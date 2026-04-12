# <img src="docs/icon.png" width="32" height="32" alt="utv icon"> utv

A simple YouTube browser for macOS. Like an old-school TV: pick a channel, watch a video. No ads.

No login, no Google account, no YouTube API. All state is local. You can't like, comment, or subscribe — use "Open in Browser" for that.

Ad blocking is powered by [uBlock Origin](https://github.com/gorhill/uBlock) filter lists, compiled into WebKit content blockers.

If you enjoy a creator's work, support them directly — merch, Patreon, or whatever they offer.

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

Requires [Xcode](https://developer.apple.com/xcode/):

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
git clone --recursive https://github.com/adriaanm/utv.git
cd utv
just build   # init submodules + build
just run     # build + launch app
```
