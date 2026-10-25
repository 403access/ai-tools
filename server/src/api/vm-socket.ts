import type { Server, ServerWebSocket, WebSocketHandler } from "bun";
import { createConnection, type Socket } from "node:net";
import type { HubSocketData, VMSerialSocketData } from "./socket.ts";
import { error } from "./support.ts";

/**
 * Bridges a browser/phone WebSocket to the helper's raw serial socket. The
 * helper streams guest output and accepts keyboard input as bytes, so this is a
 * straight byte pump like the terminal proxy.
 */
export class VMSockets {
  async upgrade(
    request: Request,
    server: Server<HubSocketData>,
    target: { vmID: string; host: string; port: number },
  ): Promise<Response | undefined> {
    const data: VMSerialSocketData = {
      kind: "vm-serial",
      vmID: target.vmID,
      host: target.host,
      port: target.port,
    };
    if (!server.upgrade(request, { data })) {
      return error("Could not upgrade the VM console connection", 500);
    }
    return undefined;
  }

  readonly handlers: WebSocketHandler<HubSocketData> = {
    data: {} as HubSocketData,
    idleTimeout: 0,

    open: (ws) => {
      const data = ws.data as VMSerialSocketData;
      const upstream = createConnection({ host: data.host, port: data.port });
      upstream.setNoDelay(true);
      data.upstream = upstream;

      upstream.on("connect", () => {
        if (data.closed) upstream.destroy();
      });

      upstream.on("data", (chunk: Buffer) => {
        if (data.closed) return;
        try {
          ws.send(chunk);
        } catch {
          data.closed = true;
          upstream.destroy();
        }
      });

      upstream.on("error", (caught) => {
        safeClose(ws, 1011, `console: ${caught.message}`);
      });

      upstream.on("close", () => {
        safeClose(ws, 1000, "console closed");
      });
    },

    message: (ws, message) => {
      const data = ws.data as VMSerialSocketData;
      const upstream = data.upstream;
      if (!upstream || upstream.destroyed) return;
      if (typeof message === "string") {
        upstream.write(Buffer.from(message, "utf8"));
      } else if (message instanceof ArrayBuffer) {
        upstream.write(Buffer.from(message));
      } else if (ArrayBuffer.isView(message)) {
        upstream.write(Buffer.from(message.buffer, message.byteOffset, message.byteLength));
      }
    },

    close: (ws) => {
      const data = ws.data as VMSerialSocketData;
      data.closed = true;
      const upstream: Socket | undefined = data.upstream;
      data.upstream = undefined;
      upstream?.destroy();
    },
  };
}

function safeClose(ws: ServerWebSocket<HubSocketData>, code: number, reason: string): void {
  try {
    ws.close(code, reason);
  } catch {
    try {
      ws.close();
    } catch {
      // Already closed.
    }
  }
}
