import { CORS_HEADERS } from "./support.ts";
import { OPENAPI_JSON } from "../openapi/document.ts";
import { swaggerPage } from "../openapi/swagger.ts";

/**
 * Swagger UI assets are loaded from jsDelivr. The hub deliberately has no
 * runtime dependencies, and bundling the UI would add ~1.5 MB to every hub
 * checkout for a page only used during development. If the CDN is unreachable
 * the page explains where to get the raw spec instead of failing silently.
 */
export const DOCS_HTML = swaggerPage({
  specUrl: "/api/openapi.json",
  interactive: true,
});

export function docsResponse(): Response {
  return new Response(DOCS_HTML, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      ...CORS_HEADERS,
    },
  });
}

export function openApiResponse(): Response {
  return new Response(OPENAPI_JSON, {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...CORS_HEADERS,
    },
  });
}
