import { afterAll, describe, expect, test } from "bun:test";
import {
  mkdirSync,
  mkdtempSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { HostDirectory, HostFileContent } from "../src/types.ts";
import { body, request, setup } from "./helpers/api.ts";

const directory = realpathSync(mkdtempSync(join(tmpdir(), "opencodebar-files-")));
mkdirSync(join(directory, "src"));
writeFileSync(join(directory, "notes.txt"), "hello from the host\n");
writeFileSync(join(directory, "photo.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00, 0x01]));
writeFileSync(join(directory, "binary.dat"), Buffer.from([0x00, 0x01, 0x02, 0x03]));
writeFileSync(join(directory, ".hidden"), "secret");

afterAll(() => {
  rmSync(directory, { recursive: true, force: true });
});

function filesPath(path: string, endpoint = "/api/files"): string {
  return `${endpoint}?path=${encodeURIComponent(path)}`;
}

describe("host file browser", () => {
  test("lists directories first with metadata and roots", async () => {
    const { db, handler } = setup();
    const response = await handler(request(filesPath(directory)));
    expect(response.status).toBe(200);

    const listing = (await body<{ data: HostDirectory }>(response)).data;
    expect(listing.path).toBe(directory);
    expect(listing.name).toBe(directory.split("/").pop() ?? "");
    expect(listing.parent).toBeTruthy();
    expect(listing.roots.length).toBeGreaterThan(0);
    expect(listing.entries[0]?.name).toBe("src");
    expect(listing.entries[0]?.isDirectory).toBe(true);

    const notes = listing.entries.find((entry) => entry.name === "notes.txt");
    expect(notes?.kind).toBe("file");
    expect(notes?.size).toBeGreaterThan(0);
    expect(notes?.permissions).toHaveLength(9);

    const hidden = listing.entries.find((entry) => entry.name === ".hidden");
    expect(hidden?.hidden).toBe(true);
    db.close();
  });

  test("previews text, binary and image files", async () => {
    const { db, handler } = setup();

    const text = (await body<{ data: HostFileContent }>(
      await handler(request(filesPath(join(directory, "notes.txt"), "/api/files/content"))),
    )).data;
    expect(text.kind).toBe("text");
    expect(text.content).toContain("hello from the host");
    expect(text.mime).toContain("text/plain");

    const binary = (await body<{ data: HostFileContent }>(
      await handler(request(filesPath(join(directory, "binary.dat"), "/api/files/content"))),
    )).data;
    expect(binary.kind).toBe("binary");
    expect(binary.content).toBeUndefined();

    const image = (await body<{ data: HostFileContent }>(
      await handler(request(filesPath(join(directory, "photo.png"), "/api/files/content"))),
    )).data;
    expect(image.kind).toBe("image");
    expect(image.mime).toBe("image/png");

    db.close();
  });

  test("serves raw bytes with a mime type", async () => {
    const { db, handler } = setup();
    const response = await handler(
      request(filesPath(join(directory, "notes.txt"), "/api/files/raw")),
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/plain");
    expect(await response.text()).toContain("hello from the host");
    db.close();
  });

  test("rejects relative paths and missing files", async () => {
    const { db, handler } = setup();
    expect((await handler(request(filesPath("relative/path")))).status).toBe(400);
    expect((await handler(request(filesPath(join(directory, "missing"))))).status).toBe(404);
    db.close();
  });

  test("requires the bearer token", async () => {
    const { db, handler } = setup();
    expect((await handler(request(filesPath(directory), {}, null))).status).toBe(401);
    db.close();
  });
});
