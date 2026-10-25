---
title: Testing
sidebar_position: 3
---

# Testing

## Swift tests

```bash
make test
```

The Swift test target covers:

- event folding into live activity,
- subagent and session ordering,
- JSON contract decoding for the hub API,
- project, usage, and terminal model shaping.

## Hub tests

```bash
make hub-test
```

The Bun tests in `server/test/` cover:

- SQLite schema, migrations, and queries,
- cached reads and message pagination,
- API routing, auth, device headers, and error responses,
- terminal routing, validation, and multi-location aggregation,
- Terminal.app tab routing, command validation, and focus,
- stats and changes aggregation.

Type-check the server:

```bash
cd server
bun run typecheck
```

## Docs build

The docs site is checked by building it:

```bash
make docs-build
```

Docusaurus is configured with `onBrokenLinks: 'throw'` and
`onBrokenMarkdownLinks: 'throw'`, so a broken internal link fails the build. The
GitHub Pages workflow runs the same command.

## Manual smoke test

1. Start `make hub`.
2. Start `make run`.
3. Confirm the menu bar item shows the hub connection.
4. Right-click the icon and confirm the compact panel opens; left-click it and
   confirm the desktop window opens (with a Dock icon). Close the window and
   confirm only the menu bar item remains.
5. Open a running session and send a prompt.
6. Create a new session with a first message.
7. Open **System → Terminals**, start a terminal, run a command, resize the
   window, close and reopen it, then stop it. Repeat from the iOS System tab;
   confirm that a terminal started from OpenCode's own terminal panel appears.
8. Open a Terminal.app window, then open it from **System → Terminal.app**.
   Confirm the text mirror updates, run a command from the field, and check the
   tab on the Mac. On first use, approve the Automation prompt.
9. Pair the iOS app and repeat the session view.
10. Stop OpenCode and confirm cached history still renders.

## CI

The Pages workflow builds the docs on pushes to `main`. It does not run the
Swift or Bun test suites; run those locally with `make test` and
`make hub-test` before changing app or server code.
