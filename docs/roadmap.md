# Roadmap

## Strategy

Start with macOS, port to tvOS later. macOS gives us Safari Web Inspector for debugging content blockers, faster iteration, and no provisioning hassle. The core WebKit content blocking API is identical on both platforms.

## Phase 1: macOS proof-of-concept

Goal: play the latest video from a given YouTube channel with ads blocked.

### 1a. Ad blocking in WKWebView

- [x] Handcrafted WebKit content blocker rules (`content-rules.json`) — blocks ad domains, tracking URLs
- [x] Inject full uBOL scriptlet bundle (`ubo-scriptlets.js`) via `WKUserScript` at document start
- [x] CSS hiding rules for ad UI elements
- [ ] Test against YouTube — verify pre-roll, mid-roll, and banner ads are blocked
- [ ] Handle YouTube's anti-adblock detection if needed

Key finding: Chrome DNR rulesets from uBOL-home aren't WebKit-compatible, but the **scriptlet bundle** is self-contained and works in any browser context. It strips `adPlacements`, `adSlots`, `playerAds` from YouTube API responses via json-prune/prevent-fetch/prevent-xhr.

### 1b. Minimal playback

- [x] WKWebView loading YouTube watch page with Safari user-agent
- [x] RSS feed parsing (`ChannelFeed.swift`) to find latest video from channel ID
- [x] Resolve @handles and full URLs to channel IDs
- [x] Auto-play latest video in WebView
- [ ] Basic transport controls (may get these for free from the web player)

### 1c. Package as macOS app

- [x] Xcode project (generated via xcodegen from `project.yml`)
- [x] SwiftUI app with channel input + WebPlayerView
- [x] `just sync` / `just build` / `just run` recipes
- [ ] Test with real channels

## Phase 2: make it actually usable (macOS)

- [ ] Channel list / subscription management
- [ ] Browse recent videos per channel
- [ ] Background filter updates (re-run sync, recompile rules)
- [ ] Persist state (last watched, subscriptions)

## Phase 3: tvOS port

- [ ] New tvOS target in the Xcode project, sharing the WebView + content blocking core
- [ ] Focus-based UI for Siri Remote navigation
- [ ] TV-appropriate layout (10-foot UI)
- [ ] TestFlight distribution

## Open questions

- Can `WKContentRuleList` handle the full uBO ruleset size, or do we need to trim? (WebKit has a 50k rule limit per list, but allows multiple lists)
- Do the scriptlet injections work reliably in WKWebView, or does YouTube detect the injection method?
- Is the YouTube RSS feed reliable enough for "latest video", or do we need the Data API?
