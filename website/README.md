# OpenCodeBar documentation

Docusaurus 3 source for the documentation published at
<https://403access.github.io/ai-tools/docs/>.

## Local development

The start and build scripts regenerate the Swagger API explorer from
`server/src/openapi/`, so Bun must be installed as well as Node.

```bash
npm install
npm run start
```

Open <http://localhost:3000/ai-tools/docs/>. The base path matches the published
site.

## Production build

```bash
npm run build
npm run serve
```

The combined marketing site, docs and API explorer are assembled and deployed
by `.github/workflows/deploy-pages.yml`. See
[Documentation site](docs/development/docs-site.md) for structure, linking
rules, and publishing details.
