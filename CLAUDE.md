# CLAUDE.md — Project Guidelines

## Project

Personal-use macOS YouTube viewer app using WKWebView + content blocking, backed by uBlock Origin filter lists. No login, no YouTube API — all state is local. macOS-only.

## Working principles

- **Commit each logical change separately.** One commit per behavior change — don't batch unrelated changes. If a session produces a bug fix and a new feature, that's two commits. Commit after each meaningful step, not at the end of a session.
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
- [docs/sync-design.md](docs/sync-design.md) — Mac ↔ Apple TV sync (MultipeerConnectivity; channels + watch progress + SOCS cookie)

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

**`VideoListView`** is the shared video list used by both the per-channel view and `HomeView`. It takes a `videos` array, an `allVideos` superset (for "Mark Older as Watched"), an optional `channel` (enables load-more pagination), and a `showChannel` flag. **`VideoRow`** renders each video; when `showChannel` is true it includes the channel handle. `HomeView` is a thin wrapper that owns the `@StoredQuery` and watch-status filter (Unwatched / Started / Watched), passing filtered results into `VideoListView`.

### Data flow

The `/videos` tab scrape is the source of truth for Video records. Anything that appears in the DB's time window for a channel but isn't in the `/videos` scrape is treated as a short / livestream / unlisted and deleted.

- **Refresh**: `FeedService.refreshChannel` rescrapes the channel's `/videos` first page. It takes the oldest `publishedAt` in that scrape as a cleanup boundary — any DB video newer than the boundary whose ID isn't in the browse result gets deleted. Then it upserts the browse result (filling durations for anything still at 0). Runs every time a refresh happens; there's no "skip if nothing new" optimization. RSS plays no role in refresh.
- **Browse scrape**: `ChannelBrowser` parses YouTube's `/videos` tab (ytInitialData JSON) for both initial channel add and pagination. It yields video IDs, titles, relative dates, thumbnails, and durations from the grid overlay. The channel's display name also comes from this scrape (`metadata.channelMetadataRenderer.title`).
- **Shorts / livestreams / unlisted**: naturally excluded because YouTube's `/videos` tab omits them. No client-side detection needed — if it's not in the browse result, it doesn't become a Video record (and refresh will delete any that previously did).
- **Player-reported duration**: When a video is played, `WebPlayerView` reports position and duration via JS message handler. This always overwrites any scraped value, so the player is the source of truth once a video has been played. `upsertBrowseVideos` only fills duration when the stored value is 0, so player precision is preserved across refreshes.

### Models (SwiftData)

- **`Channel`** — `channelID`, `handle`, `displayName`, `continuation` (pagination token), `videos` relationship.
- **`Video`** — `videoID`, `title`, `publishedAt`, `thumbnailURL`, `watchPercentage` (0–100), `watchedAt`, `lastPosition`, `duration`, `channel` relationship.

`Video.watchPercentage` is updated from the player's JS position reports (currentTime/duration). Clicking play does not mark a video as watched — only actual playback progress changes the percentage. Videos with ≥90% are considered "watched", >0% but <90% are "started".

`Video.duration` is populated from `ChannelBrowser`'s grid scrape at insert time. Live stream VODs whose duration isn't yet known come in at 0 and are filled on a later refresh. The player overwrites whatever is stored when the video plays.

The SwiftData store lives at `~/Library/Containers/com.utv.app/Data/Library/Application Support/default.store` (SQLite).

## Build

Builds with SwiftPM (`swift build`). Requires a full Xcode.app install (Command Line Tools alone are no longer sufficient — see below):

```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Xcode.app dependencies

Xcode.app is required for the **iOS SDK WebKit headers**, which the tvOS bridge vendors via `just sync-webkit-headers`. tvOS itself ships no public WebKit headers; we copy the iOS SDK's headers (same WebKit binary surface) and link with `-undefined dynamic_lookup`. See [docs/tvos-port.md](docs/tvos-port.md).

For the macOS build alone, the dependency is lighter:

- **SwiftData macros** — replaced by custom macros (`@StoredModel`, `@Unique`, `@Relation`) in `Macros/UtvMacros/`, built from source via SwiftPM with swift-syntax.
- **`actool`** — replaced by `iconutil` (ships with Command Line Tools). The app icon lives in `AppIcon.iconset/` and is compiled to `.icns` by `bundle-app.sh`.

So macOS-only compilation, linking, code signing, and bundling work with just the Swift toolchain, `iconutil`, and `codesign` — but the tvOS port pulls Xcode.app back in as a hard dependency, and the project no longer aims to keep CLT-only viable.

## Just recipes

- `just build` — sync submodules + build debug
- `just run` — build + bundle + launch .app
- `just install` — release build + install to /Applications
- `just sync` — update uBO submodules + copy scriptlet bundle
- `just clean` — remove build artifacts
- `just diff-filters` — show YouTube-relevant upstream filter changes
- `just adblock-status` — show bundle version, rule count, submodule versions
