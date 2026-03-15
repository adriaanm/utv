import SwiftUI
import WebKit

struct WebPlayerView: NSViewRepresentable {
    let videoID: String?
    var maximized: Bool = false
    var startAt: Double = 0
    var onPositionUpdate: ((Double, Double) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.isElementFullscreenEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []

        AdBlocker.configure(config)

        // Message handler for position tracking
        config.userContentController.add(context.coordinator, name: "utvPosition")

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
        context.coordinator.onPositionUpdate = onPositionUpdate
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.maximized = maximized
        context.coordinator.onPositionUpdate = onPositionUpdate

        guard let videoID = videoID,
              videoID != context.coordinator.currentVideoID else { return }
        context.coordinator.startAt = startAt
        context.coordinator.load(videoID: videoID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var currentVideoID: String?
        var maximized = false
        var startAt: Double = 0
        var onPositionUpdate: ((Double, Double) -> Void)?

        func load(videoID: String) {
            currentVideoID = videoID
            guard let webView = webView else { return }
            var urlString = "https://www.youtube.com/watch?v=\(videoID)"
            if startAt > 0 {
                urlString += "&t=\(Int(startAt))s"
            }
            let url = URL(string: urlString)!
            webView.load(URLRequest(url: url))
        }

        func pause() {
            webView?.evaluateJavaScript("document.querySelector('video')?.pause()")
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "utvPosition",
                  let body = message.body as? [String: Double],
                  let pos = body["currentTime"],
                  let dur = body["duration"],
                  dur > 0 else { return }
            onPositionUpdate?(pos, dur)
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if maximized {
                injectMaximizeCSS(webView)
                injectPositionTracker(webView)
                if startAt > 0 {
                    seekTo(startAt, in: webView)
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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

        // MARK: - JS Injection

        private func seekTo(_ seconds: Double, in webView: WKWebView) {
            // Seek to target, retrying only if YouTube resets position back to 0.
            // Stop retrying once playback has progressed past the target.
            let js = """
            (function() {
                const target = \(seconds);
                let settled = false;
                let attempts = 0;
                function trySeek() {
                    if (settled || attempts >= 20) return;
                    attempts++;
                    const v = document.querySelector('video');
                    if (!v || v.readyState < 1) {
                        setTimeout(trySeek, 500);
                        return;
                    }
                    if (v.currentTime >= target - 2) {
                        // Position is at or past target — playback is progressing normally
                        settled = true;
                        return;
                    }
                    v.currentTime = target;
                    setTimeout(trySeek, 1000);
                }
                trySeek();
            })();
            """
            webView.evaluateJavaScript(js)
        }

        private func injectPositionTracker(_ webView: WKWebView) {
            let js = """
            (function() {
                if (window._utvTracker) return;
                window._utvTracker = setInterval(function() {
                    const v = document.querySelector('video');
                    if (v && v.duration) {
                        window.webkit.messageHandlers.utvPosition.postMessage({
                            currentTime: v.currentTime,
                            duration: v.duration
                        });
                    }
                }, 3000);
            })();
            """
            webView.evaluateJavaScript(js)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak webView] in
                webView?.evaluateJavaScript(js)
            }
        }

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
