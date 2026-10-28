#!/usr/bin/env bash
#
# Rebuilds and relaunches OpenCodeBar whenever Swift sources change.
#
# This is live reload, not state-preserving hot reload: every change restarts
# the app, so in-memory UI state (open panel, selected session) resets. Debug
# builds are the default because they iterate much faster.
#
# Usage:
#   Scripts/watch.sh               build (debug), launch, then watch
#   Scripts/watch.sh --no-initial  watch without the initial build
#   CONFIG=release Scripts/watch.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
INTERVAL="${INTERVAL:-0.5}"

usage() {
    cat <<'TEXT'
Watch sources and rebuild/relaunch OpenCodeBar.

Recursively watches Sources/OpenCodeBar plus Package.swift and
Package.resolved, and coalesces bursts of saves into one rebuild.

Usage:
  Scripts/watch.sh               build (debug), launch, then watch
  Scripts/watch.sh --no-initial  watch without the initial build
  CONFIG=release Scripts/watch.sh
  INTERVAL=1 Scripts/watch.sh    poll less often
  Scripts/watch.sh --help
TEXT
}

initial=1
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        --no-initial|-n) initial=0 ;;
        *) echo "watch: unknown option '$arg'" >&2; usage >&2; exit 2 ;;
    esac
done

WATCHED=(
    "$ROOT/Sources/OpenCodeBar"
    "$ROOT/Package.swift"
    "$ROOT/Package.resolved"
)

# Hash file contents rather than mtimes: APFS timestamps are too coarse to
# reliably notice two saves within the same second.
fingerprint() {
    local paths=()
    local entry
    for entry in "${WATCHED[@]}"; do
        [ -e "$entry" ] && paths+=("$entry")
    done
    find "${paths[@]}" -type f \( -name '*.swift' -o -name 'Package.swift' -o -name 'Package.resolved' \) -print0 \
        | sort -z \
        | xargs -0 shasum 2>/dev/null \
        | shasum \
        | cut -d' ' -f1
}

rebuild() {
    echo
    echo "==> Change detected at $(date '+%H:%M:%S')"
    if ! CONFIG="$CONFIG" "$ROOT/Scripts/restart.sh"; then
        echo "==> Build failed; the previous app is still running. Waiting for the next change." >&2
    fi
}

if [ "$initial" -eq 1 ]; then
    CONFIG="$CONFIG" "$ROOT/Scripts/restart.sh"
fi

last="$(fingerprint)"
echo
echo "==> Watching ${WATCHED[*]} (Ctrl-C to stop)"

while true; do
    sleep "$INTERVAL"
    current="$(fingerprint)"
    if [ "$current" = "$last" ]; then
        continue
    fi
    # Let save bursts (format-on-save, multi-file edits) settle first.
    while true; do
        sleep 0.3
        settled="$(fingerprint)"
        [ "$settled" = "$current" ] && break
        current="$settled"
    done
    last="$current"
    rebuild
done
