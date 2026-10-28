#!/usr/bin/env bash
#
# Builds an over-the-air install for a physical iPhone/iPad and publishes it
# through the hub. The phone opens the printed link (or scans the QR) from any
# network and taps Install; no USB cable or shared Wi-Fi is needed.
#
# The IPA is signed with the development profile, which already lists the
# paired devices' UDIDs. iOS accepts that over HTTPS as long as the developer
# certificate is trusted on the device (it is after the first Xcode install).
#
# Usage:
#   Scripts/deploy-ota.sh              build, publish, show a QR
#   Scripts/deploy-ota.sh --install    also install directly when the phone is reachable
#   Scripts/deploy-ota.sh --no-build   republish the last build
#   Scripts/deploy-ota.sh --json       machine-readable result for the hub
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HUB_CONFIG="${HUB_CONFIG:-$HOME/.config/opencode/opencodebar-hub.json}"
TUNNEL_CONFIG="${OPENCODEBAR_TUNNEL_CONFIG:-$HOME/.config/opencode/opencodebar-hub-tunnel.json}"
KEEP="${OPENCODEBAR_OTA_KEEP:-5}"

usage() {
    cat <<'TEXT'
Publish an over-the-air OpenCodeBar build through the hub.

Usage:
  Scripts/deploy-ota.sh                 archive, export, publish, show a QR
  Scripts/deploy-ota.sh --install       also install now if the phone is reachable
  Scripts/deploy-ota.sh --no-build      republish .build/ota without rebuilding
  Scripts/deploy-ota.sh --json          print one OTA_RESULT line (used by the hub)
  Scripts/deploy-ota.sh --no-qr         do not open the QR image
  Scripts/deploy-ota.sh --out DIR       publish below DIR
  Scripts/deploy-ota.sh --help

--install talks to the phone with devicectl over USB or the local network. It
needs the phone unlocked, trusted, and Developer Mode enabled. When the phone
is not reachable, the published link and QR still work from any network.

Environment:
  DEVICE                      device name or UDID for --install (default: only reachable device)
  DEVELOPMENT_TEAM            Apple team id (otherwise found in Xcode)
  OPENCODEBAR_OTA_INSTALL=1   same as --install
  OPENCODEBAR_OTA_KEEP        builds to keep (default 5)
  OPENCODEBAR_HUB_URL/TOKEN   override the hub from opencodebar-hub.json
  OPENCODEBAR_TUNNEL_CONFIG   tunnel record written by `make hub-tunnel`
TEXT
}

build=1
json=0
qr=1
install=0
[ "${OPENCODEBAR_OTA_INSTALL:-0}" = "1" ] && install=1
device="${DEVICE:-}"
out="${XDG_DATA_HOME:-$HOME/.local/share}/opencodebar/ota"
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --no-build|-n) build=0 ;;
        --install) install=1 ;;
        --json) json=1; qr=0 ;;
        --no-qr) qr=0 ;;
        --device)
            shift
            [ $# -gt 0 ] || { echo "deploy-ota: --device needs a name or UDID" >&2; exit 2; }
            device="$1"
            ;;
        --out)
            shift
            [ $# -gt 0 ] || { echo "deploy-ota: --out needs a directory" >&2; exit 2; }
            out="$1"
            ;;
        *)
            echo "deploy-ota: unknown option '$1'" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

note() {
    # Keep stdout clean when the hub reads the result as JSON.
    if [ "$json" -eq 1 ]; then echo "$@" >&2; else echo "$@"; fi
}

if [ "$build" -eq 1 ]; then
    cert_team="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -nE 's/.*Apple Development: .*\(([A-Z0-9]{10})\)".*/\1/p' \
            | head -1
    )"
    team="${DEVELOPMENT_TEAM:-}"
    if [ -z "$team" ]; then
        team="$(
            defaults export com.apple.dt.Xcode - 2>/dev/null | python3 -c '
import plistlib
import sys

team_on_certificate = sys.argv[1]
try:
    prefs = plistlib.loads(sys.stdin.buffer.read())
except Exception:
    sys.exit(0)

teams = []
for entries in (prefs.get("IDEProvisioningTeams") or {}).values():
    for entry in entries or []:
        if entry.get("teamID") and entry not in teams:
            teams.append(entry)

if not teams:
    sys.exit(0)

ids = [entry["teamID"] for entry in teams]
if team_on_certificate in ids:
    print(team_on_certificate)
    sys.exit(0)

last = prefs.get("IDEProvisioningTeamManagerLastSelectedTeamID")
if last in ids:
    print(last)
    sys.exit(0)

paid = [entry for entry in teams if not entry.get("isFreeProvisioningTeam")]
print((paid or teams)[0]["teamID"])
' "$cert_team" 2>/dev/null || true
        )"
    fi
    [ -n "$team" ] || team="$cert_team"
    if [ -z "$team" ]; then
        echo "deploy-ota: no Apple Development identity; sign in to Xcode or set DEVELOPMENT_TEAM." >&2
        exit 1
    fi

    work="$ROOT/.build/ota"
    rm -rf "$work"
    mkdir -p "$work"
    archive="$work/OpenCodeBar.xcarchive"
    export_dir="$work/export"

    command -v xcodegen >/dev/null 2>&1 && (cd "$ROOT" && xcodegen generate)

    note "==> Archiving for device (team $team)"
    xcodebuild archive \
        -project "$ROOT/OpenCodeBarMobile.xcodeproj" \
        -scheme OpenCodeBarMobile \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath "$archive" \
        -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$team" \
        CODE_SIGN_STYLE=Automatic \
        >"$work/archive.log" 2>&1 || {
            tail -20 "$work/archive.log" >&2
            echo "deploy-ota: archive failed (log: $work/archive.log)" >&2
            exit 1
        }

    cat > "$work/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$team</string>
  <key>destination</key>
  <string>export</string>
  <key>thinning</key>
  <string>&lt;none&gt;</string>
</dict>
</plist>
PLIST

    note "==> Exporting the development IPA"
    xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportPath "$export_dir" \
        -exportOptionsPlist "$work/export.plist" \
        -allowProvisioningUpdates \
        >"$work/export.log" 2>&1 || {
            tail -20 "$work/export.log" >&2
            echo "deploy-ota: export failed (log: $work/export.log)" >&2
            exit 1
        }
    ipa="$export_dir/OpenCodeBar.ipa"
else
    ipa="$ROOT/.build/ota/export/OpenCodeBar.ipa"
fi

if [ ! -f "$ipa" ]; then
    echo "deploy-ota: no IPA at $ipa; run without --no-build first." >&2
    exit 1
fi

# Read the identity straight from the exported app so the install page and
# manifest describe exactly what was signed.
work="$ROOT/.build/ota"
payload="$work/unpacked"
rm -rf "$payload"
mkdir -p "$payload"
unzip -q "$ipa" -d "$payload"
info="$payload/Payload/OpenCodeBar.app/Info.plist"
plist() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$info" 2>/dev/null || true
}
bundle_id="$(plist CFBundleIdentifier)"
version="$(plist CFBundleShortVersionString)"
build_number="$(plist CFBundleVersion)"
title="$(plist CFBundleDisplayName)"
[ -n "$title" ] || title="$(plist CFBundleName)"
[ -n "$title" ] || title="OpenCodeBar"
[ -n "$bundle_id" ] || { echo "deploy-ota: could not read the bundle id" >&2; exit 1; }

id="$(date -u +%Y%m%d-%H%M%S)-$(openssl rand -hex 16)"
dest="$out/$id"
mkdir -p "$dest"
cp "$ipa" "$dest/app.ipa"

commit="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
python3 - "$dest/meta.json" "$id" "$title" "$bundle_id" "$version" "$build_number" "$commit" "$branch" "$ROOT" <<'PY'
import datetime
import json
import os
import sys

path, build_id, title, bundle_id, version, build, commit, branch, worktree = sys.argv[1:10]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "id": build_id,
            "title": title,
            "bundleId": bundle_id,
            "version": version,
            "build": build,
            "commitSha": commit,
            "branch": branch,
            "worktree": worktree,
            "createdAt": int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000),
        },
        handle,
        indent=2,
    )
    handle.write("\n")
PY

# Keep the newest builds; an IPA is several megabytes and quickly adds up.
python3 - "$out" "$KEEP" <<'PY'
import json
import os
import shutil
import sys

root, keep = sys.argv[1], int(sys.argv[2])
builds = []
for name in os.listdir(root):
    meta = os.path.join(root, name, "meta.json")
    if not os.path.isfile(meta):
        continue
    try:
        with open(meta, encoding="utf-8") as handle:
            created = json.load(handle).get("createdAt", 0)
    except Exception:
        created = 0
    builds.append((created, name))
for _, name in sorted(builds, reverse=True)[keep:]:
    shutil.rmtree(os.path.join(root, name), ignore_errors=True)
PY

hub_url="${OPENCODEBAR_HUB_URL:-}"
hub_token="${OPENCODEBAR_HUB_TOKEN:-}"
if [ -f "$HUB_CONFIG" ]; then
    [ -n "$hub_url" ] || hub_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("url", ""))' "$HUB_CONFIG" 2>/dev/null || true)"
    [ -n "$hub_token" ] || hub_token="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("token", ""))' "$HUB_CONFIG" 2>/dev/null || true)"
fi

# Prefer the tunnel: a phone on another network cannot reach the LAN address.
base="$hub_url"
if [ -f "$TUNNEL_CONFIG" ]; then
    tunnel_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("url", ""))' "$TUNNEL_CONFIG" 2>/dev/null || true)"
    tunnel_pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("pid", ""))' "$TUNNEL_CONFIG" 2>/dev/null || true)"
    if [ -n "$tunnel_url" ] && { [ -z "$tunnel_pid" ] || kill -0 "$tunnel_pid" 2>/dev/null; }; then
        base="$tunnel_url"
    fi
fi
base="${base%/}"

page="${base}/api/deployments/ota/${id}"
label="${title} ${version}${build_number:+ ($build_number)}"

installed=0
installed_device=""
if [ "$install" -eq 1 ]; then
    if ! command -v xcrun >/dev/null 2>&1; then
        note "    Install skipped: xcrun not found (install Xcode)"
    else
        device_line="$(
            xcrun devicectl list devices --json-output - 2>/dev/null | python3 -c '
import json
import sys

wanted = sys.argv[1].strip().lower()
try:
    data = json.load(sys.stdin)
except Exception:
    print("none")
    sys.exit(0)

devices = []
for entry in data.get("result", {}).get("devices", []):
    hardware = (entry.get("properties") or {}).get("hardware") or entry.get("hardwareProperties") or {}
    connection = (entry.get("properties") or {}).get("connection") or entry.get("connectionProperties") or {}
    details = entry.get("deviceProperties") or {}
    if hardware.get("platform") != "iOS" or hardware.get("reality") != "physical":
        continue
    devices.append({
        "id": entry.get("identifier", ""),
        "name": details.get("name") or entry.get("name") or hardware.get("marketingName") or "iPhone",
        "model": hardware.get("marketingName", ""),
        "state": connection.get("state", "unknown"),
        "udid": hardware.get("udid", ""),
        "serial": hardware.get("serialNumber", ""),
    })

def matches(item):
    values = [item["id"], item["udid"], item["serial"], item["name"], item["model"]]
    return any(wanted == value.lower() for value in values if value) or wanted in item["name"].lower()

if wanted:
    found = [item for item in devices if matches(item)]
else:
    found = [item for item in devices if item["state"] == "connected"]

if not found:
    print("none")
elif len(found) > 1:
    print("many\t" + "\t".join(item["name"] for item in found))
else:
    item = found[0]
    print("\t".join(["ok", item["id"], item["name"], item["udid"], item["model"], item["state"]]))
' "$device" 2>/dev/null || echo none
        )"
        case "$device_line" in
            ok$'\t'*)
                IFS=$'\t' read -r _ device_id device_name device_udid device_model _state <<<"$device_line"
                install_app="$payload/Payload/OpenCodeBar.app"
                if [ -d "$install_app" ] \
                    && xcrun devicectl device install app --device "$device_id" "$install_app" \
                        >"$work/install.log" 2>&1; then
                    installed=1
                    installed_device="$device_name"
                    note "    Installed on $device_name${device_udid:+ ($device_udid)}"
                else
                    note "    Install skipped: devicectl could not install (log: $work/install.log)"
                fi
                ;;
            many*)
                note "    Install skipped: several phones are reachable; set DEVICE=…"
                ;;
            *)
                note "    Install skipped: no reachable phone (USB or same Wi-Fi)"
                ;;
        esac
    fi
fi

if [ "$installed" -eq 1 ] && [ -n "$hub_token" ]; then
    # Record the direct install so Settings → Deployments shows it as current.
    # Prefer the loopback URL: the tunnel hostname may not resolve on this Mac.
    report_base="$base"
    hub_port="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("port", ""))' "$HUB_CONFIG" 2>/dev/null || true)"
    if [ -n "$hub_port" ]; then report_base="http://127.0.0.1:$hub_port"; fi
    OC_DEVICE_KEY="${device_udid:-$device_id}" \
    OC_DEVICE_NAME="$device_name" \
    OC_DEVICE_MODEL="$device_model" \
    OC_BUNDLE_ID="$bundle_id" \
    OC_APP_NAME="$title" \
    OC_VERSION="$version" \
    OC_BUILD="$build_number" \
    OC_COMMIT="$commit" \
    OC_BRANCH="$branch" \
    OC_WORKTREE="$ROOT" \
    OC_TOKEN="$hub_token" \
    python3 - "$report_base" <<'PY_REPORT' >/dev/null 2>&1 || note "    Note: the install was not recorded in the hub"
import json
import os
import sys
import urllib.request

payload = {
    "deviceKey": os.environ.get("OC_DEVICE_KEY", ""),
    "deviceName": os.environ.get("OC_DEVICE_NAME", ""),
    "deviceModel": os.environ.get("OC_DEVICE_MODEL", ""),
    "bundleId": os.environ.get("OC_BUNDLE_ID", ""),
    "appName": os.environ.get("OC_APP_NAME", ""),
    "version": os.environ.get("OC_VERSION", ""),
    "build": os.environ.get("OC_BUILD", ""),
    "commitSha": os.environ.get("OC_COMMIT", ""),
    "branch": os.environ.get("OC_BRANCH", ""),
    "worktree": os.environ.get("OC_WORKTREE", ""),
    "source": "ota",
}
request = urllib.request.Request(
    sys.argv[1].rstrip("/") + "/api/deployments",
    data=json.dumps(payload).encode(),
    headers={
        "Content-Type": "application/json",
        "Authorization": "Bearer " + os.environ.get("OC_TOKEN", ""),
    },
    method="POST",
)
with urllib.request.urlopen(request, timeout=5) as response:
    if response.status not in (200, 201):
        raise RuntimeError("hub returned %s" % response.status)
PY_REPORT
fi

note "==> Published $label"
note "    Build   $id"
if [ -n "$commit" ]; then note "    Commit  $(printf '%.7s' "$commit") on ${branch:-detached}"; fi
if [ -n "$base" ]; then
    note "    Install $page"
    case "$base" in
        https://*) ;;
        *) note "    Note: iOS needs HTTPS. Start \`make hub-tunnel\` for installs off this network." ;;
    esac
else
    note "    Install (no hub URL found; start the hub or set OPENCODEBAR_HUB_URL)"
fi

if [ "$qr" -eq 1 ] && [ -n "$page" ]; then
    qr_path="$work/ota-qr.png"
    if swift "$ROOT/Scripts/qr.swift" "$page" "$qr_path" >/dev/null 2>&1; then
        note "    QR      $qr_path (opened)"
        open "$qr_path" 2>/dev/null || true
    fi
fi

if [ "$json" -eq 1 ]; then
    python3 - "$id" "$page" "$installed" "$installed_device" "${base:-}" <<'PY'
import json
import sys

build_id, page, installed, device, origin = sys.argv[1:6]
result = {"id": build_id, "page": page, "installed": installed == "1"}
if device:
    result["device"] = device
if origin:
    result["origin"] = origin
print("OTA_RESULT " + json.dumps(result))
PY
fi
