# utv

A simple YouTube browser for macOS and iOS. Like an old-school TV: pick a channel, watch a video. No ads.

No login, no Google account, no YouTube API. All state is local. You can't like, comment, or subscribe — use "Open in Browser" for that.

Ad blocking is powered by [uBlock Origin](https://github.com/gorhill/uBlock) filter lists, compiled into WebKit content blockers.

If you enjoy a creator's work, support them directly — merch, Patreon, or whatever they offer.

Built with [Claude Code](https://claude.ai/claude-code).

## Setup

```sh
git clone --recursive <repo-url>
just sync    # pull latest uBO filter lists
just generate # generate Xcode project
just build   # build macOS app
```
