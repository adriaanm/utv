import WebKit

private let resourceBundle: Bundle = {
    // In the .app bundle, resources are in Contents/Resources/.
    // For `swift run` (no .app), fall back to SwiftPM's Bundle.module.
    if let url = Bundle.main.url(forResource: "content-rules", withExtension: "json") {
        return Bundle.main
    }
    return Bundle.module
}()

struct AdBlocker {
    /// Configure a WKWebViewConfiguration with content blocking rules and scriptlet injection.
    static func configure(_ config: WKWebViewConfiguration) {
        let userContentController = config.userContentController

        // 1. Compile WebKit content blocker rules
        compileContentRules(for: userContentController)

        // 2. Inject CSS hiding rules
        injectCSSHiding(into: userContentController)

        // 3. Inject uBO scriptlet bundle (the heavy lifter)
        injectScriptlets(into: userContentController)
    }

    // MARK: - Content Blocker Rules

    private static func compileContentRules(for controller: WKUserContentController) {
        guard let url = resourceBundle.url(forResource: "content-rules", withExtension: "json"),
              let jsonString = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("[AdBlocker] content-rules.json not found")
            return
        }

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "utv-rules",
            encodedContentRuleList: jsonString
        ) { ruleList, error in
            if let error = error {
                NSLog("[AdBlocker] Failed to compile content rules: \(error)")
                return
            }
            if let ruleList = ruleList {
                controller.add(ruleList)
                NSLog("[AdBlocker] Content rules compiled and loaded")
            }
        }
    }

    // MARK: - CSS Hiding

    private static func injectCSSHiding(into controller: WKUserContentController) {
        let css = """
        #player-ads,
        ytd-display-ad-renderer,
        ytd-promoted-sparkles-web-renderer,
        ytd-promoted-video-renderer,
        ytd-ad-slot-renderer,
        ytd-in-feed-ad-layout-renderer,
        ytd-banner-promo-renderer,
        .ytp-ad-module,
        .ytp-ad-overlay-container,
        .ytp-ad-text-overlay,
        .ytp-ad-skip-button-container,
        .ytp-ad-player-overlay,
        #masthead-ad,
        #merch-shelf,
        #related ytd-promoted-video-renderer,
        tp-yt-paper-dialog:has(#sponsor-button),
        .ytd-mealbar-promo-renderer {
            display: none !important;
        }
        """

        let js = """
        (function() {
            const style = document.createElement('style');
            style.textContent = \(css.javaScriptStringLiteral());
            (document.head || document.documentElement).appendChild(style);
        })();
        """

        let script = WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        controller.addUserScript(script)
    }

    // MARK: - Scriptlet Injection

    private static func injectScriptlets(into controller: WKUserContentController) {
        guard let url = resourceBundle.url(forResource: "ubo-scriptlets", withExtension: "js"),
              let bundle = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("[AdBlocker] ubo-scriptlets.js not found — run 'just sync' first")
            return
        }

        // The uBO scriptlet bundle is a self-contained IIFE that reads document.location
        // to determine which scriptlets to run. On youtube.com it will automatically
        // activate json-prune, prevent-fetch, prevent-xhr etc. to strip ad payloads.
        // CRITICAL: Must inject into .page world so scriptlets can intercept the page's
        // fetch/XHR/JSON.parse — the default .defaultClient world is isolated.
        let script = WKUserScript(
            source: bundle,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        controller.addUserScript(script)
        NSLog("[AdBlocker] Scriptlet bundle injected (\(bundle.count) bytes)")
    }
}

// MARK: - String Helper

private extension String {
    /// Escape a string for use as a JavaScript string literal (with backtick template).
    func javaScriptStringLiteral() -> String {
        let escaped = self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return "`\(escaped)`"
    }
}
