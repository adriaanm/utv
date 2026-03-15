#!/usr/bin/env bash
# Install utv.app to /Applications, stripping Gatekeeper quarantine.
# Run from the directory containing utv.app (e.g. after extracting utv.tar.gz).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/utv.app"

if [ ! -d "$APP" ]; then
    echo "Error: utv.app not found next to this script." >&2
    exit 1
fi

echo "Installing utv.app to /Applications..."
rm -rf /Applications/utv.app
cp -R "$APP" /Applications/utv.app
xattr -cr /Applications/utv.app
echo "Done. You can open utv from /Applications."
open /Applications/utv.app
