import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { OpenCodeClient } from "../src/opencode.ts";

let server: ReturnType<typeof Bun.serve>;
let calls: string[] = [];

beforeAll(() => {
  server = Bun.serve({
    port: 0,
    fetch(request) {
      const url = new URL(request.url);
      calls.push(`${request.method} ${url.pathname}`);

      if (request.method === "GET" && url.pathname === "/api/session/ses_1/inbox") {
        return Response.json({
          data: [
            {
              id: "msg_1",
              sessionID: "ses_1",
              type: "user",
              time: { created: 1_700_000_000_000 },
              delivery: "queue",
              payload: { text: "Run the tests" },
            },
          ],
        });
      }

      if (request.method === "DELETE" && url.pathname === "/api/session/ses_1/inbox/msg_1") {
        return new Response(null, { status: 204 });
      }

      return new Response("not found", { status: 404 });
    },
  });
});

afterAll(() => {
  server.stop(true);
});

describe("OpenCode pending inputs", () => {
  test("reads admitted inputs from the inbox", async () => {
    calls = [];
    const client = new OpenCodeClient({
      url: `http://127.0.0.1:${server.port}`,
      password: "secret",
    });

    const pending = await client.pending("ses_1");
    expect(pending).toHaveLength(1);
    expect(pending[0]?.payload?.text).toBe("Run the tests");
    expect(pending[0]?.delivery).toBe("queue");
    expect(calls).toEqual(["GET /api/session/ses_1/inbox"]);
  });

  test("cancels one queued input", async () => {
    calls = [];
    const client = new OpenCodeClient({
      url: `http://127.0.0.1:${server.port}`,
      password: "secret",
    });

    await client.cancelPending("ses_1", "msg_1");
    expect(calls).toEqual(["DELETE /api/session/ses_1/inbox/msg_1"]);
  });
});
