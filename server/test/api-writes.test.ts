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

  test("validates repository clone requests", async () => {
    const { handler, db } = setup();
    const headers = { "Content-Type": "application/json" };

    const missingBody = await handler(
      request("/api/git/clone", { method: "POST", headers }),
    );
    expect(missingBody.status).toBe(400);

    const missingURL = await handler(
      request("/api/git/clone", {
        method: "POST",
        headers,
        body: JSON.stringify({ parent: "/tmp" }),
      }),
    );
    expect(missingURL.status).toBe(400);

    const badURL = await handler(
      request("/api/git/clone", {
        method: "POST",
        headers,
        body: JSON.stringify({ url: "--upload-pack=evil" }),
      }),
    );
    expect(badURL.status).toBe(400);

    const wrongMethod = await handler(request("/api/git/clone"));
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

  test("validates fork, model, and agent bodies", async () => {
    const { handler, db } = setup();

    const missingModel = await handler(
      request("/api/session/ses_1/model", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model: { id: "only-id" } }),
      }),
    );
    expect(missingModel.status).toBe(400);

    const missingAgent = await handler(
      request("/api/session/ses_1/agent", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ agent: "  " }),
      }),
    );
    expect(missingAgent.status).toBe(400);

    const wrongMethod = await handler(request("/api/session/ses_1/fork"));
    expect(wrongMethod.status).toBe(405);

    const catalog = await handler(request("/api/model"));
    expect(catalog.status).toBe(503);

    const agents = await handler(request("/api/agent"));
    expect(agents.status).toBe(503);

    db.close();
  });

  test("reports an offline service for fork and settings switches", async () => {
    const { handler, db } = setup();
    const headers = { "Content-Type": "application/json" };

    for (const [path, payload] of [
      ["/api/session/ses_1/fork", {}],
      ["/api/session/ses_1/model", { model: { id: "m", providerID: "p" } }],
      ["/api/session/ses_1/agent", { agent: "build" }],
    ] as const) {
      const response = await handler(
        request(path, { method: "POST", headers, body: JSON.stringify(payload) }),
      );
      expect(response.status).toBe(503);
    }

    db.close();
  });
});

