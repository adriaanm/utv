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
    # iOS WebKit headers reference UIKit types that are unavailable on tvOS
    # (UIEventButtonMask, UIEditMenuInteractionAnimating). We never use those
    # WebKit APIs from utv, so strip the offending declarations after sync so
    # the WebKit clang module compiles for tvOS.
    sed -i '' '/UIEventButtonMask /d' "$dst/WKNavigationAction.h"
    sed -i '' '/UIEditMenuInteractionAnimating/d' "$dst/WKUIDelegate.h"
    echo "Vendored $count WebKit headers from $sdk"
    echo "  destination: $dst"
    echo "  patched: stripped tvOS-incompatible UIKit references in WKNavigationAction.h, WKUIDelegate.h"

# Build the app (debug)
build: _ensure-resources
    swift build

# Build for tvOS (debug). Personal-sideload only — uses vendored WebKit headers.
build-tv: _ensure-resources
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d Sources/VendoredWebKit/include/WebKit ]; then
        echo "Vendored WebKit headers missing — run 'just sync-webkit-headers' first." >&2
        exit 1
    fi
    sdk=$(xcrun --sdk appletvos --show-sdk-path)
    swift build --triple arm64-apple-tvos17.0 --sdk "$sdk"

# Regenerate tvos/utv-tv.xcodeproj from project.yml (XcodeGen).
gen-tv:
    cd tvos && xcodegen generate

# Build a Release tvOS .app via xcodebuild + XcodeGen project.
bundle-tv: _ensure-resources gen-tv
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d Sources/VendoredWebKit/include/WebKit ]; then
        echo "Vendored WebKit headers missing — run 'just sync-webkit-headers' first." >&2
        exit 1
    fi
    xcodebuild \
        -project tvos/utv-tv.xcodeproj \
        -scheme utv-tv \
        -configuration Release \
        -sdk appletvos \
        -destination 'generic/platform=tvOS' \
        -derivedDataPath .build/tvos-dd \
        CODE_SIGNING_ALLOWED=NO \
        build

# Build, sign, and sideload utv to the single paired Apple TV.
deploy-tv: _ensure-resources gen-tv
    ./scripts/deploy-tv.sh

# Launch utv on the paired Apple TV. Requires $TV_DEVICE_ID (set in .envrc).
launch-tv:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${TV_DEVICE_ID:?TV_DEVICE_ID not set — see .envrc}"
    xcrun devicectl device process launch \
        --device "$TV_DEVICE_ID" \
        com.utv.tv

# Launch utv on the Apple TV with --console (streams stdout/stderr until process exits).
launch-tv-console:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${TV_DEVICE_ID:?TV_DEVICE_ID not set — see .envrc}"
    xcrun devicectl device process launch \
        --device "$TV_DEVICE_ID" \
        --console \
        com.utv.tv

# Terminate any running utv process on the Apple TV (best-effort).
kill-tv:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${TV_DEVICE_ID:?TV_DEVICE_ID not set — see .envrc}"
    pid=$(xcrun devicectl device info processes --device "$TV_DEVICE_ID" \
        | awk '/com\.utv\.tv/ {print $1; exit}')
    if [ -n "${pid:-}" ]; then
        xcrun devicectl device process signal --device "$TV_DEVICE_ID" --signal SIGKILL --pid "$pid"
        echo "Killed utv (pid $pid)"
    else
        echo "utv not running"
    fi

# Tail recent crash/launch logs for utv from the Apple TV.
logs-tv:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${TV_DEVICE_ID:?TV_DEVICE_ID not set — see .envrc}"
    out=$(mktemp -d)
    xcrun devicectl device diagnostics fetchLogs \
        --device "$TV_DEVICE_ID" \
        --output "$out" >/dev/null
    echo "Logs at $out"
    find "$out" -name '*utv*' -o -name '*crash*' 2>/dev/null | head -20

# Full iteration loop: deploy fresh build, then launch with console output.
iterate-tv: deploy-tv launch-tv-console

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
    ls -lh Sources/utvCore/Resources/ubo-scriptlets.js 2>/dev/null || echo "  NOT FOUND — run 'just sync'"
    echo ""
    echo "==> Content rules:"
    jq length Sources/utvCore/Resources/content-rules.json 2>/dev/null && echo "  rules in content-rules.json" || echo "  NOT FOUND"
    echo ""
    echo "==> Submodule versions:"
    git submodule status --cached | sed 's/^/  /'
