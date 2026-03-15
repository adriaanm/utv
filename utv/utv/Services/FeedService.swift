import Foundation
import SwiftData

@MainActor
final class FeedService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Resolve a @handle, add channel + its videos to the database.
    func addChannel(handle: String) async throws -> Channel {
        let channelID = try await ChannelFeed.resolveChannelID(from: handle)
        let feedResult = try await ChannelFeed.fetchFeed(channelID: channelID)

        // Check if channel already exists
        let descriptor = FetchDescriptor<Channel>(predicate: #Predicate { $0.channelID == channelID })
        if let existing = try modelContext.fetch(descriptor).first {
            // Refresh instead of duplicating
            try await refreshChannel(existing)
            return existing
        }

        let normalizedHandle = handle.hasPrefix("@") ? handle : "@\(feedResult.channelName)"
        let channel = Channel(
            channelID: channelID,
            handle: normalizedHandle,
            displayName: feedResult.channelName
        )
        modelContext.insert(channel)

        for info in feedResult.videos {
            let video = Video(
                videoID: info.videoID,
                title: info.title,
                publishedAt: info.publishedAt,
                thumbnailURL: info.thumbnailURL
            )
            video.channel = channel
            modelContext.insert(video)
        }

        try modelContext.save()
        return channel
    }

    /// Re-fetch RSS for a channel, insert only new videos.
    func refreshChannel(_ channel: Channel) async throws {
        let feedResult = try await ChannelFeed.fetchFeed(channelID: channel.channelID)

        let existingIDs = Set(channel.videos.map(\.videoID))

        for info in feedResult.videos where !existingIDs.contains(info.videoID) {
            let video = Video(
                videoID: info.videoID,
                title: info.title,
                publishedAt: info.publishedAt,
                thumbnailURL: info.thumbnailURL
            )
            video.channel = channel
            modelContext.insert(video)
        }

        // Update display name in case it changed
        if !feedResult.channelName.isEmpty {
            channel.displayName = feedResult.channelName
        }

        try modelContext.save()
    }

    /// Refresh all channels concurrently.
    func refreshAll() async {
        let descriptor = FetchDescriptor<Channel>()
        guard let channels = try? modelContext.fetch(descriptor) else { return }

        await withTaskGroup(of: Void.self) { group in
            for channel in channels {
                let channelID = channel.channelID
                group.addTask { [weak self] in
                    guard let self else { return }
                    // Fetch feed off main actor context
                    guard let feedResult = try? await ChannelFeed.fetchFeed(channelID: channelID) else { return }
                    await self.upsertVideos(for: channel, from: feedResult)
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

        let existingIDs = Set(channel.videos.map(\.videoID))
        for info in result.videos where !existingIDs.contains(info.videoID) {
            let video = Video(
                videoID: info.videoID,
                title: info.title,
                publishedAt: info.publishedAt,
                thumbnailURL: info.thumbnailURL
            )
            video.channel = channel
            modelContext.insert(video)
        }

        // Store continuation token (nil → "" means no more pages)
        channel.continuation = result.continuation ?? ""
        try modelContext.save()
    }

    private func upsertVideos(for channel: Channel, from feedResult: ChannelFeedResult) {
        let existingIDs = Set(channel.videos.map(\.videoID))

        for info in feedResult.videos where !existingIDs.contains(info.videoID) {
            let video = Video(
                videoID: info.videoID,
                title: info.title,
                publishedAt: info.publishedAt,
                thumbnailURL: info.thumbnailURL
            )
            video.channel = channel
            modelContext.insert(video)
        }

        if !feedResult.channelName.isEmpty {
            channel.displayName = feedResult.channelName
        }

        try? modelContext.save()
    }
}
