/**
 * Shared Swagger UI page used by the live hub and by the published docs site.
 *
 * The docs build renders `interactive: false`, which hides the Execute buttons:
 * the static GitHub Pages copy has no hub behind it, so "Try it out" would send
 * requests to the docs origin. The hub's own page keeps them enabled and can
 * pre-authorize from `?token=…`.
 */

export interface SwaggerPageOptions {
  /** OpenAPI document URL, relative to the page. */
  specUrl: string;
  /** Enables Execute buttons and the `?token=` prefill. */
  interactive?: boolean;
  /** Trusted HTML rendered above the explorer. */
  notice?: string;
}

const SWAGGER_VERSION = "5";

export function swaggerPage(options: SwaggerPageOptions): string {
  const interactive = options.interactive ?? true;
  const notice = options.notice ? `<div class="notice">${options.notice}</div>` : "";
  const execute = interactive
    ? `          tryItOutEnabled: true,`
    : `          tryItOutEnabled: false,\n          supportedSubmitMethods: [],`;
  const preauthorize = interactive
    ? `
        // ?token=… pre-authorizes the explorer, so a bookmark can run
        // authenticated "Try it out" requests directly.
        const token = new URLSearchParams(window.location.search).get("token");`
    : "";
  const onComplete = interactive
    ? `
          onComplete: function () {
            if (token && window.ui) window.ui.preauthorizeApiKey("bearerAuth", token);
          },`
    : "";

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>OpenCodeBar Hub API</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@${SWAGGER_VERSION}/swagger-ui.css" />
    <style>
      html { box-sizing: border-box; overflow-y: scroll; }
      *, *::before, *::after { box-sizing: inherit; }
      body { margin: 0; background: #fafafa; }
      .swagger-ui .topbar { background-color: #1f2430; }
      .swagger-ui .topbar .download-url-wrapper { display: none; }
      .notice { max-width: 60rem; margin: 1.25rem auto 0; padding: 0.85rem 1.1rem;
        border: 1px solid #d9dde5; border-radius: 8px; background: #fff;
        font: 14px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #3c4557; }
      .notice a { color: #2563eb; }
      #fallback { display: none; max-width: 42rem; margin: 4rem auto; padding: 0 1.5rem;
        font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #1f2430; }
      #fallback code { background: #eceef2; border-radius: 4px; padding: 0.1em 0.35em; }
      #fallback a { color: #2563eb; }
    </style>
  </head>
  <body>
    ${notice}
    <div id="swagger-ui"></div>
    <div id="fallback">
      <h1>OpenCodeBar Hub API</h1>
      <p>
        The interactive explorer could not load its assets from the CDN. The
        specification is still available at
        <a href="${options.specUrl}"><code>${options.specUrl}</code></a>; open
        that file in any OpenAPI viewer, or paste it into
        <a href="https://editor.swagger.io">editor.swagger.io</a>.
      </p>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@${SWAGGER_VERSION}/swagger-ui-bundle.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@${SWAGGER_VERSION}/swagger-ui-standalone-preset.js"></script>
    <script>${preauthorize}
      if (!window.SwaggerUIBundle) {
        document.getElementById("swagger-ui").style.display = "none";
        document.getElementById("fallback").style.display = "block";
      } else {
        window.ui = SwaggerUIBundle({
          url: ${JSON.stringify(options.specUrl)},
          dom_id: "#swagger-ui",
          deepLinking: true,
          docExpansion: "none",
          filter: true,
          persistAuthorization: true,
          displayRequestDuration: true,
${execute}
          presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],
          plugins: [SwaggerUIBundle.plugins.DownloadUrl],
          layout: "StandaloneLayout",${onComplete}
        });
      }
    </script>
  </body>
</html>
`;
}
