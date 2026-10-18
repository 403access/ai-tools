# Notes

Working notes for OpenCodeBar: follow-ups, known polish items, and environment
observations. Last updated 2026-10-19.

## Next steps

- **Add controls (monitor → control).** Deliberately left out of v1, but the API
  already supports it:
  - Interrupt / stop a running session: `POST /api/session/{sessionID}/interrupt`.
  - Open a session in the TUI or a Terminal window.
  - Create a new session: `POST /api/session`.
- **Initialize git** and make an initial commit. The project is currently a
  plain SwiftPM directory, not a repository.
- **Distribute properly** (optional): Developer ID signing + notarization so the
  app runs without the local ad-hoc signature.

## Known polish items

- **Model chip truncates** long model IDs in the *Recent* list on the Live tab
  (e.g. `deepseek-v4.1-flash` competes with the project name and timestamp).
  Options: shrink the font, allow two lines, show a tooltip, or drop the variant.
- **"Today's steps" can read 0 late at night.** The stats `activity` array lags
  at the day boundary — the last entry reflects the previous day until the server
  rolls over. Options: compute today's steps locally from sessions, or relabel the
  tile as "latest day".
- **Heatmap scaling uses `max`**, so a single outlier day flattens all other
  cells. Consider a percentile cap or clamping the color scale.

## Environment observations

- **`~/.local/share/opencode/opencode.db` is unusually large (~3.7 GB,
  3,765,533,624 bytes).** OpenCodeBar does not read it — it uses the HTTP API
  only — but the size is worth investigating separately (candidates: `VACUUM`,
  or checking for retained snapshots / tool-output / WAL growth).
- Service discovery depends on `~/.config/opencode/service.json` and the
  `opencode` CLI. Both were confirmed present and working on this machine
  (OpenCode v2.0.32).
