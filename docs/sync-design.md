# Mac ↔ Apple TV Sync

Status: **design.** Not implemented yet — sketch for review before coding.

## Goals

1. Mac is the source of truth for **channel subscriptions**. Adding a channel on the Mac should make it appear on the Apple TV without retyping.
2. Watch progress (`watchPercentage`, `lastPosition`, `watchedAt`) should be **bidirectional**: a video watched on the TV shows as watched on the Mac, and vice versa, with a basic conflict-resolution rule.
3. Driven by an explicit user action — a menu item on the Mac (`Sync with Apple TV…`). No background sync, no daemon.
4. No cloud, no account. Direct LAN peer-to-peer.

## Non-goals

- iOS / iPad sync (later, if at all).
- Backfilling video metadata across devices — each device runs its own `/videos`-tab scrape. Sync only moves user state (subscriptions + progress), not the cached YouTube grid.
- Offline / "while you were away" sync. Both devices must be powered on and on the same network when the user invokes sync.
- Encryption beyond what the transport gives us. This is a personal-use app on a home network.

## Transport: MultipeerConnectivity

`MultipeerConnectivity` is built into both macOS 14 and tvOS 17, no third-party dependencies, handles Bonjour discovery and an encrypted session for free.

- **tvOS app** advertises an `MCNearbyServiceAdvertiser` with service type `utv-sync` while the app is running. Auto-accepts invitations from peers (this is a personal-use app on a trusted LAN).
- **Mac app** menu item `Sync with Apple TV…` starts an `MCNearbyServiceBrowser`, picks the first discovered peer (or a single-pick UI if multiple), invites, and on connection runs the exchange below.

If MultipeerConnectivity proves flaky on tvOS (it's known to be finicky), fall back to a 30-line HTTP server in the tvOS app and Bonjour-only discovery from the Mac.

## Protocol

Both sides exchange a single JSON `SyncBundle`. There's no incremental sync — the bundles are small enough to send in full each time.

```jsonc
// SyncBundle
{
  "schemaVersion": 1,
  "exportedAt": "2026-04-25T17:30:00Z",
  "channels": [
    { "channelID": "UCxxx", "handle": "@handle", "displayName": "Display", "addedAt": "..." }
  ],
  "videos": [
    {
      "videoID": "abc123",
      "channelID": "UCxxx",
      "watchPercentage": 87,
      "watchedAt": "2026-04-25T16:55:12Z",
      "lastPosition": 612.4,
      "duration": 703.0
    }
  ]
}
```

`videos` carries **only watch state**, not title/thumbnail/publishedAt. Each device's own `/videos` scrape populates that. If the receiver has never seen a `videoID`, it skips the entry — there's no point creating a bare Video record on the TV for something it hasn't browsed yet. (Caveat: the TV's first sync after install will receive a lot of skips; once the TV has done its own scrapes, subsequent syncs will land progress updates.)

### Exchange

1. Mac connects, sends `SyncBundle` with its full channel list + every video that has `watchPercentage > 0` (or any non-default progress).
2. tvOS receives, applies the merge below, then replies with its own `SyncBundle` (subset: channels are read-only on TV, so just videos with progress).
3. Mac receives, applies merge.
4. Both sides disconnect.

### Merge rules

**Channels (Mac → TV one-way for now):**
- Insert TV-side any channel from the bundle whose `channelID` doesn't exist on the TV.
- Update `handle` / `displayName` if changed.
- **Delete** TV-side any channel not in the bundle (Mac is canonical).
- The TV → Mac reply does not include channels.

**Videos (bidirectional, last-write-wins on a per-field basis):**

Per `videoID` present on both sides:
- `watchPercentage`: take the **higher** value. (More-watched wins; protects against a stale "I started but didn't finish" overwriting a "I watched it through".)
- `watchedAt`: take the **later** non-nil value.
- `lastPosition`: take the value from whichever side had the higher `watchPercentage`. (Position only makes sense in the context of the same playback session.)
- `duration`: take the player-measured value if either has one (>0); otherwise leave as-is.

If the receiver has no record of the `videoID`, skip — see note above.

This is "last-write-wins per field, biased toward more-watched." It handles the common cases:
- Watched something on TV → Mac shows it as watched.
- Started on Mac, finished on TV → Mac picks up the higher percentage on next sync.
- Stale Mac record (watched 30%) vs fresh TV record (watched 90%) — TV wins because higher percentage.

It does **not** handle: deliberate "un-watch" (resetting `watchPercentage` to 0). That'd require tombstones. Punt for now — manual fix on both devices is fine for personal use.

## UI

- **Mac**: a `Sync` menu item under a new top-level `Device` menu (or under `File`, TBD). On click, opens a small sheet showing discovery progress, peer name, exchange status, and a final summary ("Pushed 12 channels, received 4 watch updates"). Dismisses on done.
- **tvOS**: no UI. The advertiser runs whenever the app is foregrounded. A subtle indicator in the corner (small dot) when a sync is in progress is nice-to-have; not in v1.

## Implementation outline

```
Sources/utvCore/
  Services/
    SyncProtocol.swift     # SyncBundle codable types, schema version
    SyncMerger.swift       # pure functions: merge(local: SyncBundle, remote: SyncBundle, into: ModelContext)
  Sync/
    SyncTransport.swift    # MCSession wrapper, send/recv SyncBundle, peer discovery
    SyncCoordinator.swift  # orchestrates the exchange; one method `runSync(role: .initiator|.responder)`

Sources/utvCore/
  AppRoot.swift            # tvOS-side: start advertiser on appear, stop on disappear
  ContentView.swift (macOS body):
                           # add Sync menu item -> opens SyncSheet -> SyncCoordinator(role: .initiator)
```

`SyncMerger` is the testable core (pure SwiftData operations on a passed `ModelContext`). Transport + coordinator are platform-conditioned thinly: `import MultipeerConnectivity` works on both macOS and tvOS, but `MCNearbyServiceAdvertiser` is what tvOS uses and `MCNearbyServiceBrowser` is what Mac uses.

Bundles are JSON via `JSONEncoder/Decoder`. No protobuf, no Codable wizardry needed.

## Open questions

1. **Multiple TVs** — does anyone have more than one Apple TV running utv? If yes, the Mac menu becomes "Sync with… → [list]". If no, auto-pick the only peer. Defer until it matters.
2. **What about videos seen only on the TV?** They get scraped on TV. Mac never learns about them through sync (only progress on existing records flows). That's fine — Mac will scrape them next refresh.
3. **Schema migrations across versions** — `schemaVersion: 1` for now. If the schema changes, refuse to sync with mismatching versions until both sides updated.
4. **Authentication** — none. Personal-use, home LAN. If we ever ship publicly, MCSession peers can be required to share a PSK (`MCEncryptionRequired` is already on by default).

## What gets committed first

To stay incremental:

1. `Sources/utvCore/Services/SyncProtocol.swift` — `SyncBundle` types + `SyncMerger.merge` pure function. With unit-style asserts in a small `#if DEBUG` self-test (we don't have XCTest infra yet — see roadmap).
2. `Sources/utvCore/Sync/SyncTransport.swift` + `SyncCoordinator.swift` — MultipeerConnectivity wiring, platform-conditioned init.
3. tvOS `AppRoot` hook to start the advertiser.
4. Mac `Device > Sync with Apple TV…` menu item + sheet.

Each step is independently testable: (1) is pure logic, (2) is "two devices on a network can connect and exchange bytes" without merging, (3) is "TV is discoverable from Mac", (4) is end-to-end.
