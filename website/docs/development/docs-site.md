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

This runs `npm install` and `docusaurus start` in `website/`. Docusaurus serves
the site at:

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
  alt="OpenCodeBar Live tab"
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
2. builds Docusaurus with the `/ai-tools/docs/` base URL,
3. copies the marketing site from `docs/` to the artifact root,
4. copies the Docusaurus build to `_site/docs/`,
5. uploads the combined artifact to GitHub Pages.

In the GitHub repository, set:

**Settings → Pages → Build and deployment → Source: GitHub Actions**

The published URLs are:

- marketing site: `https://403access.github.io/ai-tools/`
- documentation: `https://403access.github.io/ai-tools/docs/`

## Updating the theme

The docs theme mirrors the marketing site: mint accent, deep green-black
surfaces, and a soft grid. Shared values live at the top of
`website/src/css/custom.css`; the marketing site variables live in
`docs/assets/style.css`.
