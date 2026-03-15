# utv

A tvOS app for watching YouTube without ads.

## Why

YouTube on Apple TV is awful. The official app serves unskippable ad breaks that get longer every year — 2, 3, sometimes 5 ads in a row before a video plays. YouTube Premium costs $14/month for what should be the default experience. Third-party tvOS clients get pulled from the App Store. Browser-based solutions don't exist on tvOS because there's no browser.

This project takes a different approach: a native tvOS app built around WKWebView that loads YouTube's web player, with uBlock Origin's filter lists compiled into WebKit content blockers. No jailbreak, no sideloading someone else's app, no subscription.

## How it works

WebKit on tvOS supports content blocking rules — the same JSON format Safari extensions use. uBlock Origin maintains the most actively updated filter lists targeting YouTube ads. We track three upstream uBO repositories as git submodules and extract the relevant rules:

- **Filter lists** — ABP-syntax rules that match YouTube ad requests by URL pattern
- **Declarative rulesets** — pre-compiled JSON rules ready for WebKit's content blocker API
- **Scriptlets** — JavaScript that intercepts ad-related fetch/XHR requests and prunes ad configuration from YouTube's API responses

YouTube changes its ad delivery constantly. By tracking uBO upstream directly, we inherit updates from a large community that actively reverse-engineers and patches against these changes.

See [docs/ubo-tracking.md](docs/ubo-tracking.md) for details on the submodule setup and sync process.

## Setup

```sh
git clone --recursive <repo-url>
./scripts/sync-ubo.sh
```
