---
title: Go plan usage
sidebar_position: 5
---

# Go plan usage

OpenCodeBar shows the rolling (5h), weekly, and monthly windows from the
OpenCode Go usage API.

## Endpoint

```text
GET https://opencode.ai/zen/go/v1/usage
Authorization: Bearer <usage-key>
```

The hub polls this endpoint on the usage cadence (default 60s) and caches the
result for both apps. `OPENCODE_GO_USAGE_URL` overrides the endpoint for testing
or a compatible proxy.

## Key resolution

The hub looks for a key in this order:

1. `$OPENCODE_GO_USAGE_KEY`
2. `$OPENCODE_API_KEY`
3. `goUsageKey` in `~/.config/opencode/opencodebar.json`
4. the `opencode-go` key, then the `opencode` key, in
   `~/.local/share/opencode/auth.json`

For GUI-launched apps, the config file is the most reliable place:

```json
{
  "goUsageKey": "oc_sk_..."
}
```

## Use a usage-only key

A console service-account key (`oc_sk_…`, inference only) works against the
usage endpoint and lets you avoid replacing the credential OpenCode uses for
inference. Create it in the OpenCode console under **Keys → Add Service
Account → Add API Key**.

Service-account keys are shown once, so store the value immediately in
`opencodebar.json`.

## What is shown

- Rolling consumption with a reset countdown.
- Weekly consumption with a reset countdown.
- Monthly consumption with a reset countdown.
- Percentage bars and last-known values when the API is unreachable.

## What is not shown

The console's **Credits**, **Extra usage**, and **Auto-recharge** values are not
part of the usage endpoint. OpenCodeBar does not scrape the console, so those
rows stay console-only.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Plan limits hidden | No key resolved |
| `401 api_key_expired` | The `auth.json` key expired; use a service-account key |
| Stale values | The endpoint is unreachable; cached values are being shown |
| Missing credits | Those fields are not in the API |

See [Configuration](configuration.md) for all environment variables.
