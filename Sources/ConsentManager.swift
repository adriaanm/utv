import Foundation
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
    /// Automatically starts/stops cookie observation.
    var consentRequest: ConsentRequest? {
        didSet {
            if consentRequest != nil {
                dismissWarning = nil
                startObservingCookies()
            } else {
                stopObservingCookies()
            }
        }
    }

    /// Warning shown when the user tries to dismiss without the cookie being set.
    var dismissWarning: String?

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

    private var cookieObserver: SOCSCookieObserver?

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

    /// Try to dismiss the consent sheet. If the SOCS cookie hasn't been set yet,
    /// show a warning instead.
    func finishConsent() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        if let socs = cookies.first(where: { $0.name == "SOCS" && $0.domain.contains("youtube") }) {
            socsCookieValue = socs.value
            consentRequest = nil
        } else {
            dismissWarning = "Cookie consent not yet accepted. YouTube blocks video feeds without it — browse around and accept the cookie banner before closing."
        }
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

    // MARK: - Cookie observation

    private func startObservingCookies() {
        let observer = SOCSCookieObserver { [weak self] value in
            Task { @MainActor in
                guard let self, self.consentRequest != nil else { return }
                self.socsCookieValue = value
                self.stopObservingCookies()
                self.consentRequest = nil
            }
        }
        cookieObserver = observer
        WKWebsiteDataStore.default().httpCookieStore.add(observer)
    }

    private func stopObservingCookies() {
        if let observer = cookieObserver {
            WKWebsiteDataStore.default().httpCookieStore.remove(observer)
            cookieObserver = nil
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

// MARK: - WKHTTPCookieStore observer

/// Watches the WKWebView cookie store for the SOCS cookie being set.
private class SOCSCookieObserver: NSObject, WKHTTPCookieStoreObserver {
    private let onFound: (String) -> Void

    init(onFound: @escaping (String) -> Void) {
        self.onFound = onFound
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task {
            let cookies = await cookieStore.allCookies()
            if let socs = cookies.first(where: { $0.name == "SOCS" && $0.domain.contains("youtube") }) {
                onFound(socs.value)
            }
        }
    }
}

// MARK: - Consent Web View

struct ConsentWebView: NSViewRepresentable {
    var searchQuery: String?
    func makeNSView(context: Context) -> WKWebView { makeConsentWebView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

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
