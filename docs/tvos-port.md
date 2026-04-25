# tvOS Port Plan

Status: **in progress.** App launches on Apple TV; ad blocker (all three layers — content rules + scriptlet bundle + CSS hiding) is green on hardware and a hardcoded YouTube watch URL plays end-to-end. d-pad navigation inside the WKWebView is the next big task (see [docs/tvos-dpad-navigation.md](tvos-dpad-navigation.md)). Progress checklist at the bottom.

## Goal

Port utv to tvOS, mirroring macOS as closely as possible: a real `WKWebView` playing the YouTube watch page directly, with the existing ad-blocker pipeline (content rules + scriptlet bundle + CSS hiding) intact.

Personal-use sideload only — uses private APIs, cannot ship via App Store.

## Strategy: vendored headers + `dynamic_lookup`

tvOS ships WebKit on-device at `/System/Library/Frameworks/WebKit.framework/`, but its SDK exposes no public headers and no link-time stub. Inspired by [tvosbrowser](https://github.com/jvanakker/tvosbrowser) but without their pure-runtime-reflection style:

1. **Vendor WebKit headers from the iOS SDK** (`xcrun --sdk iphoneos --show-sdk-path`). Same WebKit binary surface, headers are gitignored and synced on demand.
2. **Build with `-Xlinker -undefined -Xlinker dynamic_lookup`** so unresolved `_OBJC_CLASS_$_WKWebView` and friends are deferred to runtime resolution rather than failing at link time.
3. **`dlopen("/System/Library/Frameworks/WebKit.framework/WebKit")`** at app launch to load the framework.

Result: tvOS callsites read identically to macOS — `WKWebView *web = [[WKWebView alloc] initWithFrame:bounds configuration:cfg]`. No `objc_msgSend` reflection in our code, type-checked, autocompletes. The Objective-C compiler doesn't emit static dispatch for ObjC method calls anyway (always `objc_msgSend`), so the only thing we need from the linker is the class symbol — which `dynamic_lookup` defers to runtime.

### Caveat: dyld eagerly binds class refs

`-undefined dynamic_lookup` defers function symbol resolution to runtime, but ObjC class refs (`_OBJC_CLASS_$_WKFoo` entries in `__objc_classrefs`) are **eagerly bound by dyld during image load**, before any user code runs — including before `UtvWebKitBootstrap` can `dlopen` WebKit. If the symbol isn't already in the flat namespace at that point, dyld kills the process with `symbol not found in flat namespace '_OBJC_CLASS_$_WKWebView'`.

This means **any Swift class-level reference** to a WebKit class — `WKWebView(frame:configuration:)`, `WKWebViewConfiguration()`, `WKWebsiteDataStore.default()`, `WKUserScript(source:…)`, `WKContentWorld.page` — emits a class ref that dyld will fail on at launch. Instance-level method calls on already-typed values are fine (selector dispatch via `objc_msgSend`); only class-level construction and class-method calls produce the offending refs.

Workaround: every WebKit class construction or class-method call on tvOS goes through a C bridge function in `UtvWebKitTV.m` that uses `NSClassFromString` (resolved at runtime *after* the dlopen). Currently bridged: `UtvWebKitMakeWebView`, `UtvWebKitMakeConfiguration`, `UtvWebKitMakeUserScript`, `UtvWebKitDefaultDataStore`, `UtvWebKitAllWebsiteDataTypes`, `UtvWebKitCompileContentRuleList`. macOS keeps the direct Swift constructors via `#if os(tvOS) … #else … #endif`.

`UtvWebKitCompileContentRuleList` is the most involved bridge — it has to call a class method (`+[WKContentRuleListStore defaultStore]`) and then an instance method whose completion handler hands back another WebKit type (`WKContentRuleList`) without ever letting either type's class ref into the binary. The bridge dispatches both via `objc_msgSend` after `respondsToSelector:` checks, then routes the resulting `WKContentRuleList` back into `[WKUserContentController addContentRuleList:]` (also via `objc_msgSend`). Swift only sees the `WKUserContentController *` parameter and an error-only completion. The `WKContentRuleListStore` SDK header is annotated `API_AVAILABLE(macos, ios)` with no tvOS — but the runtime class IS shipped in `/System/Library/Frameworks/WebKit.framework` on tvOS (single WebKit binary across platforms), so `NSClassFromString` resolves it.

The Objective-C bridge itself can use the WebKit types as parameter / return types in its function signatures — those don't emit class refs, only forward declarations.

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
Sources/VendoredWebKit/include/WebKit/
    WKWebView.h
    WKWebViewConfiguration.h
    WKUserContentController.h
    ...
```

Gitignored. Re-run after every Xcode update. Owned by the `VendoredWebKit` target so a single header copy serves both `UtvWebKitTV`'s `#import`s and the `module WebKit` Swift shim.

## Module layout

SwiftPM cross-compiles a tvOS Mach-O cleanly but produces no `.app` bundle. The tvOS app target is therefore an Xcode project, generated from `tvos/project.yml` by XcodeGen, that consumes the SwiftPM package as a local dependency. The shared SwiftUI Scene was extracted into a `utvCore` library so it can be reused by both the macOS executable and the tvOS Xcode target.

```
Package.swift                  # macOS exe (utv) + utvCore library + UtvWebKitTV bridge
Sources/
  utv/utvApp.swift             # macOS @main wrapper (12 lines) — instantiates AppRoot
  utvCore/                     # all SwiftUI views, models, services, ad-block, scriptlets
    AppRoot.swift              # WindowGroup + macOS commands; the shared Scene
    ContentView.swift          # macOS body (#if os(macOS)) + tvOS placeholder
    WebPlayerView.swift        # Coordinator + NSViewRepresentable (macOS) /
                               # UIViewRepresentable (tvOS) — JS-injection logic shared
    AdBlocker.swift, ConsentManager.swift, ChannelFeed.swift, …
    Models/, Services/, Resources/
  UtvWebKitTV/                 # ObjC bridge: dlopen + private prefs category. No-op on macOS.
    include/UtvWebKitTV.h, module.modulemap
    UtvWebKitTV.m
  VendoredWebKit/              # tvOS-only. Owns vendored iOS-SDK WebKit headers + `module WebKit` shim.
    include/module.modulemap, WebKit/   # WebKit/ is gitignored; sync via just sync-webkit-headers
    VendoredWebKit.m

tvos/                          # XcodeGen-driven tvOS app target
  project.yml                  # consumes utv package -> utvCore + UtvWebKitTV products
  utv-tv/
    App.swift                  # @main wrapper — calls UtvWebKitBootstrap() then renders AppRoot
    Info.plist
    Assets.xcassets/           # empty for now (see "Asset catalog" below)
  utv-tv.xcodeproj/            # gitignored; regenerate with `just gen-tv`
```

**Why XcodeGen and not pure SwiftPM?** SwiftPM `xcodebuild -scheme utv` doesn't produce an `.app` bundle for executable products on tvOS — it links the binary but skips bundling/Info.plist/asset compilation/code signing. An Xcode project target does all of that. XcodeGen lets us keep `tvos/project.yml` (small, hand-written, in-tree) without checking the generated `.xcodeproj` into git.

**Revised approach (narrower than the original sketch):** no monolithic `UtvWebView` wrapper class. WebKit's surface used by `WebPlayerView` and `AdBlocker` is extensive (`WKWebView`, `WKWebViewConfiguration`, `WKUserContentController`, `WKContentRuleListStore`, `WKUserScript`, `WKContentWorld`, `WKNavigationDelegate`, `WKScriptMessageHandler`, `WKNavigationAction`, …); wrapping all of it in ObjC for both platforms would be a lot of duplicate code on macOS for no value.

Instead the bridge target provides only what's strictly tvOS-specific:

1. A C entry point `UtvWebKitBootstrap()` that `dlopen`s the framework on tvOS (no-op on macOS).
2. `UtvWebKitIsAvailable()` — `respondsToSelector:` smoke check on the few methods we depend on.
3. `UtvWebKitEnableYouTubeMediaPrefs(WKWebViewConfiguration *)` — calls the private `_setMediaSourceEnabled:` etc. via a category, without exposing them to Swift.

Plus (in a later step) a `module.modulemap` that re-publishes the vendored WebKit headers as `module WebKit` for tvOS Swift code to import. macOS Swift continues to use the system WebKit module.

Coordinator logic (autoplay-next disable, position tracker, fullscreen override, maximize CSS) lives in `WebPlayerView.swift` and is shared verbatim — only the `make<Platform>View` factory differs across files.

## Runtime bootstrap

On the first `WebPlayerView.makeWebView`, we call `UtvWebKitBootstrap()` (no return-value check — the bridge falls back through three candidate framework paths and idempotently caches success). `UtvWebKitIsAvailable()` does a `respondsToSelector:` smoke check on the methods we depend on, but we don't currently gate launch on it; if Apple reshuffles WebKit's surface, we'd see it as a bridge call returning nil rather than a clean fatalError. Wire `IsAvailable` into the launch path if that becomes a real risk.

## Build & deploy

```
just sync-webkit-headers   # vendor headers from iOS SDK (re-run after Xcode updates)
just build-tv              # SwiftPM cross-compile (no .app — just verifies the package compiles for tvOS)
just gen-tv                # regenerate tvos/utv-tv.xcodeproj from project.yml (XcodeGen)
just bundle-tv             # xcodebuild Release .app — unsigned, useful for inspecting the bundle
just deploy-tv             # build signed + sideload to the single paired Apple TV
just launch-tv             # launch utv on the paired Apple TV (returns immediately)
just launch-tv-console     # launch + stream stdout/stderr from the device until exit
just kill-tv               # SIGKILL any running utv process on the Apple TV
just iterate-tv            # deploy-tv + launch-tv-console — the inner-loop iteration recipe
```

The launch/kill recipes wrap `xcrun devicectl device process …` and read the device UDID from `$TV_DEVICE_ID` (set in `.envrc` via direnv — `scripts/deploy-tv.sh` auto-detects the value to seed it). `launch-tv-console` is the workhorse for debugging dyld errors and Swift fatal errors: it streams the process's stdio over the USB/network bridge so you see crash output without round-tripping through `just logs-tv`. `iterate-tv` chains a fresh deploy with a console launch — the standard build → run → observe loop.

`scripts/deploy-tv.sh` auto-detects the paired TV (`xcrun devicectl list devices --json-output`, filtering for `deviceType=appleTV` + `pairingState=paired` and extracting the xcodebuild-style 8-16-hex UDID from `potentialHostnames`) and the signing team (`defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier`). Override either with `DEVELOPMENT_TEAM=XXXXXXXXXX scripts/deploy-tv.sh`.

Sideload requirements:
1. Apple Developer account (free tier OK — provisioning expires every 7 days)
2. Apple TV paired in Xcode (Cmd-Shift-2 → Devices and Simulators)
3. Re-deploy weekly when the provisioning profile expires

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
- [x] `VendoredWebKit` target added — owns the gitignored iOS-SDK WebKit headers and a `module.modulemap` declaring `module WebKit`. Conditionally depended on by `utv` and `UtvWebKitTV` only on tvOS.
- [x] `Package.swift` declares `tvOS(.v17)` as a supported platform.
- [x] `just sync-webkit-headers` patches iOS-only UIKit references in `WKNavigationAction.h` / `WKUIDelegate.h` so the WebKit clang module compiles on tvOS. (See "Header patching" below.)
- [x] tvOS clang build of the `UtvWebKitTV` and `VendoredWebKit` targets verified.
- [x] `just build-tv` recipe — runs `swift build --triple arm64-apple-tvos17.0 --sdk $(xcrun --sdk appletvos --show-sdk-path)`.
- [x] `WebPlayerView` and `ConsentWebView` platform-conditioned: `NSViewRepresentable` on macOS, `UIViewRepresentable` on tvOS, all coordinator/JS-injection logic shared.
- [x] `ContentView` macOS body wrapped in `#if os(macOS)`; minimal tvOS placeholder `ContentView` loads a hardcoded `WebPlayerView` for first-sideload smoke test.
- [x] `utvApp` `.commands` and `.defaultSize` scoped to macOS.
- [x] **Whole-package tvOS build green** — `swift build --triple arm64-apple-tvos17.0` links a tvOS executable. Two non-fatal warnings: `using sysroot for 'MacOSX' but targeting 'AppleTV'` (clang on the C target) and `-undefined dynamic_lookup is deprecated on tvOS` (linker — still works).
- [x] **Library/executable refactor** — split SwiftPM target into `utvCore` library + thin `utv` executable. `AppRoot` extracts the SwiftUI Scene so the tvOS Xcode target reuses it.
- [x] **XcodeGen scaffold** — `tvos/project.yml` generates `utv-tv.xcodeproj` (gitignored) consuming the SwiftPM package's `utvCore` + `UtvWebKitTV` library products.
- [x] **`just bundle-tv` + `just deploy-tv`** — `xcodebuild` produces a Release `.app`; `scripts/deploy-tv.sh` builds signed and installs to the single paired Apple TV via `xcrun devicectl device install app`.
- [x] **`just launch-tv` / `launch-tv-console` / `iterate-tv` / `kill-tv`** — `$TV_DEVICE_ID`-driven recipes wrapping `xcrun devicectl device process …`. `iterate-tv` chains deploy + launch-with-console for the dyld-error iteration loop. `TV_DEVICE_ID` lives in `.envrc` (direnv).
- [x] **App launches on Apple TV** — clean dyld load. Took routing every WebKit class construction through a C bridge in `UtvWebKitTV.m` (see "Caveat: dyld eagerly binds class refs" above). AdBlocker scriptlet injection succeeds; WebKit's filesystem-permission warnings on launch are non-fatal sandbox noise.
- [x] **`WKContentRuleListStore` bridged on tvOS** — `UtvWebKitCompileContentRuleList` resolves the store + compile method via `NSClassFromString` + `objc_msgSend`, and pipes the resulting `WKContentRuleList` into `addContentRuleList:` without exposing either WebKit type to Swift. Restores the WebKit-native content-blocker layer (uBO filter list → JSON rules) so tvOS gets the same three-layer ad-block stack as macOS. tvOS routes the store at a custom URL inside `Library/Caches/ContentRuleListStore` rather than `+defaultStore` — the default path lives under `~/Library/WebKit/`, which the tvOS sandbox refuses to create (you'll see `Operation not permitted` for `WebsiteData/MediaKeys`, `IndexedDB`, etc. at WKWebView init), causing the compile to fail with `WKErrorDomain code 6 (WKErrorContentRuleListStoreCompileFailed)`. macOS keeps `+defaultStore`.
- [x] **Consent-cookie gate on tvOS `ContentView`** — Siri Remote can't click YouTube's GDPR consent banner inside a WKWebView (no DOM focus engine bridge), so on tvOS we never show the banner: `ContentView` waits for the Mac → TV sync to deliver the SOCS cookie (see [docs/sync-design.md](sync-design.md)) before mounting `WebPlayerView`. If the Mac isn't reachable, an actionable retry view fronts the WebView. Cached cookies from prior sessions are re-injected before mount via `ConsentManager.ensureConsent()`.
- [x] **First sideload to Apple TV** — `[WebPlayer] didFinish https://www.youtube.com/watch?v=…` confirms the YouTube watch page reaches navigation completion on hardware after Mac→TV cookie sync. AdBlocker logs all three layers as installed (`Scriptlet bundle injected (573 397 bytes)` + `Content rules compiled and loaded (tvOS bridge)` + the always-on CSS hide script). Visual playback verification is still a remote-needs-eyes step but the data path is clean.
- [x] **Visual playback confirmation** — Rick Astley plays end-to-end on the Apple TV from a hardcoded `dQw4w9WgXcQ` watch URL. (2026-04-25)
- [ ] Restore tvOS app icon — currently empty (see "Asset catalog" below)
- [ ] **d-pad navigation inside the WKWebView** — Siri Remote presses → DOM focus + synthetic clicks. Prerequisite for any HTML-driven UI on tvOS, including the focus-driven channel browser. Picks up after first sideload validates cookie sync + playback. Full design + edge cases in [docs/tvos-dpad-navigation.md](tvos-dpad-navigation.md).
- [ ] Focus-driven `ContentView` for tvOS — channel list, video list, player. Blocked on the d-pad bridge above; the shape of the UI (HTML inside WebView vs. native SwiftUI alongside it) depends on how tractable the JS focus shim turns out to be.

### Cross-compile invocation

```sh
just build-tv
# == swift build --triple arm64-apple-tvos17.0 --sdk $(xcrun --sdk appletvos --show-sdk-path)
```

Two warnings during the cross-compile are expected and harmless:

1. `clang: warning: using sysroot for 'MacOSX' but targeting 'AppleTV'` — SwiftPM's auto-detected sysroot for the C target is the host's macOS SDK, but the explicit `--triple` makes clang target tvOS. The vendored WebKit headers + UIKit references all resolve via the explicit `-isysroot` we'd otherwise pass; in practice it builds cleanly.
2. `ld: warning: -undefined dynamic_lookup is deprecated on tvOS` — Apple has deprecated the flag for App Store builds, but it still works. We rely on it because the tvOS SDK exposes no link-time stub for WebKit; `UtvWebKitBootstrap()` `dlopen`s the framework before any WKWebView use. Since this is a personal-sideload project, the deprecation doesn't affect us.

### Notes from scaffolding

- SwiftPM's auto-generated modulemap rejects sibling directories next to an umbrella header (we have `include/UtvWebKitTV.h` AND `include/WebKit/`). An explicit `include/module.modulemap` listing only `UtvWebKitTV.h` sidesteps the check.
- `WKWebViewConfiguration *` parameter in the bridge header is forward-declared (`@class WKWebViewConfiguration;`). This avoids requiring importers of `UtvWebKitTV` to also see the WebKit module — Swift unifies the type at the call site via its own `import WebKit`.

### Exposing `module WebKit` to Swift on tvOS

Cross-platform Swift code (`WebPlayerView`, `AdBlocker`) does `import WebKit`. On macOS that resolves to the system framework. On tvOS the system has no WebKit Swift/clang module — we need a clang module declaration that points at the vendored headers.

A `module WebKit` declaration inside `UtvWebKitTV/include/` would conflict with the system WebKit on macOS where both would be visible to the same target. Solution: a **separate `VendoredWebKit` target conditionally depended on only for tvOS** (`condition: .when(platforms: [.tvOS])`). Its `include/` directory owns the gitignored vendored headers plus a tracked `module.modulemap` declaring `module WebKit { umbrella header "WebKit/WebKit.h" export * module * { export * } }`. On macOS the target isn't in the build graph at all, so its modulemap is invisible. On tvOS it is, and Swift's `import WebKit` resolves to it.

`UtvWebKitTV` (the ObjC bridge) also depends on `VendoredWebKit` on tvOS via `headerSearchPath("../VendoredWebKit/include")`, so its `#import "WebKit/WKWebView.h"` etc. find the same single-source-of-truth header copy.

`just sync-webkit-headers` writes the headers into `VendoredWebKit/include/WebKit/`. The modulemap and bridge target both reference that location.

### Asset catalog

The tvOS asset catalog at `tvos/utv-tv/Assets.xcassets` ships **empty** — no `App Icon & Top Shelf Image.brandassets`. tvOS layered (parallax) icons require `actool` to spawn an Interface Builder simulator device for parallax preview rendering, and on this machine `~/Library/Developer` is symlinked to an external SSD that `CoreSimulatorService` can't write to (TCC restricts daemon writes to external volumes — `Operation not permitted` when creating `<UUID>/data/Library/Caches`). The build previously failed at:

```
Failed to find a suitable device for the type IBAppleTVSimDeviceType1080p ...
Device was allocated but was stuck in creation state.
```

For now the app sideloads with the default tvOS icon. To restore: regenerate the `.brandassets` from `AppIcon.iconset/` and either grant Full Disk Access to `CoreSimulatorService` for the external volume, or move `~/Library/Developer` back onto the internal disk.

### Header patching

The vendored iOS WebKit headers reference iOS UIKit types that don't exist on tvOS:

- `UIEventButtonMask` (used by `WKNavigationAction.buttonNumber`) — tvOS has no UIKit pointer/click events.
- `UIEditMenuInteractionAnimating` (used by `WKUIDelegate willPresent/willDismissEditMenu:`) — tvOS has no edit menus.

We never call those WebKit APIs from utv, so `just sync-webkit-headers` strips the offending single-line declarations after copying the headers. This keeps the WebKit clang module buildable on tvOS without touching the rest of the surface. Re-run on every Xcode update; if Apple changes the offending declarations, add the new patterns to the recipe.
