# tvOS Port Plan

Status: **in progress.** Foundation scaffolding underway. This doc evolves into a guide once implemented. Progress checklist at the bottom.

## Goal

Port utv to tvOS, mirroring macOS as closely as possible: a real `WKWebView` playing the YouTube watch page directly, with the existing ad-blocker pipeline (content rules + scriptlet bundle + CSS hiding) intact.

Personal-use sideload only — uses private APIs, cannot ship via App Store.

## Strategy: vendored headers + `dynamic_lookup`

tvOS ships WebKit on-device at `/System/Library/Frameworks/WebKit.framework/`, but its SDK exposes no public headers and no link-time stub. Inspired by [tvosbrowser](https://github.com/jvanakker/tvosbrowser) but without their pure-runtime-reflection style:

1. **Vendor WebKit headers from the iOS SDK** (`xcrun --sdk iphoneos --show-sdk-path`). Same WebKit binary surface, headers are gitignored and synced on demand.
2. **Build with `-Xlinker -undefined -Xlinker dynamic_lookup`** so unresolved `_OBJC_CLASS_$_WKWebView` and friends are deferred to runtime resolution rather than failing at link time.
3. **`dlopen("/System/Library/Frameworks/WebKit.framework/WebKit")`** at app launch to load the framework.

Result: tvOS callsites read identically to macOS — `WKWebView *web = [[WKWebView alloc] initWithFrame:bounds configuration:cfg]`. No `objc_msgSend` reflection in our code, type-checked, autocompletes. The Objective-C compiler doesn't emit static dispatch for ObjC method calls anyway (always `objc_msgSend`), so the only thing we need from the linker is the class symbol — which `dynamic_lookup` defers to runtime.

For **genuinely private APIs** (the media prefs that tvosbrowser found necessary for YouTube playback), we declare them in our own category header. Clang trusts headers, runtime dispatches normally:

```objc
@interface WKPreferences (UtvPrivate)
- (void)_setMediaSourceEnabled:(BOOL)enabled;
- (void)_setManagedMediaSourceEnabled:(BOOL)enabled;
- (void)_setMediaCapabilityGrantsEnabled:(BOOL)enabled;
@end
```

## Header vendoring workflow

Apple SDK headers are restricted from redistribution, so they're gitignored and synced from the local Xcode install:

```sh
just sync-webkit-headers
```

Layout:
```
Sources/UtvWebKitTV/include/WebKit/
    WKWebView.h
    WKWebViewConfiguration.h
    WKUserContentController.h
    ...
```

Gitignored. Re-run after every Xcode update.

## Module layout

```
Sources/
  UtvWebKitTV/                   # ObjC bridge target. tvOS only — no-op on macOS.
    include/
      UtvWebKitTV.h              # bootstrap + smoke test + private prefs setter
      WebKit/                    # gitignored, populated by `just sync-webkit-headers`
        WKWebView.h
        WKWebViewConfiguration.h
        ...
      module.modulemap           # exposes UtvWebKitTV to Swift; (later) WebKit module on tvOS
    UtvWebKitTV.m                # dlopen + respondsToSelector smoke check + _setMediaSourceEnabled: etc.
  WebPlayerView.swift            # Coordinator logic stays here, shared across platforms
  WebPlayerView+macOS.swift      # NSViewRepresentable using system WKWebView directly
  WebPlayerView+tvOS.swift       # UIViewRepresentable using WKWebView via vendored module
  ContentView.swift              # macOS — unchanged
  ContentView+tvOS.swift         # Focus-driven list view, no NavigationSplitView
```

**Revised approach (narrower than the original sketch):** no monolithic `UtvWebView` wrapper class. WebKit's surface used by `WebPlayerView` and `AdBlocker` is extensive (`WKWebView`, `WKWebViewConfiguration`, `WKUserContentController`, `WKContentRuleListStore`, `WKUserScript`, `WKContentWorld`, `WKNavigationDelegate`, `WKScriptMessageHandler`, `WKNavigationAction`, …); wrapping all of it in ObjC for both platforms would be a lot of duplicate code on macOS for no value.

Instead the bridge target provides only what's strictly tvOS-specific:

1. A C entry point `UtvWebKitBootstrap()` that `dlopen`s the framework on tvOS (no-op on macOS).
2. `UtvWebKitIsAvailable()` — `respondsToSelector:` smoke check on the few methods we depend on.
3. `UtvWebKitEnableYouTubeMediaPrefs(WKWebViewConfiguration *)` — calls the private `_setMediaSourceEnabled:` etc. via a category, without exposing them to Swift.

Plus (in a later step) a `module.modulemap` that re-publishes the vendored WebKit headers as `module WebKit` for tvOS Swift code to import. macOS Swift continues to use the system WebKit module.

Coordinator logic (autoplay-next disable, position tracker, fullscreen override, maximize CSS) lives in `WebPlayerView.swift` and is shared verbatim — only the `make<Platform>View` factory differs across files.

## Runtime smoke test

On app launch (tvOS only):

```swift
guard UtvWebKit.isAvailable else {
    fatalError("WebKit framework not available on this tvOS build")
}
```

`isAvailable` verifies:
- `dlopen` of WebKit.framework succeeded
- `NSClassFromString("WKWebView")` returns a class
- The handful of selectors we depend on (`-loadRequest:`, `-evaluateJavaScript:completionHandler:`, our private prefs) all `respondsToSelector:`

Surfaces a clean error if Apple reshuffles WebKit's API in a future tvOS release rather than crashing mid-frame.

## Build & deploy

New justfile recipes:

```
just sync-webkit-headers   # vendor headers from iOS SDK (this PR)
just build-tv              # swift build for tvOS
just bundle-tv             # assemble .app for tvOS
just deploy-tv             # install to paired Apple TV
```

Sideload requirements (document in README):
1. Apple Developer account (free tier OK for personal sideload — provisioning expires every 7 days)
2. Apple TV in developer mode, paired in Xcode
3. Re-deploy weekly (free-tier provisioning expiry — drives the cadence at which we accept SDK header drift risk)

## Risks / things to verify before committing to the port

1. **Content rules apply.** Compile `content-rules.json` via runtime-loaded `WKContentRuleListStore` and confirm blocking works.
2. **Custom UA respected.** Set our Safari/macOS UA, confirm YouTube serves the desktop player.
3. **Performance.** YouTube SPA + scriptlet bundle on Apple TV hardware. Target A12 Bionic minimum.
4. **Siri Remote in WKWebView.** Likely the web view doesn't accept focus/input at all on tvOS. Our maximize CSS already hides YouTube chrome, so we only need play/pause + back, both bridged from the host SwiftUI layer via JS. Verify focus behavior early.

## Out of scope

- Stream-URL extraction / native AVPlayer fallback. See [project memory](../../.claude/...): the WKWebView path is the only playback strategy.
- App Store distribution.
- Channel browsing / list UI redesign — start macOS-faithful, refine if Siri Remote forces changes.

## When done

This doc rewrites itself: "Strategy" becomes "How the bridge works", "Risks" become validated decisions or known limitations, the verification list becomes a smoke-test checklist for new tvOS releases.

## Progress checklist

- [x] Plan + header-vendoring recipe (`just sync-webkit-headers`) committed
- [x] `Sources/UtvWebKitTV/` bridge target scaffolded — `UtvWebKitBootstrap()`, `UtvWebKitIsAvailable()`, `UtvWebKitEnableYouTubeMediaPrefs()`. Wired into `WebPlayerView.makeWebView`. No-op on macOS, ready for tvOS code paths.
- [x] `Package.swift` declares the `UtvWebKitTV` target with `-undefined dynamic_lookup` linker flag and tvOS-conditioned vendored-headers search path.
- [ ] `Package.swift` declares tvOS as a supported platform (currently macOS-only)
- [ ] `module.modulemap` re-publishes vendored WebKit as `module WebKit` for tvOS Swift
- [ ] `WebPlayerView` split into platform-specific representables
- [ ] tvOS app target with focus-driven `ContentView+tvOS`
- [ ] Bundle + deploy scripts (`just bundle-tv`, `just deploy-tv`)
- [ ] First sideload to Apple TV — verify ad blocking + playback + Siri Remote

### Notes from scaffolding

- SwiftPM's auto-generated modulemap rejects sibling directories next to an umbrella header (we have `include/UtvWebKitTV.h` AND `include/WebKit/`). An explicit `include/module.modulemap` listing only `UtvWebKitTV.h` sidesteps the check.
- `WKWebViewConfiguration *` parameter in the bridge header is forward-declared (`@class WKWebViewConfiguration;`). This avoids requiring importers of `UtvWebKitTV` to also see the WebKit module — Swift unifies the type at the call site via its own `import WebKit`.
