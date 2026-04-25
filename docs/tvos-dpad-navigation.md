# tvOS d-pad Navigation Inside the WKWebView

Status: **pending.** Pick up after the first hardware sideload confirms (a) Mac → TV consent-cookie sync delivers the SOCS cookie, (b) the YouTube watch page loads, and (c) playback starts on the device. Until those are green, this work has no surface to test against.

## Why

The Siri Remote talks to the tvOS focus engine, which only walks SwiftUI / UIKit views. WKWebView is a single opaque view from the focus engine's perspective — focus stops at its border and never enters the DOM. Concretely on Apple TV today:

- The user can't click YouTube's GDPR consent banner. (Currently sidestepped by syncing the SOCS cookie from the Mac — see [docs/sync-design.md](sync-design.md) — but that's a one-time bypass for *one* unclickable element.)
- The user can't pick a quality, toggle captions, scrub the timeline, click "Watch on YouTube", or interact with anything else inside the page.
- The eventual focus-driven channel/video browser, if built as HTML inside the same WebView (currently the plan), is unusable without this bridge.

So d-pad → DOM is the prerequisite for the WKWebView strategy to be a complete UI, not just a video sink.

## Approach

The standard pattern (as used by [tvosbrowser](https://github.com/jvanakker/tvosbrowser)) is to translate Siri Remote presses into synthetic DOM events:

1. **Capture remote input.** Override `pressesBegan:withEvent:` (or use a `GCController` listener — `GCMicroGamepad` exposes the d-pad and select cleanly) on the `UIView` hosting the `WKWebView`, intercept `UIPress.PressType` values for `.upArrow`, `.downArrow`, `.leftArrow`, `.rightArrow`, `.select`, `.menu`, `.playPause`. Don't forward to `super` for events we handle — that prevents the focus engine from collapsing back to whatever SwiftUI view sits behind the WebView.
2. **Maintain focus state in JS.** A user-script injected at document start keeps a list of focusable elements (`a[href]`, `button`, `[tabindex]:not([tabindex="-1"])`, `input`, `select`, `[role="button"]`, `video`), tracks one as "focused", and draws a focus ring (CSS outline + scrollIntoView). Re-scan on DOM mutations (`MutationObserver`) so SPA navigation doesn't strand the cursor on a stale node.
3. **Bridge presses → JS.** From the `UIPressesEvent` handler, `evaluateJavaScript("window.utvFocus.move('up')")` etc. The JS picks the next focusable in that direction (geometric nearest-neighbor by bounding rect, or DOM-order fallback) and updates focus. `select` dispatches a synthetic `click` plus a `keydown`/`keyup` for `Enter`. `menu` either pops a navigation history entry or hands control back to SwiftUI (e.g. exits the player view).
4. **Visual feedback.** A persistent focus indicator that survives YouTube's own CSS — outline + box-shadow on `:focus-visible`, plus a custom class the JS toggles. Animate transitions so the user can see where focus moved.

### Edge cases that need design decisions

- **Form fields.** When focus lands on an `<input>`, what does pressing select do? Pop a SwiftUI text-entry sheet? Forward to a UIKit `TVTextInputController`? YouTube's search box is the obvious test surface.
- **Iframes.** YouTube uses `<iframe>` for embedded content (and shadow DOM throughout). Cross-origin iframes are not reachable from the parent's user script — we'd need to inject the focus shim into every frame via `WKUserScript` with `forMainFrameOnly: false`. Even then, shadow DOM walks need explicit `node.shadowRoot` traversal.
- **Scroll containers.** Long lists scroll, but we never want the d-pad to scroll past a focusable element. Focus first, scroll the focused element into view second; only fall back to scroll-only when there's no next focusable in that direction.
- **Player chrome.** YouTube's player has its own keyboard handler (`k` for play/pause, `f` for fullscreen, arrows for seek). The bridge needs to map Siri Remote → those keys when focus is on the video element, instead of trying to walk DOM siblings.
- **Back button (`menu`).** YouTube's SPA pushes history. Should `menu` go back inside the SPA, or exit the WebView? Probably: SPA-back if `history.length > 1`, otherwise exit. Bridge to SwiftUI via a script-message handler.
- **Video controls overlay.** `.ytp-chrome-bottom` only appears on mouse move. The shim has to either emit synthetic mouse-move events on remote activity, or use the YouTube player API (`document.getElementById('movie_player').showControls()`).

### Alternatives considered

- **Apple's `_setEditable:` private API.** Makes WKWebView take focus and accept hardware keyboard input. Routes through WebKit's own focus model rather than building our own. But: same private-SPI fragility cost as the media prefs we already vendor, and YouTube's d-pad handling under that mode hasn't been verified — possibly we'd be debugging YouTube's keyboard shim rather than building our own. Worth a quick spike before committing to the full DIY shim.
- **Native UI for everything except the player.** Build the channel/video browser in SwiftUI, only use the WKWebView for the watch page. Sidesteps most d-pad-in-DOM work but needs a YouTube-data layer reachable from tvOS (probably the same `ChannelBrowser` scrape we already have on macOS) and gives up the "WKWebView is the source of truth" simplification. Closest to a real product, biggest scope.

The current bet is on the JS shim because it's incremental (each fix is a small JS addition, no protocol redesign) and reuses everything from macOS. If the shim turns out to be a tar pit (likely culprits: iframes, shadow DOM, YouTube's own keyboard handler racing ours), pivot to native UI for browsing and keep WKWebView only for playback.

## Reference

- [tvosbrowser](https://github.com/jvanakker/tvosbrowser) — full-page d-pad-driven WKWebView browser. Read its focus-shim JS and `pressesBegan:` translator first; it has handled most of the edge cases above.
- WebKit private API survey for tvOS — particularly `_setEditable:`, `_focusController`, `WKFocusedFormControlView`. None are used in utv yet.

## Definition of done

1. From a fresh launch on Apple TV, the user can navigate the YouTube watch page (cards, recommendations, like button, captions toggle, quality menu) using only the Siri Remote.
2. Search box is reachable and triggers tvOS text entry.
3. Player controls (play/pause, seek ±10s, fullscreen) respond to remote presses while focus is on the video.
4. `menu` button exits the player back to a SwiftUI parent view rather than killing the app.
5. No regressions on macOS — the shim is `#if os(tvOS)` only, or stays no-op when no `UIPressesEvent` handler is attached.
6. Doc is rewritten as a guide ("how the focus shim works") once shipped, per [CLAUDE.md](../CLAUDE.md) working principles.

## Out of scope

- Replacing YouTube's player with native AVPlayer. Stream-extraction was rejected at the start of the tvOS port — see [project memory](../.claude/projects/-Users-adriaan-g-utv/memory/project_tvos_port_strategy.md).
- A general-purpose tvOS web browser. We only need utv's specific YouTube flows to work.
