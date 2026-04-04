#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/AdsFilters"

FORCE="${1:-}"
APP_RESOURCES="$REPO_ROOT/Sources/Resources"
SCRIPTLET_TARGET="$APP_RESOURCES/ubo-scriptlets.js"

# Quick path: if not --update and scriptlets already exist, nothing to do
if [ "$FORCE" != "--update" ] && [ -f "$SCRIPTLET_TARGET" ]; then
    exit 0
fi

echo "==> Initialising submodules (shallow)..."
git -C "$REPO_ROOT" submodule update --init --depth 1

if [ "$FORCE" = "--update" ]; then
    echo "==> Fetching latest upstream..."
    git -C "$REPO_ROOT" submodule update --remote --depth 1
fi

echo "==> Preparing output directory: $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/filters" "$OUT_DIR/rulesets" "$OUT_DIR/scriptlets"

# --- 1. Extract YouTube-relevant filter rules from uAssets ---
echo "==> Extracting YouTube-relevant filter rules from uAssets..."
UASSETS="$REPO_ROOT/third_party/uAssets"
YT_DOMAINS='youtube\.com|youtube-nocookie\.com|youtubei\.googleapis\.com|yt3\.ggpht\.com|googlevideo\.com|youtube\.google\.com|ytimg\.com'

for f in "$UASSETS"/filters/*.txt; do
    name="$(basename "$f")"
    # Extract lines mentioning YouTube-related domains (skip pure comments)
    grep -iE "$YT_DOMAINS" "$f" > "$OUT_DIR/filters/yt-$name" 2>/dev/null || true
    # Remove empty files
    [ -s "$OUT_DIR/filters/yt-$name" ] || rm -f "$OUT_DIR/filters/yt-$name"
done

# Also keep full copies of the most important lists
for list in filters.txt privacy.txt unbreak.txt quick-fixes.txt; do
    [ -f "$UASSETS/filters/$list" ] && cp "$UASSETS/filters/$list" "$OUT_DIR/filters/$list"
done

echo "   Extracted $(find "$OUT_DIR/filters" -name 'yt-*' | wc -l | tr -d ' ') YouTube filter files"

# --- 2. Copy pre-compiled rulesets from uBOL-home ---
echo "==> Copying pre-compiled rulesets from uBOL-home..."
UBOL="$REPO_ROOT/third_party/uBOL-home/chromium/rulesets"

# Copy the core declarativeNetRequest rulesets
for ruleset in default.json ublock-filters.json ublock-privacy.json ublock-unbreak.json ublock-quick-fixes.json easylist.json easyprivacy.json; do
    [ -f "$UBOL/main/$ruleset" ] && cp "$UBOL/main/$ruleset" "$OUT_DIR/rulesets/$ruleset"
done

# Copy ruleset metadata
for meta in ruleset-details.json scriptlet-details.json; do
    [ -f "$UBOL/$meta" ] && cp "$UBOL/$meta" "$OUT_DIR/rulesets/$meta"
done

# Copy scriptlet injections from uBOL-home (pre-compiled)
if [ -d "$UBOL/scripting/scriptlet/main" ]; then
    mkdir -p "$OUT_DIR/rulesets/scriptlet"
    cp "$UBOL/scripting/scriptlet/main"/*.js "$OUT_DIR/rulesets/scriptlet/" 2>/dev/null || true
fi

echo "   Copied $(find "$OUT_DIR/rulesets" -type f | wc -l | tr -d ' ') ruleset files"

# --- 3. Extract key scriptlets from uBlock source ---
echo "==> Extracting scriptlets from uBlock source..."
UBLOCK="$REPO_ROOT/third_party/uBlock"
SCRIPTLETS_SRC="$UBLOCK/src/js/resources"

# Copy the key scriptlet files needed for YouTube ad blocking
KEY_SCRIPTLETS=(
    json-prune.js
    prevent-fetch.js
    prevent-xhr.js
    prevent-settimeout.js
    prevent-addeventlistener.js
    set-constant.js
    noeval.js
    scriptlets.js
    safe-self.js
    shared.js
    utils.js
)

for s in "${KEY_SCRIPTLETS[@]}"; do
    [ -f "$SCRIPTLETS_SRC/$s" ] && cp "$SCRIPTLETS_SRC/$s" "$OUT_DIR/scriptlets/$s"
done

echo "   Copied $(find "$OUT_DIR/scriptlets" -type f | wc -l | tr -d ' ') scriptlet files"

# --- 4. Copy scriptlet bundle into app Resources ---
echo "==> Copying uBO scriptlet bundle into utv app Resources..."
APP_RESOURCES="$REPO_ROOT/Sources/Resources"
mkdir -p "$APP_RESOURCES"
SCRIPTLET_BUNDLE="$UBOL/scripting/scriptlet/main/ublock-filters.js"
if [ -f "$SCRIPTLET_BUNDLE" ]; then
    cp "$SCRIPTLET_BUNDLE" "$APP_RESOURCES/ubo-scriptlets.js"
    echo "   Copied ubo-scriptlets.js ($(wc -c < "$SCRIPTLET_BUNDLE" | tr -d ' ') bytes)"
else
    echo "   WARNING: ublock-filters.js not found at $SCRIPTLET_BUNDLE"
fi

# --- Summary ---
echo ""
echo "==> Sync complete. Output in $OUT_DIR/"
echo "    filters/     — YouTube-specific + full core filter lists"
echo "    rulesets/     — Pre-compiled declarativeNetRequest rulesets"
echo "    scriptlets/   — Key uBlock scriptlet source files"
echo ""
echo "Submodule versions:"
git -C "$REPO_ROOT" submodule status --cached | sed 's/^/    /'
