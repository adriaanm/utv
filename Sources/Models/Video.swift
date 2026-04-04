import Foundation
import SwiftData

@Model
final class Video {
    @Attribute(.unique) var videoID: String
    var title: String
    var publishedAt: Date
    var thumbnailURL: String?
    var isShort: Bool = false
    var watched: Bool = false
    var watchedAt: Date?
    var lastPosition: Double = 0
    var duration: Double = 0
    var channel: Channel?

    init(videoID: String, title: String, publishedAt: Date, thumbnailURL: String? = nil) {
        self.videoID = videoID
        self.title = title
        self.publishedAt = publishedAt
        self.thumbnailURL = thumbnailURL
    }
}
