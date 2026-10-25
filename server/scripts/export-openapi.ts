#!/usr/bin/env bun
/**
 * Exports the runtime OpenAPI document and a static Swagger UI page.
 *
 * Used by the docs build (`website/package.json` → `prebuild`) so the published
 * site always reflects the routes in `server/src/openapi/`. The output folder is
 * generated, not checked in.
 *
 *   bun run scripts/export-openapi.ts [output-dir]
 */

import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { OPENAPI_JSON } from "../src/openapi/document.ts";
import { swaggerPage } from "../src/openapi/swagger.ts";

const outputDir = resolve(
  process.argv[2] ?? join(import.meta.dir, "..", "..", "website", "static", "api"),
);

const html = swaggerPage({
  specUrl: "./openapi.json",
  interactive: false,
  notice:
    "This is the published API reference. To send requests, open the explorer on your hub at " +
    '<a href="http://127.0.0.1:8787/api/docs">http://127.0.0.1:8787/api/docs</a> ' +
    "(or the hub's LAN address).",
});

mkdirSync(outputDir, { recursive: true });
writeFileSync(join(outputDir, "openapi.json"), OPENAPI_JSON);
writeFileSync(join(outputDir, "index.html"), html);

const kib = Math.round(OPENAPI_JSON.length / 102.4) / 10;
console.log(`[openapi] wrote ${join(outputDir, "openapi.json")} (${kib} KiB)`);
console.log(`[openapi] wrote ${join(outputDir, "index.html")}`);
