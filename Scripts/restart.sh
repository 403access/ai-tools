#!/usr/bin/env bash
#
# Rebuilds OpenCodeBar and restarts it in one step.
#
# The build runs first, so a failed build leaves the currently running app
# untouched. The old instance is then stopped and the freshly built bundle is
# launched, waiting up to 10 seconds for it to appear.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/OpenCodeBar.app"
BINARY="$APP/Contents/MacOS/OpenCodeBar"

usage() {
    cat <<'TEXT'
Rebuild and restart OpenCodeBar.

The build runs first, so a failed build leaves the running app untouched.

Usage:
  Scripts/restart.sh              rebuild (release) and restart
  Scripts/restart.sh --no-build   restart the existing bundle
  CONFIG=debug Scripts/restart.sh rebuild debug and restart
  Scripts/restart.sh --help
TEXT
}

build=1
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            usage
            exit 0
            ;;
        --no-build|-n)
            build=0
            ;;
        *)
            echo "restart: unknown option '$arg'" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$build" -eq 1 ]; then
    "$ROOT/Scripts/build-app.sh"
elif [ ! -x "$BINARY" ]; then
    echo "restart: $APP not found; run without --no-build first" >&2
    exit 1
fi

# Stop only the bundle this script manages, not copies elsewhere on disk.
pids="$(pgrep -f "$BINARY" || true)"
if [ -n "$pids" ]; then
    echo "==> Stopping $(echo "$pids" | tr '\n' ' ' | sed 's/ *$//')"
    # shellcheck disable=SC2086 # one PID per line, splitting is intended
    kill $pids 2>/dev/null || true
    for _ in $(seq 1 50); do
        pgrep -f "$BINARY" >/dev/null 2>&1 || break
        sleep 0.1
    done
    if pgrep -f "$BINARY" >/dev/null 2>&1; then
        echo "==> Still running, forcing quit"
        pkill -9 -f "$BINARY" 2>/dev/null || true
        sleep 0.2
    fi
else
    echo "==> Not running"
fi

echo "==> Launching $APP"
open "$APP"

for _ in $(seq 1 100); do
    pid="$(pgrep -f "$BINARY" | head -n 1 || true)"
    if [ -n "$pid" ]; then
        echo "==> Running (pid $pid)"
        exit 0
    fi
    sleep 0.1
done

echo "restart: app did not start within 10s" >&2
exit 1
