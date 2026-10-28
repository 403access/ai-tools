# OpenPencil design mirror — roadmap

Status: **complete for the first mirror**. The source of truth for the design is
`design/OpenCodeBar.fig`; this file tracks what the document covers and what is
still missing. Update this file and [`TODO.md`](TODO.md) after every build pass.

Last updated: 2026-10-27 (all phases complete)

## Goal

Mirror the OpenCodeBar repository completely in an OpenPencil project so the
product can be reviewed, demoed, and extended visually:

- every surface: macOS menu bar, compact panel, desktop window, iPhone, iPad,
  Home Screen widgets, hub, website and docs;
- every feature area: Tasks, Live, Sessions, Projects, Usage, System, Remote
  desktop, Terminals, Files, Virtual machines, Settings, Developer tools;
- every state: populated lists, empty lists, loading, errors, offline/stale
  cache, permissions, long content, dark and light appearance;
- demo data that is realistic enough to show the product without a hub;
- architecture, API, data model, roadmap, coverage and documentation pages so
  the file is also the project's visual source of truth.

## Phases

| Phase | Scope | Status |
| --- | --- | --- |
| 0 | Foundations: design tokens, typography, components, page skeleton | ✅ done |
| 1 | macOS: menu bar, panel shell, Live, Tasks, Settings | ✅ done |
| 2 | macOS: sessions, projects, usage, system, VMs | ✅ done |
| 3 | iOS: core tabs, sessions, projects, tasks, usage, settings | ✅ done |
| 4 | iOS: Host, Remote desktop, terminals, files | ✅ done |
| 5 | iOS: VMs, widgets, iPad, light mode | ✅ done |
| 6 | States and edge cases, architecture, roadmap, coverage | ✅ done |
| 7 | Documentation updates and final review | ✅ done |

## Milestones

- **M1 — Reviewable shell.** Cover, design system and macOS Live/Tasks demo
  screens open in OpenPencil and export cleanly.
- **M2 — Full macOS surface.** Every macOS tab and sheet has a populated and an
  empty/error frame.
- **M3 — Full mobile surface.** Every iOS tab, sheet, widget and the Host/Remote
  flow are covered.
- **M4 — State coverage.** A single page proves empty, loading, error, stale,
  permission and light-mode states.
- **M5 — Project memory.** Architecture, API, roadmap and coverage pages match
  the repository and the docs site.

## Risks

| Risk | Mitigation |
| --- | --- |
| Design drifts from the SwiftUI source | Screen captions name the source file; rebuild from `design/gen` |
| Demo data looks like real user data | All names, paths and tokens are synthetic (`~/Developer/...`) |
| Document becomes too large for one page | One OpenPencil page per product area, screens laid out in labelled rows |
| Generated JSX is hard to maintain | Small helper kit (`design/gen/kit.mjs`) and one module per page |

## Rendering constraints

- Pages 05 and 07 use independent top-level frames because a single large
  `Page` frame did not paint in OpenPencil's canvas. The exporter was unaffected.
- Performance bars are rectangles with pixel heights, never percentage-height
  frames; the latter produced invalid 100×100 nodes and blank canvas groups.

## Definition of done

- `design/OpenCodeBar.fig` opens in OpenPencil 0.16 with all pages.
- `node design/build.mjs` regenerates every page.
- `design/TODO.md` has no unchecked coverage items.
- README and `website/docs/development/project-layout.md` mention the design.
