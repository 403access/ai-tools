import type { Server, ServerWebSocket, WebSocketHandler } from "bun";
import type { RemoteHost, RemoteStatus } from "../remote.ts";
import type { HubSocketData, RemoteSocketData } from "./socket.ts";
import { error } from "./support.ts";

/**
 * Fans one helper capture out to every connected viewer and forwards their
 * pointer and keyboard messages back to the helper.
 */
export class RemoteSockets {
  private readonly clients = new Set<ServerWebSocket<HubSocketData>>();
  private readonly unsubscribe: () => void;

  constructor(private readonly host: RemoteHost) {
    this.unsubscribe = host.subscribe((event) => {
      if (event.type === "frame") {
        this.broadcastFrame(event.data);
      } else if (event.type === "status") {
        this.broadcastJSON({ type: "status", data: event.status });
      } else {
        this.broadcastJSON({
          type: "log",
          level: event.level,
          message: event.message,
        });
      }
    });
  }

  upgrade(
    request: Request,
    server: Server<HubSocketData>,
  ): Response | undefined {
    const data: RemoteSocketData = { kind: "remote" };
    if (!server.upgrade(request, { data })) {
      return error("Could not upgrade the remote desktop connection", 500);
    }
    return undefined;
  }

  readonly handlers: WebSocketHandler<HubSocketData> = {
    data: {} as HubSocketData,
    idleTimeout: 0,

    open: (ws) => {
      const data = ws.data as RemoteSocketData;
      data.closed = false;
      this.clients.add(ws);
      this.host.addViewer();

      const status = this.host.status();
      this.sendStatus(ws, status);
      // A reconnect should paint immediately instead of waiting for the next
      // captured frame.
      const frame = this.host.latestFrame();
      if (frame) this.send(ws, frame);
    },

    message: (ws, message) => {
      const data = ws.data as RemoteSocketData;
      if (data.closed) return;
      if (typeof message !== "string") return;
      this.handle(ws, message);
    },

    close: (ws) => {
      const data = ws.data as RemoteSocketData;
      data.closed = true;
      this.clients.delete(ws);
      this.host.removeViewer();
    },
  };

  dispose(): void {
    this.unsubscribe();
    this.clients.clear();
  }

  private handle(ws: ServerWebSocket<HubSocketData>, text: string): void {
    let object: Record<string, unknown>;
    try {
      const parsed: unknown = JSON.parse(text);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return;
      object = parsed as Record<string, unknown>;
    } catch {
      return;
    }

    const type = typeof object.type === "string" ? object.type : "";
    switch (type) {
      case "pointer":
      case "scroll":
      case "key":
      case "text":
        this.host.sendInput(object);
        break;

      case "configure": {
        const input: {
          fps?: number;
          quality?: number;
          maxWidth?: number;
          displayID?: number;
        } = {};
        if (isNumber(object.fps)) input.fps = object.fps;
        if (isNumber(object.quality)) input.quality = object.quality;
        if (isNumber(object.maxWidth)) input.maxWidth = object.maxWidth;
        if (isNumber(object.displayID)) input.displayID = object.displayID;
        this.sendStatus(ws, this.host.configure(input));
        break;
      }

      case "permissions":
        this.sendStatus(
          ws,
          this.host.requestPermissions({
            screenRecording: object.screenRecording === true,
            accessibility: object.accessibility === true,
          }),
        );
        break;

      case "status":
        this.sendStatus(ws, this.host.status());
        break;

      default:
        break;
    }
  }

  private sendStatus(
    ws: ServerWebSocket<HubSocketData>,
    status: Promise<RemoteStatus> | RemoteStatus,
  ): void {
    if (status instanceof Promise) {
      void status.then((value) => this.sendStatus(ws, value));
      return;
    }
    this.broadcastJSON({ type: "status", data: status });
  }

  private broadcastJSON(payload: Record<string, unknown>): void {
    const text = JSON.stringify(payload);
    for (const client of this.clients) {
      try {
        client.send(text);
      } catch {
        // The close handler removes it.
      }
    }
  }

  private broadcastFrame(frame: Uint8Array): void {
    for (const client of this.clients) {
      if (client.getBufferedAmount() > 4_000_000) continue;
      try {
        client.send(frame);
      } catch {
        // The close handler removes it.
      }
    }
  }

  private send(ws: ServerWebSocket<HubSocketData>, data: Uint8Array): void {
    try {
      ws.send(data);
    } catch {
      // The close handler removes it.
    }
  }
}

function isNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}
