import Foundation
import SwiftData

// Wire format exchanged between Mac and Apple TV. See docs/sync-design.md.
public struct SyncBundle: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var exportedAt: Date
    // nil when sender is not the canonical channel source (i.e. tvOS).
    // Non-nil (even if empty) signals the receiver to treat it as canonical:
    // missing channelIDs get deleted on the receiver.
    public var channels: [ChannelEntry]?
    public var videos: [VideoEntry]
    // YouTube SOCS consent cookie. Mac includes it so tvOS can skip the
    // consent-banner click-through (awkward via the Siri Remote). nil from tvOS.
    public var consentCookie: String?

    public struct ChannelEntry: Codable, Sendable {
        public var channelID: String
        public var handle: String
        public var displayName: String
        public var addedAt: Date
    }

    public struct VideoEntry: Codable, Sendable {
        public var videoID: String
        public var channelID: String
        public var watchPercentage: Int
        public var watchedAt: Date?
        public var lastPosition: Double
        public var duration: Double
    }
}

public enum SyncMerger {

    // Build a bundle to send. `includeChannels` is true on Mac (canonical source)
    // and false on tvOS (read-only for channels).
    @MainActor
    public static func exportBundle(
        from context: ModelContext,
        includeChannels: Bool,
        consentCookie: String? = nil
    ) throws -> SyncBundle {
        let channels: [SyncBundle.ChannelEntry]?
        if includeChannels {
            let all = try context.fetch(FetchDescriptor<Channel>())
            channels = all.map {
                SyncBundle.ChannelEntry(
                    channelID: $0.channelID,
                    handle: $0.handle,
                    displayName: $0.displayName,
                    addedAt: $0.addedAt
                )
            }
        } else {
            channels = nil
        }

        // Only include videos with non-default progress; the rest is noise.
        let allVideos = try context.fetch(FetchDescriptor<Video>())
        let videos = allVideos.compactMap { v -> SyncBundle.VideoEntry? in
            guard hasProgress(v), let chID = v.channel?.channelID else { return nil }
            return SyncBundle.VideoEntry(
                videoID: v.videoID,
                channelID: chID,
                watchPercentage: v.watchPercentage,
                watchedAt: v.watchedAt,
                lastPosition: v.lastPosition,
                duration: v.duration
            )
        }

        return SyncBundle(
            schemaVersion: SyncBundle.currentSchemaVersion,
            exportedAt: .now,
            channels: channels,
            videos: videos,
            consentCookie: consentCookie
        )
    }

    public struct MergeStats: Sendable {
        public var channelsInserted = 0
        public var channelsUpdated = 0
        public var channelsDeleted = 0
        public var videosUpdated = 0
        public var videosSkipped = 0
        // Set when the bundle carried a SOCS cookie and the receiver had none.
        // The caller is responsible for injecting it via ConsentManager.
        public var consentCookieReceived: String?
    }

    // Apply a received bundle into the local store. See merge rules in docs/sync-design.md.
    @MainActor
    @discardableResult
    public static func apply(
        _ bundle: SyncBundle,
        into context: ModelContext,
        currentConsentCookie: String? = nil
    ) throws -> MergeStats {
        var stats = MergeStats()

        if let remoteChannels = bundle.channels {
            stats = try mergeChannels(remoteChannels, into: context, stats: stats)
        }
        stats = try mergeVideos(bundle.videos, into: context, stats: stats)

        if let remoteCookie = bundle.consentCookie, currentConsentCookie == nil {
            stats.consentCookieReceived = remoteCookie
        }

        try context.save()
        return stats
    }

    @MainActor
    private static func mergeChannels(
        _ remote: [SyncBundle.ChannelEntry],
        into context: ModelContext,
        stats inputStats: MergeStats
    ) throws -> MergeStats {
        var stats = inputStats
        let local = try context.fetch(FetchDescriptor<Channel>())
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.channelID, $0) })
        let remoteIDs = Set(remote.map(\.channelID))

        for entry in remote {
            if let existing = localByID[entry.channelID] {
                var changed = false
                if existing.handle != entry.handle { existing.handle = entry.handle; changed = true }
                if existing.displayName != entry.displayName { existing.displayName = entry.displayName; changed = true }
                if changed { stats.channelsUpdated += 1 }
            } else {
                let ch = Channel(
                    channelID: entry.channelID,
                    handle: entry.handle,
                    displayName: entry.displayName,
                    addedAt: entry.addedAt
                )
                context.insert(ch)
                stats.channelsInserted += 1
            }
        }

        for ch in local where !remoteIDs.contains(ch.channelID) {
            context.delete(ch)
            stats.channelsDeleted += 1
        }
        return stats
    }

    @MainActor
    private static func mergeVideos(
        _ remote: [SyncBundle.VideoEntry],
        into context: ModelContext,
        stats inputStats: MergeStats
    ) throws -> MergeStats {
        var stats = inputStats
        for entry in remote {
            let videoID = entry.videoID
            let descriptor = FetchDescriptor<Video>(predicate: Predicate<Video>({
                PredicateExpressions.build_Equal(
                    lhs: PredicateExpressions.build_KeyPath(
                        root: PredicateExpressions.build_Arg($0),
                        keyPath: \.videoID
                    ),
                    rhs: PredicateExpressions.build_Arg(videoID)
                )
            }))
            guard let local = try context.fetch(descriptor).first else {
                stats.videosSkipped += 1
                continue
            }
            if applyVideoMerge(remote: entry, into: local) {
                stats.videosUpdated += 1
            }
        }
        return stats
    }

    // Per-field merge. Returns true if the local record changed.
    @discardableResult
    static func applyVideoMerge(remote: SyncBundle.VideoEntry, into local: Video) -> Bool {
        var changed = false

        // watchPercentage: take the higher value.
        let remoteWonOnPercent = remote.watchPercentage > local.watchPercentage
        if remoteWonOnPercent {
            local.watchPercentage = remote.watchPercentage
            changed = true
        }

        // watchedAt: take the later non-nil value.
        switch (local.watchedAt, remote.watchedAt) {
        case (nil, let r?):
            local.watchedAt = r; changed = true
        case (let l?, let r?) where r > l:
            local.watchedAt = r; changed = true
        default:
            break
        }

        // lastPosition: take the value from whichever side had higher watchPercentage.
        if remoteWonOnPercent {
            if local.lastPosition != remote.lastPosition {
                local.lastPosition = remote.lastPosition
                changed = true
            }
        }

        // duration: prefer any non-zero value. If both non-zero, keep local.
        if local.duration == 0 && remote.duration > 0 {
            local.duration = remote.duration
            changed = true
        }

        return changed
    }

    private static func hasProgress(_ v: Video) -> Bool {
        v.watchPercentage > 0 || v.lastPosition > 0 || v.watchedAt != nil
    }
}

public enum SyncProtocolError: Error, CustomStringConvertible, Sendable {
    case schemaMismatch(local: Int, remote: Int)
    case decodingFailed(String)
    case timeout
    case noPeerFound
    case transport(String)

    public var description: String {
        switch self {
        case let .schemaMismatch(l, r): "Sync schema mismatch (local v\(l), remote v\(r))."
        case let .decodingFailed(msg): "Could not decode sync bundle: \(msg)"
        case .timeout: "Sync timed out."
        case .noPeerFound: "No sync peer found on the network."
        case let .transport(msg): "Transport error: \(msg)"
        }
    }
}

// JSON encoder/decoder shared by transport + tests.
public enum SyncCoding {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
