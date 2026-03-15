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

    var unwatchedCount: Int {
        videos.filter { !$0.watched }.count
    }

    init(channelID: String, handle: String, displayName: String, addedAt: Date = .now) {
        self.channelID = channelID
        self.handle = handle
        self.displayName = displayName
        self.addedAt = addedAt
    }
}
