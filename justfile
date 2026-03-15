# utv — YouTube viewer with ad blocking (macOS + tvOS)

# Update submodules and copy scriptlet bundle into app Resources
sync:
    ./scripts/sync-ubo.sh

# Generate Xcode project from project.yml
generate:
    cd utv && xcodegen generate

# Build the app (debug)
build:
    xcodebuild -project utv/utv.xcodeproj -scheme utv -configuration Debug build

# Build and run
run: build
    open "$(xcodebuild -project utv/utv.xcodeproj -scheme utv -configuration Debug -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/utv.app"

# Build tvOS app (debug, simulator)
build-tv:
    xcodebuild -project utv/utv.xcodeproj -scheme utv-tv -configuration Debug -destination 'platform=tvOS Simulator,name=Apple TV' build

# Clean build artifacts
clean:
    xcodebuild -project utv/utv.xcodeproj -scheme utv clean

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
