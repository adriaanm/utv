# utv — macOS YouTube viewer with ad blocking

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

# Clean build artifacts
clean:
    xcodebuild -project utv/utv.xcodeproj -scheme utv clean
