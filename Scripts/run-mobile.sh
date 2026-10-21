#!/bin/bash
# Build, install, and launch the iOS app in a simulator, then pair it with the
# running hub if the hub's config file is present.
#
#   Scripts/run-mobile.sh
#   DEVICE="iPhone 16" Scripts/run-mobile.sh
#
# Assumes `make mobile-build` has produced the app bundle.
set -euo pipefail

DEVICE="${DEVICE:-iPhone 16 Pro}"
BUNDLE_ID="dev.opencodebar.mobile"

APP=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/OpenCodeBarMobile-*/Build/Products/Debug-iphonesimulator/OpenCodeBar.app 2>/dev/null | head -1 || true)
if [ -z "$APP" ]; then
  echo "No built app found. Run 'make mobile-build' first." >&2
  exit 1
fi

UDID=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [ -z "$UDID" ]; then
  echo "No simulator named '$DEVICE'. Set DEVICE=… to another available device." >&2
  exit 1
fi

echo "Using simulator $DEVICE ($UDID)"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
# Open the Simulator UI when available; the app works headless either way.
open -a "$(xcode-select -p)/Applications/Simulator.app" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null

HUB_CONFIG="$HOME/.config/opencode/opencodebar-hub.json"
if [ -f "$HUB_CONFIG" ]; then
  LINK=$(python3 - "$HUB_CONFIG" <<'PY'
import json, sys, urllib.parse
config = json.load(open(sys.argv[1]))
url = config.get("url", "")
token = config.get("token", "")
if url and token:
    print("opencodebar://pair?url=" + urllib.parse.quote(url, safe="") + "&token=" + urllib.parse.quote(token, safe=""))
PY
)
  if [ -n "$LINK" ]; then
    sleep 2
    xcrun simctl openurl "$UDID" "$LINK"
    echo "Paired with the hub from $HUB_CONFIG"
  fi
else
  echo "No hub config found at $HUB_CONFIG — configure the hub in the app's Settings tab."
fi
