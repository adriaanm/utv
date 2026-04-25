import SwiftUI
import utvCore
import UtvWebKitTV

@main
struct utvTVApp: App {
    init() {
        // Load WebKit.framework at launch — tvOS SDK has no link-time stub
        // for WKWebView, so the executable was linked with `-undefined dynamic_lookup`
        // and we resolve the symbols at runtime here.
        guard UtvWebKitBootstrap() else {
            fatalError("WebKit framework not available on this Apple TV. " +
                       "If this is a fresh tvOS release, see docs/tvos-port.md.")
        }
    }

    var body: some Scene { AppRoot() }
}
