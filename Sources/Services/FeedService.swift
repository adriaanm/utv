import Foundation
import SwiftData

@MainActor
final class FeedService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Resolve a @handle, add channel + its videos to the database.
    /// Videos come from the `/videos` tab scrape — shorts, livestreams, and
    /// unlisted videos are naturally excluded because YouTube doesn't list them there.
    func addChannel(handle: String) async throws -> Channel {
        let channelID = try await ChannelFeed.resolveChannelID(from: handle)

        // Check if channel already exists
        // #Predicate<Channel> { $0.channelID == channelID }
        let descriptor = FetchDescriptor<Channel>(predicate: Predicate<Channel>({
            PredicateExpressions.build_Equal(
                lhs: PredicateExpressions.build_KeyPath(root: PredicateExpressions.build_Arg($0), keyPath: \.channelID),
                rhs: PredicateExpressions.build_Arg(channelID)
            )
        }))
        if let existing = try modelContext.fetch(descriptor).first {
            try await refreshChannel(existing)
            return existing
        }

        let result = try await ChannelBrowser.fetchFirstPage(channelID: channelID)
        let displayName = result.channelName ?? handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let normalizedHandle = handle.hasPrefix("@") ? handle : "@\(displayName)"
        let channel = Channel(
            channelID: channelID,
            handle: normalizedHandle,
            displayName: displayName
        )
        modelContext.insert(channel)

        upsertBrowseVideos(result.videos, into: channel)
        channel.continuation = result.continuation ?? ""

        try modelContext.save()
        return channel
    }

    /// Refresh a channel: rescrape `/videos` first page, refresh durations, and
    /// delete any DB video within that scrape's time window that isn't in the
    /// scrape result — those are shorts / livestreams / unlisted.
    func refreshChannel(_ channel: Channel) async throws {
        let browseResult = try await ChannelBrowser.fetchFirstPage(channelID: channel.channelID)
        let browseIDs = Set(browseResult.videos.map(\.videoID))

        // Use the oldest video in the scrape as the cleanup boundary. Anything
        // newer than that that /videos doesn't list must be non-standard.
        if let boundary = browseResult.videos.map(\.publishedAt).min() {
            for video in channel.videos
            where video.publishedAt >= boundary && !browseIDs.contains(video.videoID) {
                modelContext.delete(video)
            }
        }

        upsertBrowseVideos(browseResult.videos, into: channel)
        if let name = browseResult.channelName, !name.isEmpty {
            channel.displayName = name
        }
        try modelContext.save()
    }

    /// Refresh all channels concurrently.
    func refreshAll() async {
        let descriptor = FetchDescriptor<Channel>()
        guard let channels = try? modelContext.fetch(descriptor) else { return }

        await withTaskGroup(of: Void.self) { group in
            for channel in channels {
                group.addTask { [weak self] in
                    try? await self?.refreshChannel(channel)
                }
            }
        }
    }

    /// Load more videos for a channel using YouTube's browse API.
    /// First call fetches the /videos tab, subsequent calls use the continuation token.
    func loadMoreVideos(for channel: Channel) async throws {
        let result: ChannelBrowser.BrowseResult

        if let token = channel.continuation, !token.isEmpty {
            result = try await ChannelBrowser.fetchNextPage(continuation: token)
        } else {
            result = try await ChannelBrowser.fetchFirstPage(channelID: channel.channelID)
        }

        upsertBrowseVideos(result.videos, into: channel)
        channel.continuation = result.continuation ?? ""
        try modelContext.save()
    }

    private func upsertBrowseVideos(_ infos: [VideoInfo], into channel: Channel) {
        let existingByID = Dictionary(uniqueKeysWithValues: channel.videos.map { ($0.videoID, $0) })
        for info in infos {
            if let existing = existingByID[info.videoID] {
                // Update duration if not yet known from the player
                if existing.duration == 0 && info.durationSeconds > 0 {
                    existing.duration = info.durationSeconds
                }
            } else {
                let video = Video(
                    videoID: info.videoID,
                    title: info.title,
                    publishedAt: info.publishedAt,
                    thumbnailURL: info.thumbnailURL
                )
                video.duration = info.durationSeconds
                video.channel = channel
                modelContext.insert(video)
            }
        }
    }
}
