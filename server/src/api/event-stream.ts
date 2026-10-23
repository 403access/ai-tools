import type { Hub } from "../hub.ts";
import type { HubEvent } from "../types.ts";
import { CORS_HEADERS } from "./support.ts";

export function eventStream(hub: Hub, request: Request, deviceID?: string): Response {
  const encoder = new TextEncoder();
  let controller: ReadableStreamDefaultController<Uint8Array> | null = null;
  let remove: (() => void) | null = null;
  let heartbeat: ReturnType<typeof setInterval> | null = null;
  let closed = false;

  const cleanup = () => {
    if (closed) return;
    closed = true;
    if (heartbeat) clearInterval(heartbeat);
    heartbeat = null;
    remove?.();
    remove = null;
    try {
      controller?.close();
    } catch {
      // Already closed by the runtime.
    }
  };

  const send = (event: HubEvent) => {
    if (closed || !controller) return;
    try {
      controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
    } catch {
      cleanup();
    }
  };

  const stream = new ReadableStream<Uint8Array>({
    start(streamController) {
      controller = streamController;
      controller.enqueue(encoder.encode("retry: 2000\n\n"));
      remove = hub.addClient(send, deviceID);
      heartbeat = setInterval(() => {
        if (closed || !controller) return;
        try {
          controller.enqueue(encoder.encode(": ping\n\n"));
        } catch {
          cleanup();
        }
      }, 15_000);
      request.signal.addEventListener("abort", cleanup);
    },
    cancel() {
      cleanup();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
      ...CORS_HEADERS,
    },
  });
}
