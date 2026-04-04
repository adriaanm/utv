import Foundation
import SwiftData

@Model
final class Channel {
    @Attribute(.unique) var channelID: String
    var handle: String
    var displayName: String
    var addedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Video.channel)
    var videos: [Video] = []

    /// Continuation token for loading more videos from YouTube browse API.
    /// Nil means we haven't fetched the videos tab yet, empty string means no more pages.
    var continuation: String?

    var unwatchedCount: Int {
        videos.filter { !$0.watched && !$0.isShort }.count
    }

    var hasMoreVideos: Bool {
        continuation != ""
    }

    init(channelID: String, handle: String, displayName: String, addedAt: Date = .now) {
        self.channelID = channelID
        self.handle = handle
        self.displayName = displayName
        self.addedAt = addedAt
    }
}
