# <img src="docs/icon.png" width="32" height="32" alt="utv icon"> utv

A simple YouTube browser for macOS. Like an old-school TV: pick a channel, watch a video. No ads.

No login, no Google account, no YouTube API. All state is local. You can't like, comment, or subscribe — use "Open in Browser" for that.

Ad blocking is powered by [uBlock Origin](https://github.com/gorhill/uBlock) filter lists, compiled into WebKit content blockers.

If you enjoy a creator's work, support them directly — merch, Patreon, or whatever they offer.

Built with [Claude Code](https://claude.ai/claude-code).

## Setup

Requires [Xcode](https://developer.apple.com/xcode/) (for SwiftData macros and `actool`):

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
git clone --recursive <repo-url>
just build   # init submodules + build
just run     # build + launch app
```
