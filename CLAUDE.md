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
3. Edit CSS hiding in `Sources/AdBlocker.swift` — add new ad element selectors if needed

Use `just diff-filters` to see what changed upstream in uAssets. Use `just adblock-status` to check current bundle version. Full details in [docs/ubo-tracking.md](docs/ubo-tracking.md).

## Key docs

- [docs/roadmap.md](docs/roadmap.md) — Project roadmap
- [docs/ubo-tracking.md](docs/ubo-tracking.md) — Ad blocking architecture and update workflow

## Repo structure

```
Package.swift           SwiftPM package definition
Sources/                SwiftUI app source
  Macros.swift          Public macro declarations (@StoredModel, @Unique, @Relation)
  Models/               SwiftData models (Channel, Video)
  Services/             FeedService (RSS → SwiftData)
  Resources/            content-rules.json, ubo-scriptlets.js
Macros/UtvMacros/       SwiftPM macro plugin (replaces SwiftData's @Model)
scripts/
  sync-ubo.sh          Update submodules + extract scriptlet bundle
  bundle-app.sh         Assemble .app bundle from swift build output
third_party/            Git submodules (uAssets, uBOL-home, uBlock)
docs/                   Documentation and guides
```

## App architecture

### Views (ContentView.swift)

The UI is a three-column `NavigationSplitView`: sidebar (channel list), content (video list), detail (player).

Three video list views share similar row layouts but are separate structs:

- **`VideoRow`** — used in the per-channel video list (content column). Shows thumbnail, title, relative date, duration, watch progress.
- **`HomeVideoRow`** — used in both `HomeView` (unwatched across all channels) and `HistoryView` (watched, sorted by `watchedAt`). Same layout as `VideoRow` but adds the channel handle.
- **`HistoryView`** — reuses `HomeVideoRow`; no row struct of its own.

When changing how video metadata is displayed, update both `VideoRow` and `HomeVideoRow`.

### Data flow

- **Video discovery**: RSS feeds (`ChannelFeed`) provide video ID, title, date, thumbnail — but no duration.
- **Pagination**: `ChannelBrowser` scrapes YouTube's `/videos` tab (ytInitialData JSON). This data includes duration in the video grid overlay, which is extracted and stored.
- **Duration backfill**: After each feed refresh, `FeedService.backfillDurations()` runs as a background task, fetching the `/videos` page for channels that have videos without durations.
- **Player-reported duration**: When a video is played, `WebPlayerView` reports position and duration via JS message handler. This always overwrites any scraped value, so the player is the source of truth.

### Models (SwiftData)

- **`Channel`** — `channelID`, `handle`, `displayName`, `continuation` (pagination token), `videos` relationship.
- **`Video`** — `videoID`, `title`, `publishedAt`, `thumbnailURL`, `isShort`, `watched`, `watchedAt`, `lastPosition`, `duration`, `channel` relationship.

`Video.duration` starts at 0 and is populated either by `ChannelBrowser` scraping or by the player — whichever happens first.

## Build

Builds with SwiftPM (`swift build`). Requires the Xcode toolchain:

```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Xcode toolchain dependencies

We use `swift build` (not `xcodebuild`), but one thing still requires Xcode.app to be installed:

| Dependency | Used by | Why Xcode | Could be replaced when... |
|---|---|---|---|
| **`actool`** (Asset Catalog compiler) | `scripts/bundle-app.sh` — compiles `Assets.xcassets` into `AppIcon.icns` + `Assets.car` | `actool` is an Xcode developer tool, not available standalone | SwiftPM learns to compile asset catalogs natively ([SE-0loading](https://forums.swift.org/t/asset-catalog-support-in-swiftpm/)), or an open-source `actool` alternative emerges |

SwiftData macros (`@Model`, `@Attribute`, `@Relationship`) have been replaced by custom macros (`@StoredModel`, `@Unique`, `@Relation`) in `Macros/UtvMacros/`, built from source via SwiftPM using swift-syntax. This eliminated the dependency on Xcode's `libSwiftDataMacros.dylib`.

Everything else — compilation, linking, code signing, app bundle assembly — works with just the Swift toolchain and standard macOS tools (`codesign`).

## Just recipes

- `just build` — sync submodules + build debug
- `just run` — build + bundle + launch .app
- `just install` — release build + install to /Applications
- `just sync` — update uBO submodules + copy scriptlet bundle
- `just clean` — remove build artifacts
- `just diff-filters` — show YouTube-relevant upstream filter changes
- `just adblock-status` — show bundle version, rule count, submodule versions
