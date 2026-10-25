/**
 * The hub's OpenAPI 3.0 document.
 *
 * The spec is assembled from `paths.ts` and `schemas.ts` and served verbatim by
 * `GET /api/openapi.json`; Swagger UI at `/api/docs` consumes it directly.
 * Keeping it in code (instead of a checked-in YAML file) means the docs ship
 * with the server and cannot drift from the source tree unnoticed.
 */

import { HUB_VERSION } from "../config.ts";
import {
  DEVICE_HEADER_PARAMETERS,
  PATHS,
  PUBLIC_PATHS,
} from "./paths.ts";
import { SCHEMAS } from "./schemas.ts";

const TAGS = [
  { name: "Health", description: "Liveness, version, and connection health." },
  { name: "Sessions", description: "Cached OpenCode sessions, messages, prompts, and stats." },
  { name: "Projects", description: "Projects, aggregated changes, files, and icons." },
  { name: "Events & sync", description: "Live Server-Sent Events and the incremental sync feed." },
  { name: "Usage", description: "Go plan usage windows and global statistics." },
  { name: "Terminals", description: "OpenCode PTYs proxied by the hub." },
  { name: "Host terminals", description: "Tabs already open in Terminal.app on the hub host." },
  { name: "Virtual machines", description: "Declarative NixOS guests driven by the VZ helper." },
  { name: "Remote desktop", description: "Screen capture and input relay for the iOS app." },
  { name: "Host files", description: "Read-only browsing of the hub host's filesystem." },
  { name: "System", description: "Host inventory, installed apps, and media controls." },
  { name: "Devices", description: "Mac and iOS clients that have connected to this hub." },
  { name: "Settings", description: "Hub behaviour that can be tuned without a restart." },
  { name: "Documentation", description: "This specification and its interactive explorer." },
];

const RESPONSES = {
  Unauthorized: {
    description: "Missing or invalid hub token.",
    content: {
      "application/json": {
        schema: {
          type: "object",
          properties: { error: { type: "object", properties: { message: { type: "string" } } } },
        },
        example: { error: { message: "Unauthorized", code: "unauthorized" } },
      },
    },
  },
  BadRequest: {
    description: "The request body or parameters are invalid.",
    content: { "application/json": { schema: { $ref: "#/components/schemas/ErrorResponse" } } },
  },
  Forbidden: {
    description: "The path is blocked or cannot be read.",
    content: { "application/json": { schema: { $ref: "#/components/schemas/ErrorResponse" } } },
  },
  NotFound: {
    description: "The requested resource does not exist.",
    content: { "application/json": { schema: { $ref: "#/components/schemas/ErrorResponse" } } },
  },
  ServiceUnavailable: {
    description: "The feature is not supported by this hub build or the upstream service is not ready.",
    content: { "application/json": { schema: { $ref: "#/components/schemas/ErrorResponse" } } },
  },
  Error: {
    description: "Unexpected hub, OpenCode, or host error.",
    content: { "application/json": { schema: { $ref: "#/components/schemas/ErrorResponse" } } },
  },
};

const SECURITY_SCHEMES = {
  bearerAuth: {
    type: "http",
    scheme: "bearer",
    description: "Hub token from `~/.config/opencode/opencodebar-hub.json`.",
  },
  queryToken: {
    type: "apiKey",
    in: "query",
    name: "token",
    description: "Hub token as a query parameter, for SSE and WebSocket clients that cannot set headers.",
  },
};

function documentPaths(): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [pathname, item] of Object.entries(PATHS) as Array<[string, Record<string, unknown>]>) {
    if (PUBLIC_PATHS.includes(pathname)) {
      result[pathname] = item;
      continue;
    }
    // Device headers are optional on every authenticated route, so declare
    // them once at the path level rather than repeating them per operation.
    result[pathname] = { ...item, parameters: DEVICE_HEADER_PARAMETERS };
  }
  return result;
}

export const OPENAPI_DOCUMENT = {
  openapi: "3.0.3",
  info: {
    title: "OpenCodeBar Hub API",
    version: HUB_VERSION,
    description:
      "The hub caches the local OpenCode service and serves the macOS and iOS apps " +
      "from one shared history.\n\n" +
      "**Authentication** — every endpoint except `GET /api/ping`, `GET /api/docs`, and " +
      "`GET /api/openapi.json` requires the hub token as `Authorization: Bearer <token>`. " +
      "SSE and WebSocket clients may pass `?token=<token>` instead.\n\n" +
      "**Responses** — JSON endpoints use `Cache-Control: no-store`; most collections wrap " +
      "their payload in `{ \"data\": … }`. Errors use `{ \"error\": { \"message\": … } }`.\n\n" +
      "**Device headers** — clients may send the `X-OpenCodeBar-*` headers so the Settings " +
      "screen can list connected devices.",
  },
  servers: [
    { url: "/", description: "This hub" },
  ],
  tags: TAGS,
  externalDocs: {
    description: "OpenCodeBar Hub guide",
    url: "https://403access.github.io/ai-tools/docs/hub/api",
  },
  security: [{ bearerAuth: [] }, { queryToken: [] }],
  paths: documentPaths(),
  components: {
    securitySchemes: SECURITY_SCHEMES,
    schemas: SCHEMAS,
    responses: RESPONSES,
  },
} as const;

/** Pretty-printed spec, serialized once so each request stays cheap. */
export const OPENAPI_JSON = `${JSON.stringify(OPENAPI_DOCUMENT, null, 2)}\n`;
