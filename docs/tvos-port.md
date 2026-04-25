# tvOS Port Plan

Status: **planning** (no code yet). This doc evolves into a guide once implemented.

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
tvOS/
  Vendored/
    WebKit/                      # gitignored, regenerate with just sync-webkit-headers
      WKWebView.h
      WKWebViewConfiguration.h
      WKUserContentController.h
      ...
```

Re-run after every Xcode update. The `_ensure-resources` recipe (already used by `just build`) is extended to call this if the directory is missing, so the workflow stays a single `just build`.

## Module layout

```
Sources/
  UtvWebKit/                     # New ObjC bridge target (built for both platforms)
    include/
      UtvWebKit.h                # Public Swift-facing interface
      UtvWebKitPrivate.h         # Private WebKit category declarations
      module.modulemap           # exposes UtvWebKit to Swift
    UtvWebView.m                 # Bridge implementation (#if for platform branches)
  WebPlayerView.swift            # Existing — Coordinator logic stays here, shared
  WebPlayerView+macOS.swift      # NSViewRepresentable wrapping WKWebView directly
  WebPlayerView+tvOS.swift       # UIViewRepresentable wrapping UtvWebView
  ContentView.swift              # macOS — unchanged
  ContentView+tvOS.swift         # Focus-driven list view, no NavigationSplitView
```

Coordinator logic (autoplay-next disable, position tracker, fullscreen override, maximize CSS) is verbatim shared in extensions on `WebPlayerView` — only the `make<Platform>View` differs.

## Bridge surface

Mirrors exactly what `WebPlayerView`'s Coordinator uses today, in Swift-friendly ObjC:

```objc
@interface UtvWebView : UIView
- (instancetype)initWithUserAgent:(NSString *)userAgent;

// Configuration (called before first load)
- (void)addUserScriptSource:(NSString *)source
              atDocumentStart:(BOOL)atStart
                  inPageWorld:(BOOL)inPageWorld;
- (void)addMessageHandler:(id<UtvWebViewMessageHandler>)handler name:(NSString *)name;
- (void)addContentRuleList:(WKContentRuleList *)list;
+ (void)compileContentRuleListJSON:(NSString *)json
                         identifier:(NSString *)identifier
                         completion:(void (^)(WKContentRuleList *, NSError *))cb;

// Navigation
@property (nonatomic, copy) NSString *customUserAgent;
@property (nonatomic, weak) id<UtvWebViewNavigationDelegate> navigationDelegate;
- (void)loadURL:(NSURL *)url;
- (void)evaluateJavaScript:(NSString *)js
            completionHandler:(void (^_Nullable)(id _Nullable, NSError *_Nullable))cb;
- (void)pauseAllMedia;
@end
```

On macOS this is a thin pass-through to `WKWebView`. On tvOS the same code compiles against the vendored headers; `dynamic_lookup` and `dlopen` make it work at runtime.

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
