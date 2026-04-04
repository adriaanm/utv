# CLAUDE.md — Project Guidelines

## Project

Personal-use macOS YouTube viewer app using WKWebView + content blocking, backed by uBlock Origin filter lists. No login, no YouTube API — all state is local. macOS-only.

## Working principles

- **Commit often.** Small, atomic commits. Don't batch unrelated changes. Commit after each meaningful step, not at the end of a session.
- **Context is limited, the repo is forever.** Anything that might be needed in a future session belongs in the repo, not in conversation memory. Use `docs/` as a journal and work planner — write plans before starting, update as you go.
- **When a task is done, rework its doc into a guide.** Task-tracking docs in `docs/` should evolve from "what we're doing" into "how this works" once complete.
- **Automate repetitive tasks with a justfile.** Add `just` recipes for anything done more than twice (syncing, building, testing, etc.).
- **Track docs and scripts with code.** Documentation and scripts are first-class artifacts — commit them alongside the code they support.

## Non-goals

- **No login / no YouTube account integration.** The app is intentionally separate from any Google account. "Open in Browser" exists for liking/commenting.
- **No YouTube Data API.** RSS feeds are sufficient for video discovery.
- **No automated filter pipeline.** This is personal-use — manual updates when ads break through.

## Ad blocking workflow

Three layers, maintained independently. When ads start appearing:

1. `just sync` — pulls latest uBO scriptlet bundle from upstream (fixes most breakage)
2. Edit `content-rules.json` — add new ad domains/URL patterns if needed
3. Edit CSS hiding in `AdBlocker.swift` — add new ad element selectors if needed

Use `just diff-filters` to see what changed upstream in uAssets. Use `just adblock-status` to check current bundle version. Full details in [docs/ubo-tracking.md](docs/ubo-tracking.md).

## Key docs

- [docs/roadmap.md](docs/roadmap.md) — Project roadmap
- [docs/ubo-tracking.md](docs/ubo-tracking.md) — Ad blocking architecture and update workflow

## Repo structure

```
Package.swift           SwiftPM package definition
utv/utv/                SwiftUI app source
  Models/               SwiftData models (Channel, Video)
  Services/             FeedService (RSS → SwiftData)
  Resources/            content-rules.json, ubo-scriptlets.js
scripts/
  sync-ubo.sh          Update submodules + extract scriptlet bundle
  bundle-app.sh         Assemble .app bundle from swift build output
third_party/            Git submodules (uAssets, uBOL-home, uBlock)
docs/                   Documentation and guides
```

## Build

Builds with SwiftPM (`swift build`). Requires the Xcode toolchain — SwiftData macros are only available in the Xcode-bundled Swift:

```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Just recipes

- `just build` — sync submodules + build debug
- `just run` — build + bundle + launch .app
- `just install` — release build + install to /Applications
- `just sync` — update uBO submodules + copy scriptlet bundle
- `just clean` — remove build artifacts
- `just diff-filters` — show YouTube-relevant upstream filter changes
- `just adblock-status` — show bundle version, rule count, submodule versions
