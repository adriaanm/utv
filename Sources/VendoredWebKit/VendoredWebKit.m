// VendoredWebKit's purpose is to publish a `module WebKit` clang module for tvOS
// Swift code (see include/module.modulemap and include/WebKit/, the latter gitignored
// and populated by `just sync-webkit-headers`). This file is a placeholder so
// SwiftPM treats this as a buildable target.

#if TARGET_OS_TV
__attribute__((used))
static const char *VendoredWebKitTouch = "vendored-webkit-tv";
#endif
