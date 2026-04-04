# utv — YouTube viewer with ad blocking (macOS)

# Update submodules to latest upstream + copy scriptlet bundle
sync:
    ./scripts/sync-ubo.sh --update

# Build the app (debug)
build: _ensure-resources
    #!/usr/bin/env bash
    set -euo pipefail
    # SwiftData macros require the Xcode toolchain (not just Command Line Tools)
    DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$DEV_DIR" != */Xcode.app/* ]]; then
        echo "error: SwiftData macros require the Xcode toolchain. Install Xcode and run:" >&2
        echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
        exit 1
    fi
    swift build

# Build and assemble + launch .app bundle
run: build
    ./scripts/bundle-app.sh
    open .build/utv.app

# Ensure submodules are initialised and scriptlets are in place (no network if already done)
_ensure-resources:
    ./scripts/sync-ubo.sh

# Build release and install to /Applications
install: _ensure-resources
    #!/usr/bin/env bash
    set -euo pipefail
    swift build -c release
    ./scripts/bundle-app.sh release
    rm -rf /Applications/utv.app
    cp -R .build/utv.app /Applications/utv.app
    xattr -cr /Applications/utv.app
    echo "Installed to /Applications/utv.app"

# Clean build artifacts
clean:
    swift package clean

# Show YouTube-relevant filter changes since last submodule update
diff-filters:
    #!/usr/bin/env bash
    set -euo pipefail
    cd third_party/uAssets
    YT='youtube\.com|youtube-nocookie\.com|youtubei\.googleapis\.com|googlevideo\.com|ytimg\.com'
    echo "==> YouTube-relevant changes in uAssets filters:"
    git diff HEAD@{1}..HEAD -- filters/ | grep -E "^[+-].*($YT)" | head -80 || echo "  (no YouTube-related changes)"
    echo ""
    echo "==> Changed filter files:"
    git diff HEAD@{1}..HEAD --stat -- filters/ || echo "  (no changes)"

# Show current scriptlet bundle version and size
adblock-status:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Scriptlet bundle:"
    ls -lh utv/utv/Resources/ubo-scriptlets.js 2>/dev/null || echo "  NOT FOUND — run 'just sync'"
    echo ""
    echo "==> Content rules:"
    jq length utv/utv/Resources/content-rules.json 2>/dev/null && echo "  rules in content-rules.json" || echo "  NOT FOUND"
    echo ""
    echo "==> Submodule versions:"
    git submodule status --cached | sed 's/^/  /'
