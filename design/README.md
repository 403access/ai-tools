# OpenCodeBar design mirror (OpenPencil)

`OpenCodeBar.fig` is a complete visual mirror of this repository in
[OpenPencil](https://openpencil.dev): macOS, iPhone, iPad, Home Screen widgets,
the hub architecture, every important state, and the roadmap for the mirror
itself.

Open it in OpenPencil 0.16 or newer:

```sh
open -a OpenPencil design/OpenCodeBar.fig
```

The first page is an index. The numbered pages then follow the product:

| Page | Contents |
| --- | --- |
| Start here | Index, product summary and rebuild command |
| 00 | Cover, repository map, runtime topology, legend |
| 01 | Design tokens, type, components, domain specimens |
| 02 | macOS menu bar, desktop window, Live, Tasks, Settings, sheets |
| 03 | macOS sessions: chat, stats, changes, prompts, git, subagents, failure/hold |
| 04 | macOS projects, project tabs, usage pages, no-key/stale |
| 05 | macOS system, performance, media, terminals, files, VMs |
| 06 | iOS core: Live, sessions, projects, tasks, usage, settings, pairing, light |
| 07 | iOS Host, focused pages, terminals, files, Remote desktop |
| 08 | iOS VMs, widgets (small/medium/large), iPad |
| 09 | Empty, loading, error, stale, permission, long content, light |
| 10 | Architecture, request flow, API, data model, storage, security, build |
| 11 | Roadmap, milestones, current sprint, risks, definition of done |
| 12 | Coverage matrix, documentation map, changelog, rebuild steps |

## Regenerating

The `.fig` is generated from small JSX modules under `design/gen/`. Do not hand
edit the document; change the module and rebuild.

```sh
# 1. Generate JSX for every page (no app required)
node design/build.mjs

# 2. Render into the document already open in OpenPencil and save
OPENPENCIL_DOC=tab-1 node design/build.mjs --render
openpencil documents save --document-id tab-1
```

`OPENPENCIL_DOC` is the tab id from
`openpencil documents list`. Page ids are read from the open document, so the
same command works after reopening the file.

Notes:

- Each page is rendered in sections to stay under the app's 20s RPC deadline.
- Use only Lucide icon names that exist; a missing icon can stall a render.
- `design/gen/kit.mjs` holds the palette, typography and component helpers.
- Demo data is synthetic. Never put real tokens, paths or personal data in the
  design.

## Documentation

- [`ROADMAP.md`](ROADMAP.md) — phases, milestones, risks, definition of done.
- [`TODO.md`](TODO.md) — live coverage checklist.
- The README's **Design mirror** section and the docs site's
  **Development → Project layout** page point here.

## Adding a screen

1. Add a module or a section to the relevant page under `design/gen/`.
2. Use the helpers from `kit.mjs` (`panel`, `phone`, `card`, `chip`, …).
3. Add the frame to `design/TODO.md` and, if it is a new area, to the coverage
   matrix on page 12.
4. Rebuild and save. Check the page at 100% zoom and in both appearances.
