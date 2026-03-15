import Foundation

#if canImport(WebKit)
import WebKit
import SwiftUI

/// Manages the YouTube GDPR consent cookie (SOCS) dynamically.
///
/// On first launch, spins up a hidden WKWebView, loads youtube.com, and auto-clicks
/// the consent button. Falls back to showing the consent page to the user if auto-click
/// fails. The obtained SOCS cookie is persisted in UserDefaults for subsequent launches.
@Observable
@MainActor
final class ConsentManager {
    static let shared = ConsentManager()

    private static let defaultsKey = "consent.socs"
    private static let cookieDomain = ".youtube.com"

    var showConsentSheet = false

    var socsCookieValue: String? {
        get { UserDefaults.standard.string(forKey: Self.defaultsKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
        }
    }

    var needsConsent: Bool { socsCookieValue == nil }

    private init() {}

    // MARK: - Public API

    /// Ensure we have a consent cookie. If one exists, re-inject it into the shared
    /// WKWebView cookie store. Otherwise, obtain one via a hidden web view flow.
    func ensureConsent() async {
        if let value = socsCookieValue {
            await injectCookie(value: value)
            return
        }
        await obtainConsent()
    }

    /// Run the consent flow: hidden WKWebView → auto-click → extract cookie.
    /// If auto-click fails, sets `showConsentSheet` so the user can consent manually.
    func obtainConsent() async {
        let helper = ConsentHelper()

        // Try auto-click in a hidden web view
        if let value = await helper.autoObtainConsent() {
            socsCookieValue = value
            await injectCookie(value: value)
            showConsentSheet = false
            return
        }

        // Auto-click failed — show sheet for manual consent
        showConsentSheet = true
    }

    /// Add SOCS cookie header to a URLRequest (for URLSession callers).
    func applyToRequest(_ request: inout URLRequest) {
        guard let value = socsCookieValue else { return }
        let existing = request.value(forHTTPHeaderField: "Cookie") ?? ""
        if existing.isEmpty {
            request.setValue("SOCS=\(value)", forHTTPHeaderField: "Cookie")
        } else {
            request.setValue("\(existing); SOCS=\(value)", forHTTPHeaderField: "Cookie")
        }
    }

    /// Called when the manual consent sheet's web view finishes.
    /// Extracts the SOCS cookie from the cookie store.
    func extractConsentFromStore() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        if let socs = cookies.first(where: { $0.name == "SOCS" && $0.domain.contains("youtube") }) {
            socsCookieValue = socs.value
            showConsentSheet = false
        }
    }

    /// Clear stored consent (e.g. if cookie becomes stale).
    func invalidate() {
        socsCookieValue = nil
    }

    // MARK: - Private

    private func injectCookie(value: String) async {
        guard let cookie = HTTPCookie(properties: [
            .domain: Self.cookieDomain,
            .path: "/",
            .name: "SOCS",
            .value: value,
            .secure: "TRUE",
            .expires: Date.distantFuture,
        ]) else { return }
        await WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
    }
}

// MARK: - Auto-consent helper

/// Runs a hidden WKWebView to auto-click the YouTube consent dialog.
@MainActor
private final class ConsentHelper: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var autoClickAttempts = 0
    private static let maxAttempts = 3

    private static let autoClickJS = """
    (function() {
        const sels = [
            'button[aria-label*="Accept all"]',
            'button[aria-label*="Reject all"]',
            'button[aria-label*="Accept"]',
            'form[action*="consent"] button',
        ];
        for (const s of sels) {
            const b = document.querySelector(s);
            if (b) { b.click(); return true; }
        }
        return false;
    })();
    """

    func autoObtainConsent() async -> String? {
        await withCheckedContinuation { cont in
            self.continuation = cont

            let config = WKWebViewConfiguration()
            // No ad blocker — we need YouTube's consent page to load unmodified
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
            wv.navigationDelegate = self
            self.webView = wv

            let url = URL(string: "https://www.youtube.com")!
            wv.load(URLRequest(url: url))

            // Timeout: if we haven't gotten a cookie in 8 seconds, give up
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.finish(value: nil)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tryAutoClick()
    }

    private func tryAutoClick() {
        guard let webView, autoClickAttempts < Self.maxAttempts else { return }
        autoClickAttempts += 1

        webView.evaluateJavaScript(Self.autoClickJS) { [weak self] result, _ in
            guard let self else { return }
            let clicked = result as? Bool ?? false

            if clicked {
                // Wait for navigation after click, then check cookies
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.checkForCookie()
                }
            } else {
                // Retry after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.tryAutoClick()
                }
            }
        }
    }

    private func checkForCookie() {
        guard let webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let socs = cookies.first(where: { $0.name == "SOCS" && $0.domain.contains("youtube") })
            DispatchQueue.main.async {
                self?.finish(value: socs?.value)
            }
        }
    }

    private func finish(value: String?) {
        guard let cont = continuation else { return }
        continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        cont.resume(returning: value)
    }
}

// MARK: - Consent Web View (for manual fallback sheet)

#if os(macOS)
struct ConsentWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        makeConsentWebView(context: context)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> ConsentWebCoordinator { ConsentWebCoordinator() }
}
#else
struct ConsentWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        makeConsentWebView(context: context)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> ConsentWebCoordinator { ConsentWebCoordinator() }
}
#endif

extension ConsentWebView {
    func makeConsentWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // No ad blocker — plain web view for consent
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        let url = URL(string: "https://www.youtube.com")!
        wv.load(URLRequest(url: url))
        return wv
    }
}

@MainActor
class ConsentWebCoordinator: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // After each navigation, check if we got the consent cookie
        Task {
            await ConsentManager.shared.extractConsentFromStore()
        }
    }
}

#endif
