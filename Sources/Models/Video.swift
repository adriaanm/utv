import Foundation
import SwiftData

@StoredModel
final class Video {
    @Unique var videoID: String
    var title: String
    var publishedAt: Date
    var thumbnailURL: String? = nil
    var isShort: Bool = false
    var watchPercentage: Int = 0
    var watchedAt: Date? = nil
    var lastPosition: Double = 0
    var duration: Double = 0
    var channel: Channel? = nil

    init(videoID: String, title: String, publishedAt: Date, thumbnailURL: String? = nil) {
        self.videoID = videoID
        self.title = title
        self.publishedAt = publishedAt
        self.thumbnailURL = thumbnailURL
    }
}
