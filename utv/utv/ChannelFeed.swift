import Foundation

struct ChannelFeed {
    enum FeedError: LocalizedError {
        case invalidURL
        case noVideoFound
        case networkError(Error)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .noVideoFound: return "No video found in feed"
            case .networkError(let e): return "Network error: \(e.localizedDescription)"
            case .parseError(let msg): return "Parse error: \(msg)"
            }
        }
    }

    /// Resolve input (channel ID, @handle, or full URL) to a channel ID.
    static func resolveChannelID(from input: String) async throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Already a channel ID (starts with UC and is 24 chars)
        if trimmed.hasPrefix("UC") && trimmed.count == 24 {
            return trimmed
        }

        // Handle @handle or full URL — fetch the page and extract channel ID
        let url: URL
        if trimmed.hasPrefix("http") {
            guard let parsed = URL(string: trimmed) else { throw FeedError.invalidURL }
            url = parsed
        } else if trimmed.hasPrefix("@") {
            guard let parsed = URL(string: "https://www.youtube.com/\(trimmed)") else {
                throw FeedError.invalidURL
            }
            url = parsed
        } else {
            // Assume it's a channel ID
            return trimmed
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw FeedError.parseError("Could not decode page")
        }

        // Look for channel ID in meta tags or canonical URL
        // Pattern: <meta itemprop="channelId" content="UCxxxxx">
        if let range = html.range(of: #"channelId"\s+content="(UC[a-zA-Z0-9_-]{22})"#, options: .regularExpression) {
            let match = html[range]
            if let idRange = match.range(of: #"UC[a-zA-Z0-9_-]{22}"#, options: .regularExpression) {
                return String(match[idRange])
            }
        }

        // Fallback: look for /channel/UCxxx in the page
        if let range = html.range(of: #"/channel/(UC[a-zA-Z0-9_-]{22})"#, options: .regularExpression) {
            let match = html[range]
            if let idRange = match.range(of: #"UC[a-zA-Z0-9_-]{22}"#, options: .regularExpression) {
                return String(match[idRange])
            }
        }

        throw FeedError.parseError("Could not find channel ID on page")
    }

    /// Fetch the latest video ID from a channel's RSS feed.
    static func latestVideoID(channelID: String) async throws -> String {
        guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)") else {
            throw FeedError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let parser = FeedParser(data: data)
        guard let videoID = parser.parse() else {
            throw FeedError.noVideoFound
        }
        return videoID
    }
}

/// Minimal Atom XML parser that extracts the first <yt:videoId>.
private class FeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var videoID: String?
    private var currentElement = ""
    private var currentText = ""
    private var done = false

    init(data: Data) {
        self.data = data
    }

    func parse() -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return videoID
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "yt:videoId" && videoID == nil {
            videoID = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            done = true
        }
    }
}
