#if os(tvOS)
import UIKit
import WebKit

// Hosts a WKWebView and translates Siri Remote d-pad presses into JS calls
// against the focus shim (Resources/focus-shim.js). The tvOS focus engine
// only walks UIKit views — it doesn't see DOM elements — so without this
// bridge a WKWebView is uninhabitable by anything but the touch surface,
// and even that doesn't reach most clickable elements on YouTube.
//
// Phase 1: arrow keys → window._utvFocus.move(...), select → activate().
// Menu / playPause / touchpad gestures are left to bubble up to UIKit so
// SwiftUI's parent navigation behaves normally. See
// docs/tvos-dpad-navigation.md for the full plan.
final class UtvFocusHostView: UIView {
    private(set) weak var webView: WKWebView?

    override var canBecomeFocused: Bool { true }
    override var preferredFocusEnvironments: [UIFocusEnvironment] { [self] }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []
        for press in presses {
            switch press.type {
            case .upArrow:    forward(direction: "up")
            case .downArrow:  forward(direction: "down")
            case .leftArrow:  forward(direction: "left")
            case .rightArrow: forward(direction: "right")
            case .select:     activate()
            default:          unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    private func forward(direction: String) {
        webView?.evaluateJavaScript("window._utvFocus && window._utvFocus.move('\(direction)')")
    }

    private func activate() {
        webView?.evaluateJavaScript("window._utvFocus && window._utvFocus.activate()")
    }
}
#endif
