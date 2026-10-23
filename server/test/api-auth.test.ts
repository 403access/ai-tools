import { describe, expect, test } from "bun:test";
import { body, request, setup } from "./helpers/api.ts";

describe("hub API auth", () => {
  test("ping is public and reports the hub", async () => {
    const { handler, db } = setup();
    const response = await handler(request("/api/ping", {}, null));
    expect(response.status).toBe(200);
    expect((await body<{ hub: boolean }>(response)).hub).toBe(true);
    db.close();
  });

  test("data routes require the bearer token", async () => {
    const { handler, db } = setup();
    expect((await handler(request("/api/project", {}, null))).status).toBe(401);
    expect((await handler(request("/api/project", {}, "wrong"))).status).toBe(401);
    expect((await handler(request("/api/project"))).status).toBe(200);
    db.close();
  });
});

