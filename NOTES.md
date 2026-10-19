# Notes

Working notes for OpenCodeBar: follow-ups, known polish items, and environment
observations. Last updated 2026-10-19.

## Next steps

- **Go plan limits: credits and extra usage.** The Usage tab now shows the
  rolling / weekly / monthly windows from
  `GET https://opencode.ai/zen/go/v1/usage`. The console's *Credits*,
  *Extra usage*, and *Auto-recharge* rows are **not** in that endpoint — the
  balance is only retrievable from a console server function (upstream issue:
  "Zen API: expose credit balance in GET /zen/go/v1/usage"). Revisit if the
  endpoint grows a balance field.
- **Add controls (monitor → control).** Deliberately left out of v1, but the API
  already supports it:
  - Interrupt / stop a running session: `POST /api/session/{sessionID}/interrupt`.
  - Open a session in the TUI or a Terminal window.
  - Create a new session: `POST /api/session`.
- **Distribute properly** (optional): Developer ID signing + notarization so the
  app runs without the local ad-hoc signature.

## Known polish items

- **Plan limits redraw once a minute.** Rows re-render when the 60s poll lands,
  so the reset countdown can sit up to a minute stale. A `TimelineView` would
  tick it continuously if that ever matters.
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

- **The stored Go key is expired.** `~/.local/share/opencode/auth.json` holds an
  `opencode-go` key that the usage endpoint rejects with
  `401 {"code":"api_key_expired"}`. Inference may still work through a different
  credential path, but the Usage tab will show "Go API key expired" until a new
  key is created in Console. This is why `docs/screenshots/usage.png` was
  regenerated against a local fixture rather than the live endpoint.
- **`OPENCODE_GO_USAGE_URL`** overrides the usage endpoint and
  **`OPENCODE_API_KEY`** overrides the Go key; both exist to exercise the Plan
  limits UI without a live subscription. `make shots` will otherwise capture a
  real failure notice.
- **`~/.local/share/opencode/opencode.db` is unusually large (~3.7 GB,
  3,765,533,624 bytes).** OpenCodeBar does not read it — it uses the HTTP API
  only — but the size is worth investigating separately (candidates: `VACUUM`,
  or checking for retained snapshots / tool-output / WAL growth).
- Service discovery depends on `~/.config/opencode/service.json` and the
  `opencode` CLI. Both were confirmed present and working on this machine
  (OpenCode v2.0.32).
