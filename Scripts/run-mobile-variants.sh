#!/usr/bin/env bash
#
# Build and install one app variant per git worktree so several versions can be
# reviewed side by side on the same iPhone or iPad.
#
#   Scripts/run-mobile-variants.sh                          every worktree
#   Scripts/run-mobile-variants.sh ../other-worktree        one worktree
#   Scripts/run-mobile-variants.sh feature/virtual-machines  a branch with a worktree
#   Scripts/run-mobile-variants.sh "VMs=../worktrees/vms"    custom name
#   Scripts/run-mobile-variants.sh --list                   show the selection
#
# Each variant gets its own bundle ids (dev.opencodebar.mobile.<slug> and
# ...<slug>.widgets), its own home-screen name, and its own DerivedData folder,
# so installing one never replaces another. The build itself is delegated to
# Scripts/run-mobile-device.sh, which also pairs every variant with the hub.
#
# Worktrees older than the $(VARIANT_SUFFIX) placeholder in project.yml get a
# temporary patch for the duration of the build; the file is restored afterwards
# so the worktree stays clean.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
DEVICE_SCRIPT="${OPENCODEBAR_DEVICE_SCRIPT:-$SCRIPT_DIR/run-mobile-device.sh}"

device=""
build=1
dry_run=0
list_only=0
prefix="OCB "
entries=()

usage() {
    cat <<'TEXT'
Build and install one app variant per git worktree on a connected device.

Usage:
  Scripts/run-mobile-variants.sh                          all worktrees
  Scripts/run-mobile-variants.sh PATH|BRANCH ...          selected worktrees
  Scripts/run-mobile-variants.sh "NAME=PATH" ...          custom display name
  Scripts/run-mobile-variants.sh --list                   show the selection
  Scripts/run-mobile-variants.sh --dry-run                print, do not build

Options:
  -d, --device NAME    Pass a device name, UDID, or serial to devicectl
  -n, --no-build       Install the existing variant builds
      --prefix TEXT    Prefix for the home-screen names (default "OCB ")
      --dry-run        Show the variants and bundle ids without building
  -l, --list           List the worktrees and variant names, then exit
  -h, --help

With no arguments every entry from `git worktree list` is used; the checkout
you run this from is included, including uncommitted changes. Pass paths or
branch names to build only some of them. Labels come from the branch (or the
directory name for a detached worktree) and are slugified for the bundle id.

Environment:
  DEVICE, DEVELOPMENT_TEAM, OPENCODEBAR_HUB_URL, OPENCODEBAR_HUB_TOKEN,
  HUB_LAN_IP, OPENCODEBAR_TUNNEL_CONFIG
                    Forwarded to Scripts/run-mobile-device.sh. See that script's
                    --help for details.

Each variant is installed as dev.opencodebar.mobile.<slug>, so the normal app
and every earlier variant stay on the phone. Variants share the app's keychain
access group, so pairing with the hub carries over between them.
TEXT
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--device)
            if [ $# -lt 2 ]; then
                echo "run-mobile-variants: $1 needs a value" >&2
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
        --prefix)
            if [ $# -lt 2 ]; then
                echo "run-mobile-variants: $1 needs a value" >&2
                exit 2
            fi
            prefix="$2"
            shift 2
            ;;
        --prefix=*)
            prefix="${1#*=}"
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        -l|--list)
            list_only=1
            shift
            ;;
        -*)
            echo "run-mobile-variants: unknown option '$1'" >&2
            usage >&2
            exit 2
            ;;
        *)
            entries+=("$1")
            shift
            ;;
    esac
done

if [ -z "$REPO" ]; then
    echo "run-mobile-variants: not inside a git repository." >&2
    exit 1
fi
if [ ! -x "$DEVICE_SCRIPT" ]; then
    echo "run-mobile-variants: $DEVICE_SCRIPT is missing or not executable." >&2
    exit 1
fi
if [ "$dry_run" -eq 0 ] && [ "$list_only" -eq 0 ] && ! command -v xcodegen >/dev/null 2>&1; then
    echo "run-mobile-variants: xcodegen not found; install it with 'brew install xcodegen'." >&2
    exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ocb-variants.XXXXXX")"
patched_project=""
patched_backup=""

restore_project() {
    if [ -n "$patched_project" ] && [ -f "$patched_backup" ]; then
        cp "$patched_backup" "$patched_project"
        patched_project=""
        patched_backup=""
    fi
}

cleanup() {
    restore_project
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP

# Print "label<TAB>path" for every worktree, main worktree first.
worktree_list() {
    /usr/bin/python3 - "$REPO" <<'PY'
import os
import subprocess
import sys

repo = sys.argv[1]
out = subprocess.run(
    ["git", "-C", repo, "worktree", "list", "--porcelain"],
    capture_output=True,
    text=True,
    check=True,
).stdout

entries = []
path = branch = None
for line in out.splitlines() + [""]:
    if line.startswith("worktree "):
        path = line[len("worktree "):]
        branch = None
    elif line.startswith("branch "):
        branch = line[len("branch "):]
    elif line == "detached":
        branch = None
    elif line == "" and path:
        label = branch.rsplit("/", 1)[-1] if branch else os.path.basename(path.rstrip("/"))
        entries.append((label or "worktree", path))
        path = branch = None

for label, entry_path in entries:
    print(label + "\t" + entry_path)
PY
}

# Resolve a positional argument to a worktree path: a directory, or a branch
# that has a worktree. Echoes the absolute path.
resolve_path() {
    local wanted="$1" label path
    if [ -d "$wanted" ]; then
        (cd "$wanted" && pwd)
        return 0
    fi
    while IFS=$'\t' read -r label path; do
        if [ "$label" = "$wanted" ] || [ "$label" = "${wanted##*/}" ]; then
            printf '%s\n' "$path"
            return 0
        fi
    done <<<"$(worktree_list)"
    return 1
}

label_for_path() {
    local path="$1" branch
    branch="$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
        basename "$path"
    else
        printf '%s\n' "${branch##*/}"
    fi
}

slugify() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
        | cut -c1-36 \
        | sed -E 's/-+$//'
}

# project.yml needs the $(VARIANT_SUFFIX) placeholders for the per-target
# bundle-id overrides. Older worktrees predate them; add them temporarily.
patch_variant_project() {
    /usr/bin/python3 - "$1/project.yml" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    text = handle.read()

if "VARIANT_SUFFIX" in text:
    print("supported")
    sys.exit(0)

text, base = re.subn(
    r"(?m)^settings:\n  base:\n",
    'settings:\n  base:\n    VARIANT_SUFFIX: ""\n    VARIANT_NAME: OpenCodeBar\n',
    text,
    count=1,
)
if base != 1:
    sys.exit("project.yml: no top-level settings/base block to extend")

widget_id = "dev.opencodebar.mobile.widgets"
if text.count(widget_id) != 1:
    sys.exit("project.yml: expected one widget PRODUCT_BUNDLE_IDENTIFIER")
text = text.replace(widget_id, "dev.opencodebar.mobile$(VARIANT_SUFFIX).widgets")

text, app = re.subn(
    r"(?m)^(\s*PRODUCT_BUNDLE_IDENTIFIER:\s*)dev\.opencodebar\.mobile\s*$",
    r"\1dev.opencodebar.mobile$(VARIANT_SUFFIX)",
    text,
    count=1,
)
if app != 1:
    sys.exit("project.yml: no app PRODUCT_BUNDLE_IDENTIFIER to make a variant")

text, names = re.subn(
    r"(?m)^(\s*CFBundleDisplayName:\s*)OpenCodeBar\s*$",
    r"\1$(VARIANT_NAME)",
    text,
)
if names < 1:
    sys.exit("project.yml: no CFBundleDisplayName to make a variant")

with open(path, "w", encoding="utf-8") as handle:
    handle.write(text)
print("patched")
PY
}

# Same slug for the same branch across runs, but unique within one invocation.
used_slugs=" "
used_labels=" "

selected=()
if [ "${#entries[@]}" -eq 0 ]; then
    while IFS=$'\t' read -r label path; do
        selected+=("$label=$path")
    done <<<"$(worktree_list)"
else
    selected=("${entries[@]}")
fi

if [ "${#selected[@]}" -eq 0 ]; then
    echo "run-mobile-variants: no worktrees found." >&2
    exit 1
fi

failed=0
for entry in "${selected[@]}"; do
    if [[ "$entry" == *=* && ! -d "$entry" ]]; then
        label="${entry%%=*}"
        path="${entry#*=}"
    else
        label=""
        path="$entry"
    fi

    if ! path="$(resolve_path "$path")"; then
        echo "run-mobile-variants: no worktree for '$entry'." >&2
        failed=1
        continue
    fi
    if [ ! -f "$path/project.yml" ]; then
        echo "run-mobile-variants: $path has no project.yml; skipping." >&2
        failed=1
        continue
    fi
    if [ -z "$label" ]; then
        label="$(label_for_path "$path")"
    fi

    # Disambiguate duplicate branch/directory names without using the full path.
    unique="$label"
    suffix=2
    while [[ "$used_labels" == *" $unique "* ]]; do
        unique="$label $suffix"
        suffix=$((suffix + 1))
    done
    used_labels="$used_labels$unique "
    label="$unique"

    slug="$(slugify "$label")"
    if [ -z "$slug" ]; then
        slug="variant"
    fi
    unique_slug="$slug"
    suffix=2
    while [[ "$used_slugs" == *" $unique_slug "* ]]; do
        unique_slug="$slug-$suffix"
        suffix=$((suffix + 1))
    done
    used_slugs="$used_slugs$unique_slug "
    slug="$unique_slug"

    display="$prefix$label"
    display="${display:0:24}"
    bundle="dev.opencodebar.mobile.$slug"

    echo "==> $display"
    echo "    worktree  $path"
    echo "    bundle    $bundle"
    if [ "$list_only" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
        continue
    fi

    if ! grep -q 'VARIANT_SUFFIX' "$path/project.yml"; then
        patched_project="$path/project.yml"
        patched_backup="$tmp/$slug-project.yml"
        cp "$patched_project" "$patched_backup"
        patch_variant_project "$path" >/dev/null
        echo "    project.yml patched for this build (restored afterwards)"
    fi

    args=(--worktree "$path" --variant "$slug" --name "$display")
    if [ -n "$device" ]; then
        args+=(--device "$device")
    fi
    if [ "$build" -eq 0 ]; then
        args+=(--no-build)
    fi

    set +e
    "$DEVICE_SCRIPT" "${args[@]}"
    status=$?
    set -e
    restore_project
    if [ "$status" -ne 0 ]; then
        echo "run-mobile-variants: '$display' failed (exit $status)." >&2
        failed=1
    fi
done

if [ "$list_only" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
    exit "$failed"
fi

if [ "$failed" -ne 0 ]; then
    echo "run-mobile-variants: finished with errors; see the output above." >&2
    exit 1
fi

echo "==> Installed ${#selected[@]} variant(s) on the device"
