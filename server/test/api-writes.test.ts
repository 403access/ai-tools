import { describe, expect, test } from "bun:test";
import { body, request, session, setup } from "./helpers/api.ts";

describe("hub API writes", () => {
  test("validates session creation and prompt bodies", async () => {
    const { handler, db } = setup();

    const noLocation = await handler(
      request("/api/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title: "Missing directory" }),
      }),
    );
    expect(noLocation.status).toBe(400);

    const noText = await handler(
      request("/api/session/ses_1/prompt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: "   " }),
      }),
    );
    expect(noText.status).toBe(400);

    const badDelivery = await handler(
      request("/api/session/ses_1/prompt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: "hello", delivery: "later" }),
      }),
    );
    expect(badDelivery.status).toBe(400);

    const wrongMethod = await handler(request("/api/session/ses_1/prompt"));
    expect(wrongMethod.status).toBe(405);

    db.close();
  });

  test("reports an offline OpenCode service for create and prompt", async () => {
    const { handler, db } = setup();

    const create = await handler(
      request("/api/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ location: { directory: "/tmp/project" } }),
      }),
    );
    expect(create.status).toBe(503);
    expect((await body<{ error: { message: string } }>(create)).error.message).toContain("offline");

    const prompt = await handler(
      request("/api/session/ses_1/prompt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: "hello", delivery: "queue" }),
      }),
    );
    expect(prompt.status).toBe(503);
    expect((await body<{ error: { message: string } }>(prompt)).error.message).toContain("offline");

    db.close();
  });

  test("serves an empty pending queue and rejects cancelling while offline", async () => {
    const { handler, db } = setup();

    const pending = await handler(request("/api/session/ses_1/pending"));
    expect(pending.status).toBe(200);
    expect(await body<{ data: unknown[] }>(pending)).toEqual({ data: [] });

    const wrongMethod = await handler(
      request("/api/session/ses_1/pending", { method: "POST" }),
    );
    expect(wrongMethod.status).toBe(405);

    const cancel = await handler(
      request("/api/session/ses_1/pending/msg_1", { method: "DELETE" }),
    );
    expect(cancel.status).toBe(503);

    db.close();
  });
});

