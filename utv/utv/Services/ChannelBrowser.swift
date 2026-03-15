import Foundation

/// Fetches videos from a YouTube channel's videos tab with pagination support.
/// Uses YouTube's innertube browse API for continuation pages.
struct ChannelBrowser {

    struct BrowseResult {
        let videos: [VideoInfo]
        let continuation: String?  // nil = no more pages
    }

    /// Fetch the first page of videos from a channel's /videos tab.
    /// Extracts ytInitialData from the HTML and parses the video grid.
    static func fetchFirstPage(channelID: String) async throws -> BrowseResult {
        let url = URL(string: "https://www.youtube.com/channel/\(channelID)/videos")!
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        await ConsentManager.shared.applyToRequest(&request)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw ChannelFeed.FeedError.parseError("Could not decode page")
        }

        // Detect consent wall
        if html.contains("consent.youtube.com") || html.contains("consent.google.com") {
            throw ChannelFeed.FeedError.consentRequired
        }

        // Extract ytInitialData JSON from the page
        guard let jsonData = extractYtInitialData(from: html) else {
            throw ChannelFeed.FeedError.parseError("Could not find ytInitialData")
        }

        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ChannelFeed.FeedError.parseError("ytInitialData is not a dictionary")
        }

        return parseVideoTab(from: root)
    }

    /// Fetch the next page of videos using a continuation token.
    static func fetchNextPage(continuation: String) async throws -> BrowseResult {
        let url = URL(string: "https://www.youtube.com/youtubei/v1/browse")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20250101.00.00"
                ]
            ],
            "continuation": continuation
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChannelFeed.FeedError.parseError("Browse response is not a dictionary")
        }

        return parseContinuationResponse(from: root)
    }

    // MARK: - Private

    private static func extractYtInitialData(from html: String) -> Data? {
        // Pattern: var ytInitialData = {...};
        guard let startRange = html.range(of: "var ytInitialData = ") else { return nil }
        let jsonStart = startRange.upperBound
        let remaining = html[jsonStart...]

        // Find the matching closing brace by tracking depth
        var depth = 0
        var endIndex = remaining.startIndex
        for i in remaining.indices {
            let c = remaining[i]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 {
                    endIndex = remaining.index(after: i)
                    break
                }
            }
        }

        guard depth == 0 else { return nil }
        let jsonString = remaining[remaining.startIndex..<endIndex]
        return jsonString.data(using: .utf8)
    }

    /// Navigate the ytInitialData structure to find the videos tab content.
    private static func parseVideoTab(from root: [String: Any]) -> BrowseResult {
        // Path: contents.twoColumnBrowseResultsRenderer.tabs[].tabRenderer
        //   where tab.title == "Videos"
        //   → tab.content.richGridRenderer.contents[]
        guard let contents = root["contents"] as? [String: Any],
              let twoCol = contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = twoCol["tabs"] as? [[String: Any]] else {
            return BrowseResult(videos: [], continuation: nil)
        }

        for tab in tabs {
            guard let tabRenderer = tab["tabRenderer"] as? [String: Any],
                  let title = tabRenderer["title"] as? String,
                  title == "Videos",
                  let content = tabRenderer["content"] as? [String: Any],
                  let richGrid = content["richGridRenderer"] as? [String: Any],
                  let gridContents = richGrid["contents"] as? [[String: Any]] else {
                continue
            }

            return parseGridContents(gridContents)
        }

        return BrowseResult(videos: [], continuation: nil)
    }

    /// Parse a continuation/browse response.
    private static func parseContinuationResponse(from root: [String: Any]) -> BrowseResult {
        // Path: onResponseReceivedActions[].appendContinuationItemsAction.continuationItems[]
        guard let actions = root["onResponseReceivedActions"] as? [[String: Any]] else {
            return BrowseResult(videos: [], continuation: nil)
        }

        for action in actions {
            if let append = action["appendContinuationItemsAction"] as? [String: Any],
               let items = append["continuationItems"] as? [[String: Any]] {
                return parseGridContents(items)
            }
        }

        return BrowseResult(videos: [], continuation: nil)
    }

    /// Parse grid contents (shared between initial and continuation responses).
    private static func parseGridContents(_ items: [[String: Any]]) -> BrowseResult {
        var videos: [VideoInfo] = []
        var nextContinuation: String?

        for item in items {
            // Video item
            if let richItem = item["richItemRenderer"] as? [String: Any],
               let content = richItem["content"] as? [String: Any],
               let videoRenderer = content["videoRenderer"] as? [String: Any],
               let video = parseVideoRenderer(videoRenderer) {
                videos.append(video)
            }

            // Continuation token
            if let contItem = item["continuationItemRenderer"] as? [String: Any],
               let endpoint = contItem["continuationEndpoint"] as? [String: Any],
               let contCommand = endpoint["continuationCommand"] as? [String: Any],
               let token = contCommand["token"] as? String {
                nextContinuation = token
            }
        }

        return BrowseResult(videos: videos, continuation: nextContinuation)
    }

    /// Parse a single videoRenderer into VideoInfo.
    private static func parseVideoRenderer(_ renderer: [String: Any]) -> VideoInfo? {
        guard let videoID = renderer["videoId"] as? String else { return nil }

        let title: String
        if let titleObj = renderer["title"] as? [String: Any],
           let runs = titleObj["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            title = text
        } else {
            title = "Untitled"
        }

        // Published time — YouTube gives relative strings like "2 days ago"
        // We'll use a rough parser; for sorting we have the order from YouTube
        let publishedAt: Date
        if let pubText = renderer["publishedTimeText"] as? [String: Any],
           let simpleText = pubText["simpleText"] as? String {
            publishedAt = parseRelativeDate(simpleText)
        } else {
            publishedAt = .now
        }

        // Thumbnail
        let thumbnailURL: String?
        if let thumbObj = renderer["thumbnail"] as? [String: Any],
           let thumbnails = thumbObj["thumbnails"] as? [[String: Any]],
           let best = thumbnails.last,
           let url = best["url"] as? String {
            thumbnailURL = url
        } else {
            thumbnailURL = nil
        }

        return VideoInfo(videoID: videoID, title: title, publishedAt: publishedAt, thumbnailURL: thumbnailURL)
    }

    /// Parse YouTube's relative date strings like "2 days ago", "3 weeks ago".
    private static func parseRelativeDate(_ text: String) -> Date {
        let lower = text.lowercased()
        let components = lower.split(separator: " ")
        guard components.count >= 2, let n = Int(components[0]) else { return .now }

        let unit = String(components[1])
        let seconds: TimeInterval
        if unit.hasPrefix("second") { seconds = TimeInterval(n) }
        else if unit.hasPrefix("minute") { seconds = TimeInterval(n * 60) }
        else if unit.hasPrefix("hour") { seconds = TimeInterval(n * 3600) }
        else if unit.hasPrefix("day") { seconds = TimeInterval(n * 86400) }
        else if unit.hasPrefix("week") { seconds = TimeInterval(n * 604800) }
        else if unit.hasPrefix("month") { seconds = TimeInterval(n * 2592000) }
        else if unit.hasPrefix("year") { seconds = TimeInterval(n * 31536000) }
        else { return .now }

        return Date(timeIntervalSinceNow: -seconds)
    }
}
