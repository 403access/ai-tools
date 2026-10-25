import { describe, expect, test } from "bun:test";
import { body, request, setup } from "./helpers/api.ts";
import { swaggerPage } from "../src/openapi/swagger.ts";

interface Operation {
  tags?: string[];
  summary?: string;
  description?: string;
  operationId?: string;
  security?: unknown[];
  parameters?: Array<{ name?: string; in?: string; required?: boolean }>;
  responses?: Record<string, unknown>;
}

interface Document {
  openapi: string;
  info: { title: string; version: string };
  servers: Array<{ url: string }>;
  security: unknown[];
  tags: Array<{ name: string }>;
  paths: Record<string, Record<string, Operation> & { parameters?: Operation["parameters"] }>;
  components: {
    schemas: Record<string, unknown>;
    responses: Record<string, unknown>;
    securitySchemes: Record<string, unknown>;
  };
}

const HTTP_METHODS = ["get", "post", "put", "patch", "delete", "head", "options"];

async function loadDocument(): Promise<Document> {
  const { handler, db } = setup();
  const response = await handler(request("/api/openapi.json", {}, null));
  expect(response.status).toBe(200);
  const doc = (await body<Document>(response));
  db.close();
  return doc;
}

function operations(doc: Document): Array<{ path: string; method: string; op: Operation }> {
  const found: Array<{ path: string; method: string; op: Operation }> = [];
  for (const [path, item] of Object.entries(doc.paths)) {
    for (const [method, op] of Object.entries(item)) {
      if (HTTP_METHODS.includes(method)) {
        found.push({ path, method, op: op as Operation });
      }
    }
  }
  return found;
}

function refs(value: unknown, found = new Set<string>()): Set<string> {
  if (Array.isArray(value)) {
    for (const entry of value) refs(entry, found);
  } else if (value && typeof value === "object") {
    for (const [key, entry] of Object.entries(value)) {
      if (key === "$ref" && typeof entry === "string") found.add(entry);
      else refs(entry, found);
    }
  }
  return found;
}

function resolve(doc: Document, ref: string): unknown {
  const parts = ref.replace(/^#\//, "").split("/");
  let value: unknown = doc;
  for (const part of parts) {
    value = (value as Record<string, unknown> | undefined)?.[part];
  }
  return value;
}

describe("API documentation", () => {
  test("serves the OpenAPI document without a token", async () => {
    const { handler, db } = setup();
    const response = await handler(request("/api/openapi.json", {}, null));
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("application/json");

    const doc = (await body<Document>(response));
    expect(doc.openapi).toBe("3.0.3");
    expect(doc.info.title).toBe("OpenCodeBar Hub API");
    expect(doc.info.version).toBe("1.0.0");
    expect(doc.servers[0]?.url).toBe("/");

    // Every documented endpoint except the three public ones requires auth.
    for (const { path, op } of operations(doc)) {
      if (["/api/ping", "/api/docs", "/api/openapi.json"].includes(path)) {
        expect(op.security).toEqual([]);
      } else {
        expect(op.security).toBeUndefined();
      }
    }

    db.close();
  });

  test("serves Swagger UI without a token", async () => {
    const { handler, db } = setup();
    const response = await handler(request("/api/docs", {}, null));
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/html");
    const html = await response.text();
    expect(html).toContain("SwaggerUIBundle");
    expect(html).toContain('url: "/api/openapi.json"');
    db.close();
  });

  test("every operation is complete and identifiable", async () => {
    const doc = await loadDocument();
    const ids = new Set<string>();
    const tagNames = new Set(doc.tags.map((tag) => tag.name));

    for (const { path, method, op } of operations(doc)) {
      const label = `${method.toUpperCase()} ${path}`;
      expect(op.operationId, label).toBeTruthy();
      expect(ids.has(op.operationId!), `${label} duplicates ${op.operationId}`).toBe(false);
      ids.add(op.operationId!);
      expect(op.summary, label).toBeTruthy();
      expect(op.responses, label).toBeTruthy();
      expect(Object.keys(op.responses!).length, label).toBeGreaterThan(0);
      expect(op.tags?.length, label).toBeGreaterThan(0);
      for (const tag of op.tags ?? []) {
        expect(tagNames.has(tag), `${label} uses unknown tag ${tag}`).toBe(true);
      }
    }
    expect(ids.size).toBeGreaterThan(40);
  });

  test("every $ref resolves", async () => {
    const doc = await loadDocument();
    const found = [...refs(doc)];
    expect(found.length).toBeGreaterThan(50);
    for (const ref of found) {
      expect(ref.startsWith("#/"), `${ref} must be a local ref`).toBe(true);
      expect(resolve(doc, ref), ref).toBeDefined();
    }
  });

  test("path placeholders match path parameters", async () => {
    const doc = await loadDocument();
    for (const [path, item] of Object.entries(doc.paths)) {
      const placeholders = [...path.matchAll(/\{([^}]+)\}/g)].map((match) => match[1]!);
      for (const [method, op] of Object.entries(item)) {
        if (!HTTP_METHODS.includes(method)) continue;
        const parameters = [
          ...(item.parameters ?? []),
          ...((op as Operation).parameters ?? []),
        ].filter((parameter) => parameter.in === "path");
        const names = parameters
          .map((parameter) => parameter.name)
          .filter((name): name is string => Boolean(name));
        for (const placeholder of placeholders) {
          expect(names, `${method.toUpperCase()} ${path}`).toContain(placeholder);
        }
        for (const name of names) {
          expect(placeholders, `${method.toUpperCase()} ${path}`).toContain(name);
          expect(parameters.find((entry) => entry.name === name)?.required).toBe(true);
        }
      }
    }
  });

  test("documents the main resource groups and device headers", async () => {
    const doc = await loadDocument();
    expect(Object.keys(doc.paths)).toEqual(
      expect.arrayContaining([
        "/api/session",
        "/api/session/{id}/message",
        "/api/project",
        "/api/sync",
        "/api/event",
        "/api/terminals/{id}/socket",
        "/api/vms/{id}/{action}",
        "/api/system",
        "/api/remote",
        "/api/files",
        "/api/settings",
      ]),
    );

    // Authenticated paths advertise the optional device headers.
    const session = doc.paths["/api/session"]!;
    const headers = (session.parameters ?? []).map((parameter) => parameter.name);
    expect(headers).toContain("X-OpenCodeBar-Device-Id");
    expect(headers).toContain("X-OpenCodeBar-Platform");
    expect(doc.paths["/api/ping"]?.parameters).toBeUndefined();

    expect(doc.security).toEqual([{ bearerAuth: [] }, { queryToken: [] }]);
    expect(doc.components.securitySchemes.bearerAuth).toBeDefined();
    expect(doc.components.securitySchemes.queryToken).toBeDefined();
  });

  test("static explorer hides execute controls and takes a notice", () => {
    const html = swaggerPage({
      specUrl: "./openapi.json",
      interactive: false,
      notice: "<strong>Reference only</strong>",
    });
    expect(html).toContain('url: "./openapi.json"');
    expect(html).toContain("supportedSubmitMethods: []");
    expect(html).toContain("<strong>Reference only</strong>");
    expect(html).not.toContain("tryItOutEnabled: true");
    expect(html).not.toContain("preauthorizeApiKey");
  });

  test("rejects non-GET methods on the docs routes", async () => {
    const { handler, db } = setup();
    expect((await handler(request("/api/openapi.json", { method: "POST" }, null))).status).toBe(405);
    expect((await handler(request("/api/docs", { method: "POST" }, null))).status).toBe(405);
    db.close();
  });
});
