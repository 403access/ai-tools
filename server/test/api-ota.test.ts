import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { body, request, setup } from "./helpers/api.ts";
import { OtaBuilder } from "../src/hub/ota-build.ts";
import { OtaStore, otaManifest, otaRootFor } from "../src/hub/ota.ts";
import type { Hub } from "../src/hub.ts";
import type { Deployment, OtaArtifact, OtaBuildStatus, OtaPayload } from "../src/types.ts";

const ID = "20260101-120000-abcdef";

function tempStore(): { root: string; store: OtaStore; cleanup: () => void } {
  const root = join(mkdtempSync(join(tmpdir(), "opencodebar-ota-")), "ota");
  mkdirSync(root, { recursive: true });
  return { root, store: new OtaStore(root), cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

function publish(root: string, id = ID, createdAt = 1_767_268_800_000): OtaArtifact {
  const dir = join(root, id);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "app.ipa"), "not really an ipa");
  writeFileSync(
    join(dir, "meta.json"),
    JSON.stringify({
      id,
      title: "OpenCodeBar",
      bundleId: "dev.opencodebar.mobile",
      version: "1.4",
      build: "42",
      commitSha: "abcdef1234567890",
      branch: "main",
      worktree: "/tmp/ai-tools",
      createdAt,
    }),
  );
  return {
    id,
    title: "OpenCodeBar",
    bundleId: "dev.opencodebar.mobile",
    version: "1.4",
    build: "42",
    commitSha: "abcdef1234567890",
    branch: "main",
    worktree: "/tmp/ai-tools",
    createdAt,
  };
}

/** A builder whose script run is replaced by a function the test controls. */
function stubBuilder(
  store: OtaStore,
  publishBuild: () => Promise<void>,
  onPublished?: (artifact: OtaArtifact) => void,
): OtaBuilder {
  return new OtaBuilder({ store, build: publishBuild, onPublished });
}

describe("OTA store", () => {
  test("lists builds newest first and ignores broken directories", () => {
    const { root, store, cleanup } = tempStore();
    publish(root, "20260101-120000-aaaaaa", 1_000);
    publish(root, "20260102-120000-bbbbbb", 2_000);
    mkdirSync(join(root, "20260103-120000-cccccc"));

    expect(store.list().map((artifact) => artifact.id)).toEqual([
      "20260102-120000-bbbbbb",
      "20260101-120000-aaaaaa",
    ]);
    expect(store.latest()?.id).toBe("20260102-120000-bbbbbb");
    cleanup();
  });

  test("rejects ids that could escape the store and prunes old builds", () => {
    const { root, store, cleanup } = tempStore();
    publish(root, "20260101-120000-aaaaaa", 1_000);
    publish(root, "20260102-120000-bbbbbb", 2_000);

    expect(store.get("../../etc/passwd")).toBeNull();
    expect(store.ipaPath("../escape")).toBeNull();

    store.prune(1);
    expect(store.list().map((artifact) => artifact.id)).toEqual(["20260102-120000-bbbbbb"]);
    cleanup();
  });

  test("resolves the store next to the hub database", () => {
    const { root, cleanup } = tempStore();
    expect(otaRootFor(join(root, "..", "opencodebar-hub.sqlite"))).toBe(root);
    cleanup();
  });
});

describe("OTA manifest", () => {
  test("points at the absolute IPA URL and describes the signed app", () => {
    const artifact = publish(tempStore().root);
    const manifest = otaManifest(artifact, "https://hub.example");
    expect(manifest).toContain("<string>https://hub.example/api/deployments/ota/");
    expect(manifest).toContain("/app.ipa</string>");
    expect(manifest).toContain("<string>dev.opencodebar.mobile</string>");
    expect(manifest).toContain("<string>42</string>");
  });
});

describe("hub API OTA", () => {
  test("serves the install page, manifest and IPA without a token", async () => {
    const { root, store, cleanup } = tempStore();
    publish(root);
    const { handler, db } = setup({}, { ota: store });

    const page = await handler(request(`/api/deployments/ota/${ID}`, {}, null));
    expect(page.status).toBe(200);
    expect(page.headers.get("content-type")).toContain("text/html");
    const html = await page.text();
    expect(html).toContain("itms-services://?action=download-manifest");
    expect(html).toContain("opencodebar://pair?");
    expect(html).toContain("abcdef1");

    // The phone reaches the hub through the tunnel, so the manifest URLs must
    // use the forwarded origin rather than the loopback address.
    const tunnel = new Headers({
      host: "demo.trycloudflare.com",
      "x-forwarded-proto": "https",
    });
    const manifest = await handler(
      request(`/api/deployments/ota/${ID}/manifest.plist`, { headers: tunnel }, null),
    );
    expect(manifest.status).toBe(200);
    expect(manifest.headers.get("content-type")).toContain("application/xml");
    expect(await manifest.text()).toContain(
      "https://demo.trycloudflare.com/api/deployments/ota/",
    );

    const ipa = await handler(request(`/api/deployments/ota/${ID}/app.ipa`, {}, null));
    expect(ipa.status).toBe(200);
    expect(ipa.headers.get("content-type")).toBe("application/octet-stream");
    expect(ipa.headers.get("content-disposition")).toContain("OpenCodeBar-42.ipa");

    db.close();
    cleanup();
  });

  test("returns 404 for unknown and malformed builds", async () => {
    const { root, store, cleanup } = tempStore();
    publish(root);
    const { handler, db } = setup({}, { ota: store });

    // An unknown but well-formed id is reported as missing to the phone.
    expect(
      (await handler(request("/api/deployments/ota/20990101-000000-ffffff", {}, null))).status,
    ).toBe(404);

    // Anything that is not the exact public shape falls through to the
    // authenticated router, so it does not reveal whether a file exists.
    for (const path of [
      "/api/deployments/ota/..%2F..%2Fetc",
      `/api/deployments/ota/${ID}/manifest.plist/more`,
    ]) {
      expect((await handler(request(path, {}, null))).status).toBe(401);
    }

    db.close();
    cleanup();
  });

  test("lists published builds and the idle build state", async () => {
    const { root, store, cleanup } = tempStore();
    publish(root);
    const { handler, db } = setup({}, { ota: store });

    const response = await handler(request("/api/deployments/ota"));
    expect(response.status).toBe(200);
    const payload = await body<{ data: OtaPayload }>(response);
    expect(payload.data.latest?.id).toBe(ID);
    expect(payload.data.builds).toHaveLength(1);
    expect(payload.data.build.state).toBe("idle");

    db.close();
    cleanup();
  });

  test("runs one build at a time and exposes its progress", async () => {
    const { root, store, cleanup } = tempStore();
    let finish: (() => void) | null = null;
    let hubRef: Hub | null = null;
    const published: OtaArtifact[] = [];
    const builder = stubBuilder(
      store,
      () =>
        new Promise<void>((resolve) => {
          finish = () => {
            publish(root, "20260105-120000-dddddd", 5_000);
            resolve();
          };
        }),
      (artifact) => {
        published.push(artifact);
        hubRef?.broadcast({ type: "hub.ota", data: { id: artifact.id } });
      },
    );
    const { handler, db, hub } = setup({}, { ota: store, otaBuild: builder });
    hubRef = hub;

    const events: string[] = [];
    const unsubscribe = hub.addClient((event) => events.push(event.type));

    const start = await handler(request("/api/deployments/ota/build", { method: "POST" }));
    expect(start.status).toBe(202);
    expect((await body<{ data: OtaBuildStatus }>(start)).data.state).toBe("running");

    const busy = await handler(request("/api/deployments/ota/build", { method: "POST" }));
    expect(busy.status).toBe(409);

    finish!();
    for (let i = 0; i < 50 && builder.busy; i += 1) await Bun.sleep(5);

    const status = await body<{ data: OtaBuildStatus }>(
      await handler(request("/api/deployments/ota/build")),
    );
    expect(status.data.state).toBe("succeeded");
    expect(status.data.artifact?.id).toBe("20260105-120000-dddddd");
    expect(published.map((artifact) => artifact.id)).toEqual(["20260105-120000-dddddd"]);

    // The hub broadcasts the new build so connected apps can prompt.
    expect(events).toContain("hub.ota");
    unsubscribe();

    db.close();
    cleanup();
  });

  test("reports a failed build without keeping the builder busy", async () => {
    const { store, cleanup } = tempStore();
    const builder = stubBuilder(store, async () => {
      throw new Error("codesign failed");
    });
    const { handler, db } = setup({}, { ota: store, otaBuild: builder });

    const start = await handler(request("/api/deployments/ota/build", { method: "POST" }));
    expect(start.status).toBe(202);
    for (let i = 0; i < 50 && builder.busy; i += 1) await Bun.sleep(5);

    const status = await body<{ data: OtaBuildStatus }>(
      await handler(request("/api/deployments/ota/build")),
    );
    expect(status.data.state).toBe("failed");
    expect(status.data.error).toBe("codesign failed");
    expect(builder.busy).toBe(false);

    db.close();
    cleanup();
  });

  test("returns 503 when the source checkout is missing", async () => {
    const { store, cleanup } = tempStore();
    const builder = new OtaBuilder({
      store,
      scriptPath: join(store.root, "does-not-exist.sh"),
      repoRoot: store.root,
    });
    const { handler, db } = setup({}, { ota: store, otaBuild: builder });

    const response = await handler(request("/api/deployments/ota/build", { method: "POST" }));
    expect(response.status).toBe(503);
    expect(builder.busy).toBe(false);

    db.close();
    cleanup();
  });

  test("rejects non-GET/POST verbs on the build route", async () => {
    const { store, cleanup } = tempStore();
    const { handler, db } = setup({}, { ota: store });
    expect((await handler(request("/api/deployments/ota/build", { method: "DELETE" }))).status).toBe(405);
    db.close();
    cleanup();
  });

  test("accepts an OTA install report", async () => {
    const { root, store, cleanup } = tempStore();
    publish(root);
    const { handler, db } = setup({}, { ota: store });

    const response = await handler(
      request("/api/deployments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          deviceKey: "00008101-001971222298001E",
          deviceName: "Oli's iPhone",
          bundleId: "dev.opencodebar.mobile",
          version: "1.4",
          build: "42",
          source: "ota",
        }),
      }),
    );
    expect(response.status).toBe(201);
    expect((await body<{ data: Deployment }>(response)).data.source).toBe("ota");

    db.close();
    cleanup();
  });
});
