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

# Build iOS app (debug)
build-ios:
    xcodebuild -project utv/utv.xcodeproj -scheme utv-ios -configuration Debug -destination generic/platform=iOS -allowProvisioningUpdates build

# Build tvOS app (debug, simulator)
build-tv:
    xcodebuild -project utv/utv.xcodeproj -scheme utv-tv -configuration Debug -destination 'platform=tvOS Simulator,name=Apple TV' build

# Build release and install to /Applications
install:
    #!/usr/bin/env bash
    set -euo pipefail
    xcodebuild -project utv/utv.xcodeproj -scheme utv -configuration Release build
    BUILT=$(xcodebuild -project utv/utv.xcodeproj -scheme utv -configuration Release -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')
    rm -rf /Applications/utv.app
    cp -R "$BUILT/utv.app" /Applications/utv.app
    xattr -cr /Applications/utv.app
    echo "Installed to /Applications/utv.app"

# Build release .app and package as a .tar.gz for sharing
package:
    #!/usr/bin/env bash
    set -euo pipefail
    xcodebuild -project utv/utv.xcodeproj -scheme utv -configuration Release build
    BUILT=$(xcodebuild -project utv/utv.xcodeproj -scheme utv -configuration Release -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')
    STAGING=$(mktemp -d)
    cp -R "$BUILT/utv.app" "$STAGING/"
    cp scripts/install-utv.sh "$STAGING/"
    cd "$STAGING"
    tar czf utv.tar.gz utv.app install-utv.sh
    mv utv.tar.gz "{{justfile_directory()}}/"
    rm -rf "$STAGING"
    echo "Created utv.tar.gz — transfer to target Mac and run:"
    echo "  tar xzf utv.tar.gz && ./install-utv.sh"

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
