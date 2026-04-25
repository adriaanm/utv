# <img src="docs/icon.png" width="32" height="32" alt="utv icon"> utv

A personal YouTube viewer for macOS. Subscribe to channels, browse their videos, watch without ads. No shorts, no recommendations, no algorithm.

A tvOS port is also working on Apple TV — same WKWebView pipeline, same uBO ad blocking, hardware-validated playback. It isn't fully standalone yet: the YouTube consent cookie and channel list come from the Mac over MultipeerConnectivity (see [docs/sync-design.md](docs/sync-design.md)), and the focus-driven UI for browsing is still landing (the watch page itself plays from a hardcoded video for now). Sideload only — uses private APIs, won't ship via App Store. See [docs/tvos-port.md](docs/tvos-port.md).

Videos are grouped by watch state — unwatched, started, watched — and resume where you left off. Subscriptions and watch history live on your machine; nothing is sent anywhere.

No Google login and no YouTube API: channels are tracked via their public `/videos` page, ads are stripped by [uBlock Origin](https://github.com/gorhill/uBlock) filter lists compiled into WebKit content blockers. Liking, commenting, and subscribing aren't supported — use "Open in Browser" for that, and support creators directly through whatever they offer.

Built with [Claude Code](https://claude.ai/claude-code).

## Install

Download and run the latest release (macOS, Apple Silicon):

```sh
curl -fLo ~/Downloads/utv-macos-arm64.zip https://github.com/adriaanm/utv/releases/download/latest/utv-macos-arm64.zip \
  && ditto -x -k ~/Downloads/utv-macos-arm64.zip /Applications/ \
  && xattr -cr /Applications/utv.app \
  && open /Applications/utv.app
```

The app is ad-hoc signed (not notarized), so `xattr -cr` is needed to clear the Gatekeeper quarantine flag.

## Build from source

Requires [Homebrew](https://brew.sh) and [just](https://github.com/casey/just):

```sh
brew install just
git clone --recursive https://github.com/adriaanm/utv.git && cd utv
just run       # sync filters + build + launch
just install   # release build + install to /Applications
```
