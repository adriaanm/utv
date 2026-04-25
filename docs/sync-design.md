# Mac ↔ Apple TV Sync

Status: **implemented (v1).** Both directions wired through MultipeerConnectivity. tvOS pulls from the Mac on launch; the Mac can also push on demand via `Device → Sync with Apple TV…`. The bundle additionally carries the YouTube SOCS consent cookie so the tvOS app skips the consent banner click-through.

## Goals

1. Mac is the source of truth for **channel subscriptions**. Adding a channel on the Mac should make it appear on the Apple TV without retyping.
2. Watch progress (`watchPercentage`, `lastPosition`, `watchedAt`) should be **bidirectional**: a video watched on the TV shows as watched on the Mac, and vice versa, with a basic conflict-resolution rule.
3. Two trigger points:
   - **tvOS startup pull (automatic).** Every cold start, the tvOS app browses for the Mac and pulls. The Mac is assumed to be running; if it isn't, the discovery times out silently and the TV continues with whatever local state it has.
   - **Mac-initiated push (manual).** A menu item (`Device → Sync with Apple TV…`) on the Mac browses for the TV and exchanges. Used after adding/removing channels on the Mac when you want the TV to catch up immediately.
4. No cloud, no account. Direct LAN peer-to-peer.

## Non-goals

- iOS / iPad sync (later, if at all).
- Backfilling video metadata across devices — each device runs its own `/videos`-tab scrape. Sync only moves user state (subscriptions + progress), not the cached YouTube grid.
- Offline / "while you were away" sync. Both devices must be powered on and on the same network when the user invokes sync.
- Encryption beyond what the transport gives us. This is a personal-use app on a home network.

## Transport: MultipeerConnectivity

`MultipeerConnectivity` is built into both macOS 14 and tvOS 17, no third-party dependencies, handles Bonjour discovery and an encrypted session for free.

Both apps advertise an `MCNearbyServiceAdvertiser` with service type `utv-sync` while running, and auto-accept any invitation (trusted personal LAN). Either side can additionally spin up an `MCNearbyServiceBrowser` to drive an exchange:

- **tvOS** starts a browser on launch (in `AppRoot`'s `.task`) — this is the startup pull.
- **macOS** starts a browser when the user picks the menu item.

Required Info.plist keys: `NSLocalNetworkUsageDescription` and `NSBonjourServices` listing `_utv-sync._tcp` / `_utv-sync._udp`. macOS sandbox additionally needs both `network.client` and `network.server` entitlements.

If MultipeerConnectivity proves flaky on tvOS (it's known to be finicky), fall back to a 30-line HTTP server in the tvOS app and Bonjour-only discovery from the Mac.

## Protocol

Both sides exchange a single JSON `SyncBundle`. There's no incremental sync — the bundles are small enough to send in full each time.

```jsonc
// SyncBundle
{
  "schemaVersion": 1,
  "exportedAt": "2026-04-25T17:30:00Z",
  // null when the sender is not the canonical channel source (i.e. tvOS).
  // Non-null (even if []) tells the receiver to treat the list as canonical
  // and delete any local channelID that's missing.
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
  ],
  // Mac-only. The receiver applies it iff it currently has no SOCS cookie.
  // Saves a tedious banner click-through on the tvOS Siri Remote.
  "consentCookie": "CAISNQgD..."
}
```

`videos` carries **only watch state**, not title/thumbnail/publishedAt. Each device's own `/videos` scrape populates that. If the receiver has never seen a `videoID`, it skips the entry — there's no point creating a bare Video record on the TV for something it hasn't browsed yet. (Caveat: the TV's first sync after install will receive a lot of skips; once the TV has done its own scrapes, subsequent syncs will land progress updates.)

### Exchange

The exchange is symmetric: whoever initiates sends first, the responder applies + replies, both disconnect. The semantics of *what* each side sends are role-asymmetric: the Mac always includes channels + consent cookie (canonical); the tvOS bundle carries only videos with progress.

**Mac-initiated push** (menu):
1. Mac (initiator) sends bundle with channels + videos + cookie.
2. tvOS (responder) applies, replies with videos-only bundle.
3. Mac applies, both disconnect.

**TV-initiated startup pull** (automatic on launch):
1. tvOS (initiator) sends bundle with videos only.
2. Mac (responder) applies the videos, replies with channels + videos + cookie.
3. tvOS applies, both disconnect.

### Merge rules

**Channels (Mac → TV one-way for now):**
- Insert TV-side any channel from the bundle whose `channelID` doesn't exist on the TV.
- Update `handle` / `displayName` if changed.
- **Delete** TV-side any channel not in the bundle (Mac is canonical).
- The TV → Mac reply omits channels (`null`), so the Mac applies videos-only and never deletes its own channel rows.

**Consent cookie (Mac → TV):**
- If the bundle carries `consentCookie` and the receiver has no SOCS cookie stored, persist it via `ConsentManager` and inject it into the WKWebView cookie store. If the receiver already has a cookie, the field is ignored — we don't trample what the user already accepted on this device.

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

- **Mac**: `Device → Sync with Apple TV…` (⌘⇧S). On click, opens a small sheet showing discovery progress and a final summary ("Pushed N channel changes, received M watch updates"). Dismisses on done. The advertiser runs in the background regardless, so the TV's startup pull also works without the user ever opening the menu.
- **tvOS**: no UI. The advertiser runs whenever the app is foregrounded; the startup pull fires from `AppRoot`'s `.task` once per cold start. A subtle on-screen indicator while syncing is nice-to-have; not in v1.

## Implementation outline

```
Sources/utvCore/
  Services/
    SyncProtocol.swift     # SyncBundle codable types + SyncMerger pure functions + JSON coding
  Sync/
    SyncTransport.swift    # SyncAdvertiser (responder) + SyncBrowser (initiator) over MultipeerConnectivity
    SyncCoordinator.swift  # @MainActor singleton: bootstrap from AppRoot, runs both roles
  AppRoot.swift            # constructs the SwiftData container, bootstraps SyncCoordinator,
                           # adds Device menu on macOS, fires startup pull on tvOS
  ContentView.swift        # SyncSheet — driven by NotificationCenter from the menu item
```

`SyncMerger` is the testable core (pure SwiftData operations on a passed `ModelContext`). `SyncCoordinator` glues the merger to the transport and is platform-conditioned thinly: it always advertises, and exposes `runMacInitiatedSync()` / `runTVStartupPull()` for the two browser roles. Both run through the same `runInitiator(timeout:)` body — what differs is which side's bundle carries channels + cookie (driven by `isCanonicalSource = #if os(macOS)`).

Bundles are JSON via `JSONEncoder/Decoder` with ISO-8601 dates. No protobuf, no Codable wizardry needed.

## Open questions

1. **Multiple TVs** — does anyone have more than one Apple TV running utv? If yes, the Mac menu becomes "Sync with… → [list]". If no, auto-pick the only peer. Defer until it matters.
2. **What about videos seen only on the TV?** They get scraped on TV. Mac never learns about them through sync (only progress on existing records flows). That's fine — Mac will scrape them next refresh.
3. **Schema migrations across versions** — `schemaVersion: 1` for now. If the schema changes, refuse to sync with mismatching versions until both sides updated.
4. **Authentication** — none. Personal-use, home LAN. If we ever ship publicly, MCSession peers can be required to share a PSK (`MCEncryptionRequired` is already on by default).

## Troubleshooting

If both sides report a connectivity error despite being on the same LAN:

1. **Stale Mac install.** Check `codesign -d --entitlements - /Applications/utv.app` and `plutil -p /Applications/utv.app/Contents/Info.plist`. The bundle must contain both `com.apple.security.network.server` (entitlements) and `NSLocalNetworkUsageDescription` + `NSBonjourServices` listing `_utv-sync._tcp` / `_utv-sync._udp` (Info.plist). Bundles built before the sync work landed have neither — `just install` regenerates both.
2. **macOS local-network permission.** First launch after install pops a dialog ("utv would like to find devices on your local network"). If it never appeared, or you clicked Don't Allow, toggle **System Settings → Privacy & Security → Local Network → utv** on. Without this, `MCNearbyServiceAdvertiser` silently fails — `[Sync] Advertiser failed to start: …` lands in Console.app.
3. **tvOS local-network permission.** Same prompt on the device the first time. Accept it. If the prompt was missed, **Settings → Apps → utv** on the Apple TV exposes the toggle.
4. **AP isolation.** Some routers block mDNS between Wi-Fi clients (especially across 2.4 / 5 / 6 GHz radios or "guest" SSIDs). Verify both devices are on the same SSID and that client-isolation is off.
5. **Symptoms.** When the Mac isn't advertising, the TV's `runTVStartupPull` times out with `SyncProtocolError.timeout` — that's the "connectivity error" the TV surfaces. Always check the Mac side first; the TV side is mostly downstream noise from a missing advertiser.

## Validation status

- `swift build` (macOS) passes.
- tvOS compilation requires the tvOS SDK (Xcode.app). Not validated in CI here; verify with `just build-tv` before sideloading.
- Hardware end-to-end (Mac + paired Apple TV) — TBD on first real run.

## Follow-ups

- `#if DEBUG` self-test for `SyncMerger.applyVideoMerge` (per-field merge rules) — pure logic, no XCTest needed.
- On-screen sync indicator on tvOS during exchanges.
- Multi-TV picker if anyone ever runs more than one. (Currently auto-picks the first peer found.)
