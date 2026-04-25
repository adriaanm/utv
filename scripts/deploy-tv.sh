#!/bin/bash
# Build, sign, and sideload utv to a paired Apple TV.
#
# Auto-detects exactly one paired Apple TV via devicectl and the
# DEVELOPMENT_TEAM from Xcode preferences. Apple Developer Free tier
# resigning is fine — bundles re-deploy weekly.
#
# Usage:
#   scripts/deploy-tv.sh         # build + install on the single paired TV
#
# Override:
#   DEVELOPMENT_TEAM=XXXXXXXXXX scripts/deploy-tv.sh
#   DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer scripts/deploy-tv.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/tvos/utv-tv.xcodeproj"

# DEVELOPER_DIR — fall back to whatever xcode-select points at, then to a
# best-guess Xcode.app location (CLT alone can't build tvOS apps).
if [ -z "${DEVELOPER_DIR:-}" ]; then
    SELECTED=$(xcode-select -p 2>/dev/null || true)
    if [ -d "$SELECTED/Platforms/AppleTVOS.platform" ]; then
        export DEVELOPER_DIR="$SELECTED"
    elif [ -d /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform ]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    elif [ -d /Volumes/MoorsExt/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform ]; then
        export DEVELOPER_DIR=/Volumes/MoorsExt/Xcode.app/Contents/Developer
    else
        echo "Error: cannot locate Xcode.app with the AppleTVOS platform." >&2
        echo "Set DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer" >&2
        exit 1
    fi
fi

# Ensure the xcodeproj exists (regenerate via XcodeGen if missing).
if [ ! -d "$PROJECT" ]; then
    echo "==> Regenerating tvos/utv-tv.xcodeproj via XcodeGen"
    (cd "$REPO_ROOT/tvos" && xcodegen generate)
fi

# Find exactly one paired Apple TV.
DEVICE_JSON=$(mktemp /tmp/utv-devices-XXXXXX.json)
trap 'rm -f $DEVICE_JSON' EXIT
xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null 2>&1

DEVICE_INFO=$(python3 - "$DEVICE_JSON" << 'PYEOF'
import json, re, sys

data = json.load(open(sys.argv[1]))
devices = data.get("result", {}).get("devices", [])

paired_tvs = [
    d for d in devices
    if d.get("hardwareProperties", {}).get("deviceType") == "appleTV"
    and d.get("connectionProperties", {}).get("pairingState") == "paired"
]

if not paired_tvs:
    print("Error: no paired Apple TV found.", file=sys.stderr)
    print("Pair via Xcode > Devices and Simulators (Cmd-Shift-2) first.", file=sys.stderr)
    sys.exit(1)

if len(paired_tvs) > 1:
    names = [d.get("deviceProperties", {}).get("name", "Unknown") for d in paired_tvs]
    print(f"Error: {len(paired_tvs)} Apple TVs paired: {', '.join(names)}", file=sys.stderr)
    print("Turn off all but one before deploying.", file=sys.stderr)
    sys.exit(1)

tv = paired_tvs[0]
name = tv.get("deviceProperties", {}).get("name", "Unknown")
hostnames = tv.get("connectionProperties", {}).get("potentialHostnames", [])

# xcodebuild expects the 8-16-hex UDID embedded in <UDID>.coredevice.local,
# not the standard UUID that `devicectl list devices` prints in its text output.
udid = next(
    (m.group(1) for h in hostnames
     if (m := re.match(r'^([0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})\.coredevice\.local$', h))),
    None,
)
if not udid:
    print("Error: could not extract xcodebuild-style UDID from devicectl output.", file=sys.stderr)
    sys.exit(1)

print(f"{udid}\t{name}")
PYEOF
) || exit 1

XCODE_DEVICE_ID=$(echo "$DEVICE_INFO" | cut -f1)
DEVICE_NAME=$(echo "$DEVICE_INFO" | cut -f2)

# Auto-detect the development team from Xcode preferences.
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    DEVELOPMENT_TEAM=$(defaults read com.apple.dt.Xcode "IDEProvisioningTeamByIdentifier" 2>/dev/null \
        | grep teamID | head -1 | sed 's/.*= //;s/;//;s/ //g' || true)
fi
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    echo "Error: could not auto-detect DEVELOPMENT_TEAM." >&2
    echo "Set it explicitly: DEVELOPMENT_TEAM=XXXXXXXXXX scripts/deploy-tv.sh" >&2
    exit 1
fi

DERIVED="$REPO_ROOT/.build/tvos-dd"
mkdir -p "$DERIVED"

echo "=== Building utv for Apple TV ==="
echo "Device: $DEVICE_NAME ($XCODE_DEVICE_ID)"
echo "Team:   $DEVELOPMENT_TEAM"
echo "Xcode:  $DEVELOPER_DIR"
echo

xcodebuild \
    -project "$PROJECT" \
    -scheme utv-tv \
    -configuration Release \
    -destination "id=$XCODE_DEVICE_ID" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    PRODUCT_BUNDLE_IDENTIFIER=com.utv.tv \
    build

APP_PATH="$DERIVED/Build/Products/Release-appletvos/utv.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: built app not found at $APP_PATH" >&2
    exit 1
fi

echo
echo "=== Installing on $DEVICE_NAME ==="
xcrun devicectl device install app --device "$XCODE_DEVICE_ID" "$APP_PATH"

echo
echo "=== Done ==="
echo "utv installed on $DEVICE_NAME"
