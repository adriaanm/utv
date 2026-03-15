import SwiftUI
import WebKit

struct WebPlayerView: NSViewRepresentable {
    let videoID: String?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.mediaTypesRequiringUserActionForPlayback = []

        AdBlocker.configure(config)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        // Set consent cookie to bypass GDPR dialog
        let consentCookie = HTTPCookie(properties: [
            .domain: ".youtube.com",
            .path: "/",
            .name: "SOCS",
            .value: "CAISNQgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjMwODI5LjA3X3AxGgJlbiACGgYIgJnPpwY",
            .secure: "TRUE",
            .expires: Date.distantFuture,
        ])!
        webView.configuration.websiteDataStore.httpCookieStore.setCookie(consentCookie)

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let videoID = videoID,
              videoID != context.coordinator.currentVideoID else { return }
        context.coordinator.load(videoID: videoID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        weak var webView: WKWebView?
        var currentVideoID: String?

        func load(videoID: String) {
            currentVideoID = videoID
            guard let webView = webView else { return }
            let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
            webView.load(URLRequest(url: url))
        }
    }
}
