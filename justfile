# utv — YouTube viewer with ad blocking (macOS)

# Update submodules to latest upstream + copy scriptlet bundle
sync:
    ./scripts/sync-ubo.sh --update

# Vendor WebKit headers from the iOS SDK for the tvOS bridge.
# tvOS SDK ships no public WebKit headers; iOS SDK has the same WebKit binary surface.
# Re-run after every Xcode update. See docs/tvos-port.md.
sync-webkit-headers:
    #!/usr/bin/env bash
    set -euo pipefail
    sdk=$(xcrun --sdk iphoneos --show-sdk-path)
    src="$sdk/System/Library/Frameworks/WebKit.framework/Headers"
    dst="Sources/VendoredWebKit/include/WebKit"
    if [ ! -d "$src" ]; then
        echo "iOS SDK WebKit headers not found at $src" >&2
        echo "Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
        exit 1
    fi
    rm -rf "$dst" && mkdir -p "$dst"
    cp "$src/"*.h "$dst/"
    count=$(ls -1 "$dst" | wc -l | tr -d ' ')
    echo "Vendored $count WebKit headers from $sdk"
    echo "  destination: $dst"

# Build the app (debug)
build: _ensure-resources
    swift build

# Build and assemble + launch .app bundle
run: build
    ./scripts/bundle-app.sh
    open .build/utv.app

# Ensure submodules are initialised and scriptlets are in place (no network if already done)
_ensure-resources:
    ./scripts/sync-ubo.sh

# Build release .app bundle into .build/utv.app
build-release: _ensure-resources
    #!/usr/bin/env bash
    set -euo pipefail
    swift build -c release
    ./scripts/bundle-app.sh release

# Build release and install to /Applications
install: build-release
    #!/usr/bin/env bash
    set -euo pipefail
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
    ls -lh Sources/Resources/ubo-scriptlets.js 2>/dev/null || echo "  NOT FOUND — run 'just sync'"
    echo ""
    echo "==> Content rules:"
    jq length Sources/Resources/content-rules.json 2>/dev/null && echo "  rules in content-rules.json" || echo "  NOT FOUND"
    echo ""
    echo "==> Submodule versions:"
    git submodule status --cached | sed 's/^/  /'
