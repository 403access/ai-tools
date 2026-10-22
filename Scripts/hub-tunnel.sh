#!/usr/bin/env bash
#
# Expose the running hub through a Cloudflare quick tunnel so the iPhone/iPad
# can reach it from cellular or any network where the Mac is not directly
# reachable (USB tethering does not route back to the tethered Mac).
#
#   Scripts/hub-tunnel.sh
#   make hub-tunnel
#
# The quick tunnel needs no Cloudflare account, but the URL is random and lives
# only as long as this process. The script writes the URL to
# ~/.config/opencode/opencodebar-hub-tunnel.json so `make mobile-device` can
# pair the phone with it automatically while the tunnel is running.
set -euo pipefail

HUB_CONFIG="${HUB_CONFIG:-$HOME/.config/opencode/opencodebar-hub.json}"
TUNNEL_CONFIG="${OPENCODEBAR_TUNNEL_CONFIG:-$HOME/.config/opencode/opencodebar-hub-tunnel.json}"
LOG="${TMPDIR:-/tmp}/opencodebar-tunnel.log"

usage() {
    cat <<'TEXT'
Expose the OpenCodeBar hub through a Cloudflare quick tunnel.

Usage:
  Scripts/hub-tunnel.sh            start a quick tunnel and print the pairing link
  Scripts/hub-tunnel.sh --help

Environment:
  OPENCODEBAR_HUB_PORT   Hub port to tunnel (otherwise read from the hub config)
  HUB_CONFIG             Hub config path (default ~/.config/opencode/opencodebar-hub.json)
  OPENCODEBAR_TUNNEL_CONFIG
                         Where to write the tunnel URL
                         (default ~/.config/opencode/opencodebar-hub-tunnel.json)

The tunnel is public while it runs. The hub still requires its Bearer token.
Press Ctrl-C to stop it; the URL stops working immediately.
TEXT
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "hub-tunnel: unknown option '$1'" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! command -v cloudflared >/dev/null 2>&1; then
    cat >&2 <<'TEXT'
hub-tunnel: cloudflared is not installed.
Install it with `brew install cloudflared`, or use Tailscale instead and pair
the phone with the Mac's Tailscale address.
TEXT
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "hub-tunnel: curl is required." >&2
    exit 1
fi

port="${OPENCODEBAR_HUB_PORT:-}"
token=""
if [ -f "$HUB_CONFIG" ]; then
    if [ -z "$port" ]; then
        port="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("port", ""))' "$HUB_CONFIG")"
    fi
    token="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("token", ""))' "$HUB_CONFIG")"
fi
if [ -z "$port" ]; then
    echo "hub-tunnel: no hub port found. Start the hub first (make hub), or set OPENCODEBAR_HUB_PORT." >&2
    exit 1
fi
if [ -z "$token" ]; then
    echo "hub-tunnel: no hub token found in $HUB_CONFIG." >&2
    exit 1
fi

if ! curl -fsS -m 3 "http://127.0.0.1:${port}/api/ping" >/dev/null 2>&1; then
    echo "hub-tunnel: no hub answered at http://127.0.0.1:${port}. Start it with make hub." >&2
    exit 1
fi

cleanup() {
    trap - INT TERM EXIT
    if [ -n "${cloudflared_pid:-}" ] && kill -0 "$cloudflared_pid" 2>/dev/null; then
        kill -TERM "$cloudflared_pid" 2>/dev/null || true
        for _ in $(seq 1 50); do
            kill -0 "$cloudflared_pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$cloudflared_pid" 2>/dev/null; then
            kill -KILL "$cloudflared_pid" 2>/dev/null || true
        fi
        wait "$cloudflared_pid" 2>/dev/null || true
    fi
    # Only remove the record if it still belongs to this tunnel.
    if [ -f "$TUNNEL_CONFIG" ] && [ -n "${cloudflared_pid:-}" ]; then
        recorded_pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("pid", ""))' "$TUNNEL_CONFIG" 2>/dev/null || true)"
        if [ "$recorded_pid" = "$cloudflared_pid" ]; then
            rm -f "$TUNNEL_CONFIG"
        fi
    fi
    echo ""
    echo "Tunnel stopped."
}
trap cleanup EXIT INT TERM

rm -f "$LOG"
cloudflared tunnel --url "http://127.0.0.1:${port}" --no-autoupdate >"$LOG" 2>&1 &
cloudflared_pid=$!

url=""
for _ in $(seq 1 150); do
    if ! kill -0 "$cloudflared_pid" 2>/dev/null; then
        echo "hub-tunnel: cloudflared exited before the tunnel was ready." >&2
        tail -20 "$LOG" >&2 || true
        exit 1
    fi
    url="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" | head -1 || true)"
    [ -n "$url" ] && break
    sleep 0.2
done

if [ -z "$url" ]; then
    echo "hub-tunnel: timed out waiting for a tunnel URL." >&2
    tail -20 "$LOG" >&2 || true
    exit 1
fi

# The hostname can take a few seconds to resolve after it is printed.
ready=0
for _ in $(seq 1 20); do
    if curl -fsS -m 5 "${url}/api/ping" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 0.5
done
if [ "$ready" -ne 1 ]; then
    echo "hub-tunnel: the tunnel URL is up but /api/ping did not answer yet." >&2
    echo "hub-tunnel: it may still become reachable in a moment: $url" >&2
fi

python3 - "$TUNNEL_CONFIG" "$url" "$port" "$cloudflared_pid" <<'PY'
import datetime
import json
import os
import sys

path, url, port, pid = sys.argv[1:5]
payload = {
    "url": url,
    "port": int(port),
    "pid": int(pid),
    "startedAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
}
os.makedirs(os.path.dirname(path), exist_ok=True, mode=0o700)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
os.chmod(path, 0o600)
PY

pairing="$(
    URL="$url" TOKEN="$token" python3 - <<'PY'
import os
import urllib.parse

url = os.environ["URL"]
token = os.environ["TOKEN"]
print("opencodebar://pair?url=" + urllib.parse.quote(url, safe="") + "&token=" + urllib.parse.quote(token, safe=""))
PY
)"

echo ""
echo "  OpenCodeBar tunnel"
echo "  ─────────────────────────────────────────────"
echo "  Hub        http://127.0.0.1:${port}"
echo "  Public     ${url}"
echo "  Config     ${TUNNEL_CONFIG}"
echo "  Pairing    ${pairing}"
echo ""
echo "  Keep this process running. On the phone, use the URL above (or run"
echo "  make mobile-device, which picks it up automatically)."
echo "  Press Ctrl-C to stop the tunnel."
echo ""

wait "$cloudflared_pid"
