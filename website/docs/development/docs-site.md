---
title: Documentation site
sidebar_position: 6
---

# Documentation site

The docs are a Docusaurus 3 site in `website/`. They ship alongside the static
marketing page in `docs/`.

## Local development

```bash
make docs
```

This runs `npm install` and `docusaurus start` in `website/`. The `prestart`
script also regenerates the Swagger API explorer from `server/src/openapi/`, so
Bun must be available. Docusaurus serves the site at:

```text
http://localhost:3000/ai-tools/docs/
```

The base path matches production, so links and images behave the same locally.

To build and serve the production output:

```bash
make docs-build
make docs-serve
```

## Structure

```text
website/
  docusaurus.config.js   site title, URL, baseUrl, navbar, footer
  sidebars.js            documentation navigation
  docs/                  Markdown/MDX pages
  src/components/        HomeHero and Figure
  src/css/custom.css     OpenCodeBar theme
  static/img/            logo, favicon, screenshots
  static/api/             generated Swagger UI + openapi.json (not committed)
```

## Add a page

1. Create a `.md` or `.mdx` file under `website/docs/`.
2. Add front matter:

```markdown
---
title: My page
sidebar_position: 7
---
```

3. Add the doc id to `sidebars.js`.
4. Run `make docs` and check the page and its links.

## Add a screenshot

Use the shared `Figure` component:

```mdx
import Figure from '@site/src/components/Figure';

<Figure
  src="/img/screenshots/live.png"
  alt="OpenCodeBar session activity"
  caption="Running sessions on macOS"
/>
```

Put the image in `website/static/img/screenshots/`. The component applies the
Docusaurus base URL automatically.

## Search

Search is local: `@easyops-cn/docusaurus-search-local` builds an index during
`npm run build`. There is no Algolia account, API key, or external crawler.

## Link checking

`docusaurus.config.js` sets:

```js
onBrokenLinks: 'throw',
onBrokenMarkdownLinks: 'throw',
```

A broken internal link fails `make docs-build` and the Pages deployment.

## Publishing

`.github/workflows/deploy-pages.yml` runs on pushes to `main` that touch
`docs/`, `website/`, or the workflow itself.

It:

1. installs Node dependencies in `website/` with `npm ci`,
2. installs Bun, because the docs build generates the OpenAPI explorer,
3. builds Docusaurus with the `/ai-tools/docs/` base URL; `prebuild` runs
   `server/scripts/export-openapi.ts`, which writes `website/static/api/`
   (`openapi.json` plus the Swagger UI page),
4. copies the marketing site from `docs/` to the artifact root,
5. copies the Docusaurus build to `_site/docs/`,
6. uploads the combined artifact to GitHub Pages.

In the GitHub repository, set:

**Settings → Pages → Build and deployment → Source: GitHub Actions**

The published URLs are:

- marketing site: `https://403access.github.io/ai-tools/`
- documentation: `https://403access.github.io/ai-tools/docs/`
- API explorer: `https://403access.github.io/ai-tools/docs/api/` (reference
  only; run the hub for an interactive **Try it out**)

## Updating the theme

The docs theme mirrors the marketing site: mint accent, deep green-black
surfaces, and a soft grid. Shared values live at the top of
`website/src/css/custom.css`; the marketing site variables live in
`docs/assets/style.css`.
