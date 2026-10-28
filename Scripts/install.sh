#!/usr/bin/env bash
#
# Installs the built OpenCodeBar.app into ~/Applications so Spotlight, Raycast
# and "Open with" can find it.
#
# dist/ stays the build output. This copies the bundle to a stable, indexed
# location, re-signs it ad hoc, and re-registers it with Launch Services so the
# index points at the installed copy instead of a bundle that `rm -rf` recreates
# on every build.
#
# The app is a menu bar agent (LSUIElement), so it never appears in Launchpad or
# Cmd-Tab; Spotlight and Raycast still find it as an application.
#
# Usage:
#   Scripts/install.sh                 build (release), install, relaunch
#   Scripts/install.sh --no-build      install the existing dist/ bundle
#   Scripts/install.sh --no-restart    install without relaunching
#   Scripts/install.sh --uninstall     stop, remove, unregister
#   CONFIG=debug Scripts/install.sh    install a debug bundle
#   INSTALL_DIR=/Applications Scripts/install.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="OpenCodeBar"
BUNDLE="$ROOT/dist/$APP_NAME.app"
DEST_DIR="${INSTALL_DIR:-$HOME/Applications}"
DEST="$DEST_DIR/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

usage() {
    cat <<'TEXT'
Install OpenCodeBar into ~/Applications for Spotlight and Raycast.

dist/ remains the build output; this copies the bundle to a stable path,
re-registers it with Launch Services, and nudges the Spotlight index.

Usage:
  Scripts/install.sh                 build (release), install, relaunch
  Scripts/install.sh --no-build      install the existing dist/ bundle
  Scripts/install.sh --no-restart    install without relaunching
  Scripts/install.sh --uninstall     stop, remove, unregister
  CONFIG=debug Scripts/install.sh    install a debug bundle
  INSTALL_DIR=/Applications Scripts/install.sh
TEXT
}

build=1
restart=1
uninstall=0
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            usage
            exit 0
            ;;
        --no-build|-n)
            build=0
            ;;
        --no-restart)
            restart=0
            ;;
        --uninstall)
            uninstall=1
            ;;
        *)
            echo "install: unknown option '$arg'" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# The app may be running from either location: dist/ during development, the
# installed copy when it was started from Spotlight or Raycast.
stop_instances() {
    local binary pids
    for binary in "$@"; do
        [ -n "$binary" ] || continue
        pids="$(pgrep -f "$binary" || true)"
        [ -n "$pids" ] || continue
        echo "==> Stopping $(echo "$pids" | tr '\n' ' ' | sed 's/ *$//') ($binary)"
        # shellcheck disable=SC2086 # one PID per line, splitting is intended
        kill $pids 2>/dev/null || true
        for _ in $(seq 1 50); do
            pgrep -f "$binary" >/dev/null 2>&1 || break
            sleep 0.1
        done
        if pgrep -f "$binary" >/dev/null 2>&1; then
            echo "==> Still running, forcing quit"
            pkill -9 -f "$binary" 2>/dev/null || true
            sleep 0.2
        fi
    done
}

launch_installed() {
    local binary="$DEST/Contents/MacOS/$APP_NAME"
    echo "==> Launching $DEST"
    open "$DEST"
    for _ in $(seq 1 100); do
        if pgrep -f "$binary" >/dev/null 2>&1; then
            echo "==> Running (pid $(pgrep -f "$binary" | head -n 1))"
            return 0
        fi
        sleep 0.1
    done
    echo "install: app did not start within 10s" >&2
    return 1
}

if [ "$uninstall" -eq 1 ]; then
    stop_instances "$DEST/Contents/MacOS/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
    if [ ! -e "$DEST" ]; then
        echo "==> Nothing installed at $DEST"
        exit 0
    fi
    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -u "$DEST" >/dev/null 2>&1 || true
    fi
    rm -rf "$DEST"
    echo "==> Removed $DEST"
    exit 0
fi

if [ "$build" -eq 1 ]; then
    CONFIG="$CONFIG" "$ROOT/Scripts/build-app.sh"
elif [ ! -d "$BUNDLE" ]; then
    echo "install: $BUNDLE not found; run without --no-build first" >&2
    exit 1
fi

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$BUNDLE/Contents/Info.plist" 2>/dev/null || true)"

# Quit before swapping the bundle: replacing a running app leaves the live
# process on the old binary and confuses code signing checks.
stop_instances "$BUNDLE/Contents/MacOS/$APP_NAME" "$DEST/Contents/MacOS/$APP_NAME"

mkdir -p "$DEST_DIR"
STAGING="$DEST_DIR/.$APP_NAME.app.installing.$$"
trap 'rm -rf "$STAGING"' EXIT

echo "==> Installing $DEST"
rm -rf "$STAGING"
ditto "$BUNDLE" "$STAGING"

# Ad-hoc signature so the copy launches cleanly without a Developer ID.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$STAGING" >/dev/null 2>&1 || echo "  (codesign skipped)"
fi

rm -rf "$DEST"
mv "$STAGING" "$DEST"
# A fresh mtime makes Spotlight re-read the bundle after an in-place upgrade.
touch "$DEST"

if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
fi
# Nudge the metadata index; harmless when it already knows the bundle.
mdimport "$DEST" >/dev/null 2>&1 || true

echo "==> Registered $BUNDLE_ID at $DEST"

# Other checkouts (worktrees, an old dist/ path) share the bundle id. They do
# not stop Spotlight or Raycast from finding the installed copy, but it is worth
# knowing about when a launch picks the wrong one. Launch Services is the
# authoritative list; the Spotlight index lags behind a fresh install.
if [ -n "$BUNDLE_ID" ] && [ -x "$LSREGISTER" ]; then
    others=()
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ "$path" = "$DEST" ] && continue
        [ -e "$path" ] || continue
        others+=("$path")
    done < <("$LSREGISTER" -dump 2>/dev/null \
        | awk -v id="$BUNDLE_ID" '/^path:/{p=$2} /^identifier:/{if ($2==id) print p}' \
        | sort -u)
    if [ "${#others[@]}" -gt 0 ]; then
        echo "==> Other bundles with this id ($BUNDLE_ID):"
        printf '    %s\n' "${others[@]}"
        echo "    Raycast may list them separately if you added their folders."
    fi
fi

if [ "$restart" -eq 1 ]; then
    launch_installed
fi

echo "==> Spotlight and Raycast now search $DEST"
echo "    Raycast: if it lags behind, run \"Refresh Applications\" or toggle"
echo "    Search Applications off and on once."
