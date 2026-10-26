#!/usr/bin/env bash
#
# Build, install, and launch the iOS app on a physical iPhone or iPad, then
# pair it with the running hub over the LAN.
#
#   Scripts/run-mobile-device.sh
#   Scripts/run-mobile-device.sh --device "iPhone von Oli"
#   DEVICE="iPhone von Oli" Scripts/run-mobile-device.sh
#   DEVELOPMENT_TEAM=ABCDE12345 Scripts/run-mobile-device.sh
#   Scripts/run-mobile-device.sh --variant review-a --name "OCB A"
#
# --variant installs the build as an extra app instead of replacing the normal
# one: the bundle ids get the variant suffix and the display name changes, so
# several worktrees can be reviewed on the same phone. See
# Scripts/run-mobile-variants.sh for the wrapper that does this per worktree.
#
# The device must be unlocked, trusted, and have Developer Mode enabled. Signing
# uses the first "Apple Development" identity unless DEVELOPMENT_TEAM is set.
# Pairing uses an address the phone can reach because 127.0.0.1 on the phone
# means the phone itself. A running `make hub-tunnel` URL is preferred; Tailscale
# and the Mac's Wi-Fi/Ethernet address also work. USB Personal Hotspot does not:
# iOS apps cannot route back to the tethered Mac at its 192.0.0.x address.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_BUNDLE_ID="dev.opencodebar.mobile"
HUB_CONFIG="${HUB_CONFIG:-$HOME/.config/opencode/opencodebar-hub.json}"

usage() {
    cat <<'TEXT'
Build, install, and launch OpenCodeBar on a connected iPhone or iPad.

Usage:
  Scripts/run-mobile-device.sh                  build and run on the only device
  Scripts/run-mobile-device.sh -d "My iPhone"   pick a device by name
  Scripts/run-mobile-device.sh --no-build       install the last build
  Scripts/run-mobile-device.sh --console        stream the app's log output
  Scripts/run-mobile-device.sh --variant review-a --name "OCB A"
                                                install as an extra app variant
  Scripts/run-mobile-device.sh --worktree ../other-branch
                                                build from another worktree
  Scripts/run-mobile-device.sh --help

Options:
  -v, --variant SLUG   Append `.SLUG` to the bundle ids so this build can be
                       installed next to the normal app and other variants.
                       Use lowercase letters, digits, and hyphens.
      --name NAME      Home-screen name for the variant (default "OpenCodeBar
                       SLUG"). Ignored without --variant.
  -w, --worktree PATH  Build from the git worktree at PATH instead of this
                       checkout. The project is regenerated there.

Environment:
  DEVICE             Device name, UDID, serial number, or identifier
  DEVELOPMENT_TEAM   10-character Apple Team ID (otherwise auto-detected)
  OPENCODEBAR_HUB_URL / OPENCODEBAR_HUB_TOKEN
                     Override the hub connection from opencodebar-hub.json
  HUB_LAN_IP         Address the phone should use (otherwise auto-detected).
                     Tailscale and Wi-Fi/Ethernet work; a running
                     `make hub-tunnel` URL is preferred automatically.
  OPENCODEBAR_TUNNEL_CONFIG
                     Tunnel record written by make hub-tunnel

First run: connect the device, unlock it, tap Trust, and enable
Settings → Privacy & Security → Developer Mode.
TEXT
}

device="${DEVICE:-}"
build=1
console=0
variant=""
variant_name=""
worktree=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--variant)
            if [ $# -lt 2 ]; then
                echo "run-mobile-device: $1 needs a value" >&2
                exit 2
            fi
            variant="$2"
            shift 2
            ;;
        --variant=*)
            variant="${1#*=}"
            shift
            ;;
        --name)
            if [ $# -lt 2 ]; then
                echo "run-mobile-device: $1 needs a value" >&2
                exit 2
            fi
            variant_name="$2"
            shift 2
            ;;
        --name=*)
            variant_name="${1#*=}"
            shift
            ;;
        -w|--worktree)
            if [ $# -lt 2 ]; then
                echo "run-mobile-device: $1 needs a value" >&2
                exit 2
            fi
            worktree="$2"
            shift 2
            ;;
        --worktree=*)
            worktree="${1#*=}"
            shift
            ;;
        -d|--device)
            if [ $# -lt 2 ]; then
                echo "run-mobile-device: $1 needs a value" >&2
                exit 2
            fi
            device="$2"
            shift 2
            ;;
        --device=*)
            device="${1#*=}"
            shift
            ;;
        -n|--no-build)
            build=0
            shift
            ;;
        --console)
            console=1
            shift
            ;;
        *)
            echo "run-mobile-device: unknown option '$1'" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -n "$worktree" ]; then
    if [ ! -d "$worktree" ]; then
        echo "run-mobile-device: worktree '$worktree' does not exist." >&2
        exit 2
    fi
    ROOT="$(cd "$worktree" && pwd)"
fi
if [ ! -f "$ROOT/project.yml" ]; then
    echo "run-mobile-device: no project.yml in $ROOT." >&2
    exit 2
fi
if [ -n "$variant" ] && ! grep -q 'VARIANT_SUFFIX' "$ROOT/project.yml"; then
    echo "run-mobile-device: $ROOT/project.yml has no VARIANT_SUFFIX placeholder," >&2
    echo "so it cannot build a side-by-side variant. Use Scripts/run-mobile-variants.sh" >&2
    echo "or cherry-pick the variant support from main." >&2
    exit 2
fi

# Variants get their own bundle ids, home-screen name, and DerivedData folder so
# the normal app and other worktrees stay installed. iOS resolves an installed
# app by bundle id, so this is the only way to run builds side by side.
variant_suffix=""
derived_suffix=""
if [ -n "$variant" ]; then
    if ! [[ "$variant" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]]; then
        echo "run-mobile-device: variant '$variant' must be lowercase letters, digits," >&2
        echo "and hyphens, and start with a letter or digit (max 40 characters)." >&2
        exit 2
    fi
    variant_suffix=".$variant"
    derived_suffix="-$variant"
    if [ -z "$variant_name" ]; then
        variant_name="OpenCodeBar $variant"
    fi
elif [ -n "$variant_name" ]; then
    echo "run-mobile-device: --name needs --variant (otherwise it would rename the normal app)." >&2
    exit 2
fi
if [ -z "$variant_name" ]; then
    variant_name="OpenCodeBar"
fi

BUNDLE_ID="$BASE_BUNDLE_ID$variant_suffix"
DERIVED="$ROOT/.build/ios-device$derived_suffix"
APP="$DERIVED/Build/Products/Debug-iphoneos/OpenCodeBar.app"

if ! command -v xcrun >/dev/null 2>&1; then
    echo "run-mobile-device: xcrun not found; install Xcode first." >&2
    exit 1
fi

# Pick a physical device. Prefer a connected one; if none is connected, accept a
# single paired device so Wi-Fi devices can still be reached by devicectl.
device_line=""
if ! device_line="$(
    xcrun devicectl list devices --json-output - 2>/dev/null | python3 -c '
import json
import sys

wanted = sys.argv[1].strip().lower()
data = json.load(sys.stdin)

devices = []
for entry in data.get("result", {}).get("devices", []):
    hardware = (entry.get("properties") or {}).get("hardware") or entry.get("hardwareProperties") or {}
    connection = (entry.get("properties") or {}).get("connection") or entry.get("connectionProperties") or {}
    details = entry.get("deviceProperties") or {}

    if hardware.get("platform") != "iOS":
        continue
    if hardware.get("reality") != "physical":
        continue

    devices.append({
        "id": entry.get("identifier", ""),
        "name": details.get("name") or entry.get("name") or hardware.get("marketingName") or "iPhone",
        "model": hardware.get("marketingName", ""),
        "state": connection.get("state", "unknown"),
        "udid": hardware.get("udid", ""),
        "serial": hardware.get("serialNumber", ""),
        "ecid": str(hardware.get("ecid", "")),
    })

def label(item):
    if item["model"] and item["model"] != item["name"]:
        return "%s (%s)" % (item["name"], item["model"])
    return item["name"]

def matches(item):
    if not wanted:
        return False
    values = [item["id"], item["udid"], item["serial"], item["ecid"], item["name"], item["model"]]
    return any(wanted == value.lower() for value in values if value) or wanted in item["name"].lower()

if wanted:
    found = [item for item in devices if matches(item)]
    if not found:
        print("No physical iOS device matches %r. Known devices:" % sys.argv[1], file=sys.stderr)
        for item in devices:
            print("  %s — %s (%s)" % (label(item), item["state"], item["udid"] or item["id"]), file=sys.stderr)
        sys.exit(2)
    if len(found) > 1:
        print("%r matches more than one device; use a UDID:" % sys.argv[1], file=sys.stderr)
        for item in found:
            print("  %s — %s" % (label(item), item["udid"] or item["id"]), file=sys.stderr)
        sys.exit(3)
    chosen = found[0]
else:
    connected = [item for item in devices if item["state"] == "connected"]
    if len(connected) == 1:
        chosen = connected[0]
    elif len(connected) > 1:
        print("More than one device is connected; pass --device:", file=sys.stderr)
        for item in connected:
            print("  %s — %s" % (label(item), item["udid"] or item["id"]), file=sys.stderr)
        sys.exit(4)
    elif len(devices) == 1:
        print("Note: %s is not currently connected; trying anyway." % label(devices[0]), file=sys.stderr)
        chosen = devices[0]
    else:
        print("No physical iOS device found. Connect and unlock an iPhone or iPad,", file=sys.stderr)
        print("tap Trust, and enable Developer Mode, then run this again.", file=sys.stderr)
        sys.exit(5)

print("\t".join([chosen["id"], label(chosen), chosen["state"], chosen["udid"]]))
' "$device"
)"; then
    echo "run-mobile-device: could not select a device." >&2
    exit 1
fi

IFS=$'\t' read -r DEVICE_ID DEVICE_NAME DEVICE_STATE DEVICE_UDID <<<"$device_line"
if [ -z "$DEVICE_ID" ]; then
    echo "run-mobile-device: could not determine the device identifier." >&2
    exit 1
fi
if [ -n "$DEVICE_UDID" ]; then
    echo "Using device $DEVICE_NAME ($DEVICE_UDID)"
else
    echo "Using device $DEVICE_NAME ($DEVICE_ID)"
fi
if [ "$DEVICE_STATE" != "connected" ]; then
    echo "Warning: the device reports '$DEVICE_STATE'. It may still be reachable over Wi-Fi;"
    echo "keep it unlocked and on the same network, or plug it in."
fi

cert_team="$(
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -nE 's/.*Apple Development: .*\(([A-Z0-9]{10})\)".*/\1/p' \
        | head -1
)"

# The team on the certificate can be stale (for example after switching Apple
# IDs). Prefer a team Xcode actually has an account for, using the identity's
# team when it is still listed.
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
if [ -z "$team" ]; then
    team="$cert_team"
fi
if [ -z "$team" ]; then
    cat >&2 <<'TEXT'
run-mobile-device: no Apple Development signing identity found.
Sign in to Xcode (Settings → Accounts) or set DEVELOPMENT_TEAM to your Team ID.
TEXT
    exit 1
fi

if [ "$build" -eq 1 ]; then
    # A specific destination lets Xcode register the device and include it in
    # the provisioning profile. Offline devices cannot be prepared that way, so
    # fall back to a generic build and let devicectl report connectivity.
    destination="generic/platform=iOS"
    if [ "$DEVICE_STATE" = "connected" ] && [ -n "$DEVICE_UDID" ]; then
        destination="platform=iOS,id=$DEVICE_UDID"
    fi

    echo "==> Building $BUNDLE_ID for device (team $team)"
    if ! (
        cd "$ROOT"
        xcodegen generate
        # Command-line settings apply to every target, so the variant ids live
        # in project.yml as $(VARIANT_SUFFIX) placeholders and only the suffix
        # is passed here. The widget target appends `.widgets` to the app id.
        xcodebuild \
            -project OpenCodeBarMobile.xcodeproj \
            -scheme OpenCodeBarMobile \
            -configuration Debug \
            -destination "$destination" \
            -derivedDataPath "$DERIVED" \
            -allowProvisioningUpdates \
            -allowProvisioningDeviceRegistration \
            DEVELOPMENT_TEAM="$team" \
            CODE_SIGN_STYLE=Automatic \
            VARIANT_SUFFIX="$variant_suffix" \
            VARIANT_NAME="$variant_name" \
            build
    ); then
        cat >&2 <<'TEXT'
run-mobile-device: device build failed.
If this was a signing error, open Xcode → Settings → Accounts and sign in with
the Apple ID that owns the development team, then run this script again.
TEXT
        exit 1
    fi
elif [ ! -d "$APP" ]; then
    echo "run-mobile-device: no device build at $APP; run without --no-build first." >&2
    exit 1
fi

hub_url="${OPENCODEBAR_HUB_URL:-${HUB_URL:-}}"
hub_token="${OPENCODEBAR_HUB_TOKEN:-${HUB_TOKEN:-}}"
explicit_hub_url=0
[ -n "$hub_url" ] && explicit_hub_url=1
if [ -f "$HUB_CONFIG" ]; then
    if [ -z "$hub_url" ]; then
        hub_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("url", ""))' "$HUB_CONFIG")"
    fi
    if [ -z "$hub_token" ]; then
        hub_token="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("token", ""))' "$HUB_CONFIG")"
    fi
fi

# Prefer a running `make hub-tunnel` quick tunnel. A direct LAN address works on
# the same Wi-Fi, but not on cellular, and iOS does not route from an app back
# to a Mac tethered through the phone's own hotspot.
tunnel_config="${OPENCODEBAR_TUNNEL_CONFIG:-$HOME/.config/opencode/opencodebar-hub-tunnel.json}"
using_tunnel=0
if [ "$explicit_hub_url" -eq 0 ] && [ -f "$tunnel_config" ]; then
    tunnel_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("url", ""))' "$tunnel_config" 2>/dev/null || true)"
    tunnel_pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("pid", ""))' "$tunnel_config" 2>/dev/null || true)"
    tunnel_alive=1
    if [ -n "$tunnel_pid" ] && ! kill -0 "$tunnel_pid" 2>/dev/null; then
        tunnel_alive=0
    fi
    if [ "$tunnel_alive" -eq 1 ] && [ -n "$tunnel_url" ] \
        && curl -fsS -m 5 "${tunnel_url}/api/ping" >/dev/null 2>&1; then
        hub_url="$tunnel_url"
        using_tunnel=1
    else
        echo "Note: ignoring the stale tunnel in $tunnel_config. Run \`make hub-tunnel\` again for remote access."
    fi
fi

# Pick the address the phone should use to reach this Mac. `ipconfig getifaddr`
# only reports DHCP leases, and USB tethering hands out 192.0.0.2/32, so read
# addresses straight from ifconfig. Preference:
#   1. HUB_LAN_IP (explicit override)
#   2. Tailscale 100.64.0.0/10
#   3. the default-route interface (Wi-Fi/Ethernet)
#   4. any other private IPv4
# Link-local 169.254.x.x is ignored. A 192.0.0.x address on a gateway of
# 192.0.0.1 is the iPhone USB hotspot: the Mac can use the phone's data, but iOS
# apps cannot route back to the Mac. `make hub-tunnel` covers that case.
default_iface="$(netstat -rn -f inet 2>/dev/null | awk '$1 == "default" { print $NF; exit }')"
default_gateway="$(netstat -rn -f inet 2>/dev/null | awk '$1 == "default" { print $2; exit }')"
lan_ip="${HUB_LAN_IP:-}"
if [ -z "$lan_ip" ]; then
    lan_ip="$(
        python3 - "$default_iface" "$default_gateway" <<'PY'
import ipaddress
import subprocess
import sys

default_iface, default_gateway = sys.argv[1], sys.argv[2]

interfaces = []
current = None
for line in subprocess.run(["ifconfig"], capture_output=True, text=True).stdout.splitlines():
    if line and not line[0].isspace() and ":" in line:
        current = line.split(":", 1)[0]
    elif current and line.startswith("\tinet "):
        interfaces.append((current, line.split()[1]))

def score(item):
    iface, ip = item
    try:
        address = ipaddress.ip_address(ip)
    except ValueError:
        return 99
    if address.is_loopback or address.is_link_local or address.is_unspecified:
        return 99
    # USB Personal Hotspot: the Mac receives a 192.0.0.x address and the phone
    # is the gateway. The phone cannot route back to this address, so never
    # auto-pair with it.
    if (
        iface == default_iface
        and default_gateway == "192.0.0.1"
        and address in ipaddress.ip_network("192.0.0.0/24")
    ):
        return 99
    # Tailscale is reachable from any network that also runs Tailscale.
    if address in ipaddress.ip_network("100.64.0.0/10"):
        return 1
    if iface == default_iface:
        return 2
    if address.is_private:
        return 3
    return 4

usable = sorted((item for item in interfaces if score(item) < 99), key=score)
print(usable[0][1] if usable else "")
PY
    )"
fi

pair_url=""
if [ -n "$hub_url" ] && [ -n "$hub_token" ]; then
    if [ -z "$lan_ip" ] && python3 -c '
import sys
import urllib.parse
host = urllib.parse.urlsplit(sys.argv[1]).hostname or ""
sys.exit(0 if host in {"127.0.0.1", "localhost", "0.0.0.0", "::1", ""} else 1)
' "$hub_url"; then
        echo "Warning: no reachable address found; skipping automatic pairing." >&2
        echo "On cellular or USB tethering, run 'make hub-tunnel' first." >&2
        echo "Otherwise set HUB_LAN_IP or OPENCODEBAR_HUB_URL." >&2
    else
        pair_url="$(
            HUB_TOKEN="$hub_token" HUB_LAN_IP="$lan_ip" python3 - "$hub_url" <<'PY'
import os
import sys
import urllib.parse

url = sys.argv[1]
token = os.environ.get("HUB_TOKEN", "")
lan = os.environ.get("HUB_LAN_IP", "")
parts = urllib.parse.urlsplit(url)

# 127.0.0.1 on the phone means the phone itself. Substitute the address the
# phone can reach, but keep an explicit non-loopback URL (Tailscale, tunnel,
# another host) exactly as the user provided it.
if parts.hostname in {"127.0.0.1", "localhost", "0.0.0.0", "::1", None}:
    if not lan:
        sys.exit(0)
    netloc = lan
    if parts.port:
        netloc = f"{netloc}:{parts.port}"
    url = f"{parts.scheme or 'http'}://{netloc}"

print("opencodebar://pair?url=" + urllib.parse.quote(url, safe="") + "&token=" + urllib.parse.quote(token, safe=""))
PY
        )"
    fi
elif [ ! -f "$HUB_CONFIG" ]; then
    echo "No hub config found at $HUB_CONFIG — pair from the app's Settings, or set OPENCODEBAR_HUB_URL/TOKEN."
fi

echo "==> Installing on $DEVICE_NAME"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

launch_args=(--device "$DEVICE_ID" --terminate-existing)
if [ "$console" -eq 1 ]; then
    launch_args+=(--console)
fi
if [ -n "$pair_url" ]; then
    launch_args+=(--payload-url "$pair_url")
    pair_target="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.parse_qs(urllib.parse.urlsplit(sys.argv[1]).query)["url"][0])' "$pair_url")"
    if [ "$using_tunnel" -eq 1 ]; then
        echo "Pairing over the Cloudflare tunnel at $pair_target"
    else
        echo "Pairing with the hub at $pair_target"
        echo "If the phone is on cellular, run 'make hub-tunnel' first and rerun this script."
    fi
fi

echo "==> Launching $BUNDLE_ID"
xcrun devicectl device process launch "${launch_args[@]}" "$BUNDLE_ID"
