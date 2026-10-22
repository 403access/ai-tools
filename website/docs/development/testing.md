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
- project and usage model shaping.

## Hub tests

```bash
make hub-test
```

The Bun tests in `server/test/` cover:

- SQLite schema, migrations, and queries,
- cached reads and message pagination,
- API routing, auth, device headers, and error responses,
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
4. Open a running session and send a prompt.
5. Create a new session with a first message.
6. Pair the iOS app and repeat the session view.
7. Stop OpenCode and confirm cached history still renders.

## CI

The Pages workflow builds the docs on pushes to `main`. It does not run the
Swift or Bun test suites; run those locally with `make test` and
`make hub-test` before changing app or server code.
