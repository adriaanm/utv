# Roadmap

## Strategy

Start with macOS, port to tvOS later. macOS gives us Safari Web Inspector for debugging content blockers, faster iteration, and no provisioning hassle. The core WebKit content blocking API is identical on both platforms.

## Phase 1: macOS proof-of-concept [done]

Goal: play the latest video from a given YouTube channel with ads blocked.

### 1a. Ad blocking in WKWebView

- [x] Handcrafted WebKit content blocker rules (`content-rules.json`) — blocks ad domains, tracking URLs
- [x] Inject full uBOL scriptlet bundle (`ubo-scriptlets.js`) via `WKUserScript` at document start
- [x] CSS hiding rules for ad UI elements
- [x] Test against YouTube — pre-roll ads blocked, cookie consent bypassed

Key findings:
- Chrome DNR rulesets from uBOL-home aren't WebKit-compatible, but the **scriptlet bundle** is self-contained and works in any browser context. It strips `adPlacements`, `adSlots`, `playerAds` from YouTube API responses via json-prune/prevent-fetch/prevent-xhr.
- Scriptlets **must** be injected into `WKContentWorld.page` (not the default isolated world) so they can intercept the page's `fetch`/`XHR`/`JSON.parse`.
- GDPR cookie consent can be bypassed by pre-setting the `SOCS` cookie.

### 1b. Minimal playback

- [x] WKWebView loading YouTube watch page with Safari user-agent
- [x] RSS feed parsing (`ChannelFeed.swift`) to find latest video from channel ID
- [x] Resolve @handles and full URLs to channel IDs
- [x] Auto-play latest video in WebView

### 1c. Package as macOS app

- [x] Xcode project (generated via xcodegen from `project.yml`)
- [x] SwiftUI app with channel input + WebPlayerView
- [x] `just sync` / `just build` / `just run` recipes

## Phase 2: usable macOS app [done]

- [x] Channel subscriptions — add by @handle, persist with SwiftData
- [x] Video list — browse recent videos per channel, thumbnails, unread badges
- [x] NavigationSplitView — sidebar collapses on play, restores on back
- [x] Player maximization — CSS injection hides YouTube chrome, fills viewport
- [x] Playback position tracking — resume where you left off, progress bars
- [x] Open in browser — for liking/commenting (no login in app)
- [x] Feed refresh — on launch + manual toolbar button

## Phase 2b: iPad port [done]

- [x] iOS target in project.yml sharing the same source folder
- [x] Platform conditionals for "Open in Browser" (UIApplication vs NSWorkspace)
- [x] Player bottom bar on iOS (back button + title + open in browser)
- [x] Consent/cookie management accessible via toolbar menu on iOS
- [x] `just build-ios` recipe targeting iPad simulator

## Phase 3: tvOS port — not feasible

tvOS has no WebKit/WKWebView, so the core playback approach doesn't work. We explored several alternatives on the `experiment-apple-tv` branch:

- **Innertube API** (ANDROID_VR client identity) — returns direct stream URLs, but YouTube blocks with "sign in to prove you're not a bot"
- **Headless WKWebView extraction** — YouTube uses MSE/UMP (MediaSource + proprietary chunked protocol), so `video.currentSrc` is a `blob:` URL, not a direct video URL
- **Fetch interception + n-parameter deciphering** — amounts to reimplementing yt-dlp's signature logic, which is fragile and breaks with every YouTube player update
- **HTTPS proxy on WKWebView traffic** — can't inspect encrypted traffic without MITM CA, and WKWebView doesn't expose proxy configuration

**Conclusion:** tvOS streaming requires either a WebKit port to tvOS (unlikely from Apple) or maintaining a yt-dlp-equivalent decipher engine (not sustainable for a personal project). Parking this until the platform landscape changes.

## Ad blocking maintenance

This is a personal-use app. We don't need automated filter pipelines — just a manual process for when YouTube changes break ad blocking. See [docs/ubo-tracking.md](ubo-tracking.md) for the full workflow.

**TL;DR**: Three layers, maintained independently:
1. **Scriptlet bundle** (`ubo-scriptlets.js`) — `just sync` pulls latest from uBOL-home. This is the heavy lifter.
2. **Content rules** (`content-rules.json`) — hand-written WebKit blocker rules for ad domains/URLs. Edit manually.
3. **CSS hiding** (in `AdBlocker.swift`) — hides ad UI elements. Edit manually.

When ads start appearing: run `just sync`, test, and if needed update the content rules or CSS by checking uAssets upstream diffs.

## Backlog

- [ ] Automate YouTube consent flow — currently the user has to click a video, trigger the cookie banner, and accept manually. Low priority since it only happens once per machine.

## Open questions

- Can `WKContentRuleList` handle the full uBO ruleset size, or do we need to trim? (WebKit has a 50k rule limit per list, but allows multiple lists)
- Is the YouTube RSS feed reliable enough, or do we need the Data API? (So far: reliable, 15 most recent videos)
