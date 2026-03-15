import Foundation

#if canImport(WebKit)
import WebKit
import SwiftUI

/// Identifies a consent sheet presentation. Using an `Identifiable` item
/// instead of a plain `Bool` ensures SwiftUI always presents a fresh sheet.
struct ConsentRequest: Identifiable {
    let id = UUID()
    let searchQuery: String?
}

/// Manages the YouTube GDPR consent cookie (SOCS) dynamically.
///
/// On first launch (or after clearing cookies), shows a sheet with YouTube's
/// consent page. The user clicks accept/reject, then taps "Done". The SOCS
/// cookie is extracted and persisted in UserDefaults for subsequent launches.
@Observable
@MainActor
final class ConsentManager {
    static let shared = ConsentManager()

    private static let defaultsKey = "consent.socs"
    private static let cookieDomain = ".youtube.com"

    /// Set to a non-nil value to present the consent sheet.
    var consentRequest: ConsentRequest?

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
    /// WKWebView cookie store. Otherwise, show the consent sheet.
    /// Pass a `searchQuery` to navigate to that channel in the consent view
    /// (YouTube only shows the consent banner on actual page navigations).
    func ensureConsent(searchQuery: String? = nil) async {
        if let value = socsCookieValue {
            await injectCookie(value: value)
            return
        }
        consentRequest = ConsentRequest(searchQuery: searchQuery)
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

    /// Extract the SOCS cookie from the WKWebView cookie store, persist it,
    /// and dismiss the sheet. Called when the user taps "Done".
    func finishConsent() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        if let socs = cookies.first(where: { $0.name == "SOCS" && $0.domain.contains("youtube") }) {
            socsCookieValue = socs.value
        }
        consentRequest = nil
    }

    /// Clear stored consent and all WKWebView data (for testing / re-consent).
    func clearAllCookies() async {
        socsCookieValue = nil
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        for record in records {
            await store.removeData(ofTypes: record.dataTypes, for: [record])
        }
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

// MARK: - Consent Web View

#if os(macOS)
struct ConsentWebView: NSViewRepresentable {
    var searchQuery: String?
    func makeNSView(context: Context) -> WKWebView { makeConsentWebView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct ConsentWebView: UIViewRepresentable {
    var searchQuery: String?
    func makeUIView(context: Context) -> WKWebView { makeConsentWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

extension ConsentWebView {
    func makeConsentWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        let url: URL
        let q = (searchQuery ?? "@martijndoolaard")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "@martijndoolaard"
        url = URL(string: "https://www.youtube.com/results?search_query=\(q)")!
        wv.load(URLRequest(url: url))
        return wv
    }
}

#endif
