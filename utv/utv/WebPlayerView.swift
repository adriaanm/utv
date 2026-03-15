import SwiftUI
import WebKit

struct WebPlayerView: NSViewRepresentable {
    let videoID: String?
    var maximized: Bool = false

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
        context.coordinator.maximized = maximized
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.maximized = maximized

        guard let videoID = videoID,
              videoID != context.coordinator.currentVideoID else { return }
        context.coordinator.load(videoID: videoID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var currentVideoID: String?
        var maximized = false

        func load(videoID: String) {
            currentVideoID = videoID
            guard let webView = webView else { return }
            let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
            webView.load(URLRequest(url: url))
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if maximized {
                injectMaximizeCSS(webView)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow the initial load and same-page navigations
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Block navigation away from the current watch page (YouTube SPA clicks)
            if maximized,
               navigationAction.navigationType == .linkActivated,
               url.host?.contains("youtube.com") == true,
               !url.absoluteString.contains("watch?v=\(currentVideoID ?? "")") {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // MARK: - CSS Injection

        private func injectMaximizeCSS(_ webView: WKWebView) {
            let css = """
            #masthead-container, #masthead,
            #below, #secondary, #related,
            #guide, #guide-button,
            ytd-mini-guide-renderer,
            #comments, #meta,
            tp-yt-app-drawer,
            ytd-popup-container,
            .ytp-chrome-top,
            .ytp-pause-overlay,
            #chat { display: none !important; }

            ytd-app { overflow: hidden !important; }
            ytd-watch-flexy { padding: 0 !important; margin: 0 !important; max-width: 100% !important; }
            #columns { max-width: 100% !important; padding: 0 !important; }
            #primary { max-width: 100% !important; padding: 0 !important; margin: 0 !important; }
            #player-container-outer { max-width: 100% !important; }
            #player-container-inner { max-width: 100% !important; padding: 0 !important; }
            #movie_player {
                position: fixed !important;
                top: 0 !important; left: 0 !important;
                width: 100vw !important; height: 100vh !important;
                z-index: 9999 !important;
            }
            .html5-video-container { width: 100% !important; height: 100% !important; }
            video.html5-main-video { width: 100% !important; height: 100% !important; object-fit: contain !important; }
            """

            let js = """
            (function() {
                let style = document.getElementById('utv-maximize');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'utv-maximize';
                    document.head.appendChild(style);
                }
                style.textContent = `\(css.replacingOccurrences(of: "\n", with: " "))`;

                // Force theater mode and hide controls after a delay
                const player = document.getElementById('movie_player');
                if (player && player.setInternalSize) {
                    player.setInternalSize();
                }
            })();
            """

            webView.evaluateJavaScript(js)

            // Re-inject after YouTube's SPA hydration
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak webView] in
                webView?.evaluateJavaScript(js)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak webView] in
                webView?.evaluateJavaScript(js)
            }
        }
    }
}
