import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Channel.displayName) private var channels: [Channel]

    @State private var consentManager = ConsentManager.shared
    @State private var selectedChannel: Channel?
    @State private var showingHistory = false
    @State private var playingVideo: Video?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var handleInput = ""
    @State private var isAddingChannel = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    #if os(macOS)
    @State private var isFullScreen = false
    #endif

    private var feedService: FeedService {
        FeedService(modelContext: modelContext)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .task {
            await refreshAll()
            // Refresh every 30 minutes while running
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30 * 60))
                await refreshAll()
            }
        }
        .onChange(of: selectedChannel) { _, newValue in
            if newValue != nil {
                showingHistory = false
                if playingVideo != nil {
                    playingVideo = nil
                    columnVisibility = .automatic
                }
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .toolbar(playingVideo != nil && isFullScreen ? .hidden : .automatic)
        #endif
        #if canImport(WebKit)
        .task {
            // Re-inject existing cookie into WKWebView store on launch
            if let value = consentManager.socsCookieValue {
                await consentManager.ensureConsent()
            }
        }
        .sheet(item: $consentManager.consentRequest) { request in
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("YouTube Consent")
                            .font(.headline)
                        Text("Click on a video to trigger the cookie banner, then accept cookies. The dialog closes automatically.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let warning = consentManager.dismissWarning {
                            Text(warning)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    Button("Done") {
                        Task { await consentManager.finishConsent() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()

                Divider()

                ConsentWebView(searchQuery: request.searchQuery)
            }
            .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 600)
        }
        #endif
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedChannel) {
            Section {
                HStack {
                    TextField("@handle", text: $handleInput)
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                        .onSubmit { addChannel() }
                    Button {
                        addChannel()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(handleInput.isEmpty || isAddingChannel)
                    .buttonStyle(.borderless)
                }
                if isAddingChannel {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Adding channel...").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    selectedChannel = nil
                    showingHistory = false
                } label: {
                    Label("Home", systemImage: "house")
                }
                .buttonStyle(.plain)
                .fontWeight(selectedChannel == nil && !showingHistory ? .semibold : .regular)

                Button {
                    selectedChannel = nil
                    showingHistory = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.plain)
                .fontWeight(showingHistory ? .semibold : .regular)
            }

            Section("Channels") {
                ForEach(channels) { channel in
                    NavigationLink(value: channel) {
                        ChannelRow(channel: channel)
                    }
                    .contextMenu {
                        Button("Mark All as Watched") {
                            markAllWatched(channel)
                        }
                        Divider()
                        Button("Remove Channel", role: .destructive) {
                            deleteChannel(channel)
                        }
                    }
                }
                .onDelete(perform: deleteChannels)
            }
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let playingVideo {
            #if os(macOS)
            PlayerView(video: playingVideo, isFullScreen: isFullScreen) {
                stopPlaying()
            }
            #else
            PlayerView(video: playingVideo) {
                stopPlaying()
            }
            #endif
        } else if let selectedChannel {
            VideoListView(channel: selectedChannel) { video in
                play(video)
            }
        } else if showingHistory {
            HistoryView { video in
                play(video)
            }
        } else {
            HomeView { video in
                play(video)
            }
        }
    }

    // MARK: - Actions

    private func addChannel() {
        guard !handleInput.isEmpty else { return }
        let handle = handleInput
        handleInput = ""
        errorMessage = nil
        isAddingChannel = true

        Task {
            // If we don't have a consent cookie yet, show the consent sheet
            // and let the user consent before attempting the network request.
            if consentManager.needsConsent {
                consentManager.consentRequest = ConsentRequest(searchQuery: handle)
                isAddingChannel = false
                return
            }

            do {
                let channel = try await feedService.addChannel(handle: handle)
                selectedChannel = channel
            } catch ChannelFeed.FeedError.consentRequired {
                consentManager.consentRequest = ConsentRequest(searchQuery: handle)
            } catch {
                errorMessage = error.localizedDescription
            }
            isAddingChannel = false
        }
    }

    private func deleteChannels(at offsets: IndexSet) {
        for index in offsets {
            deleteChannel(channels[index])
        }
    }

    private func deleteChannel(_ channel: Channel) {
        if selectedChannel == channel {
            selectedChannel = nil
        }
        modelContext.delete(channel)
    }

    private func markAllWatched(_ channel: Channel) {
        for video in channel.videos where !video.watched {
            video.watched = true
            video.watchedAt = .now
        }
    }

    private func play(_ video: Video) {
        video.watched = true
        video.watchedAt = .now
        playingVideo = video
        columnVisibility = .detailOnly
    }

    private func stopPlaying() {
        playingVideo = nil
        columnVisibility = .automatic
    }

    private func refreshAll() async {
        isRefreshing = true
        await feedService.refreshAll()
        isRefreshing = false
    }
}

// MARK: - Channel Row

struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(channel.handle)
                    .fontWeight(.medium)
                Text(channel.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if channel.unwatchedCount > 0 {
                Text("\(channel.unwatchedCount)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Video List

struct VideoListView: View {
    @Environment(\.modelContext) private var modelContext
    let channel: Channel
    let onPlay: (Video) -> Void

    @State private var isLoadingMore = false

    private var feedService: FeedService {
        FeedService(modelContext: modelContext)
    }

    private var sortedVideos: [Video] {
        channel.videos
            .filter { !$0.isShort }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    var body: some View {
        List {
            ForEach(sortedVideos) { video in
                Button { onPlay(video) } label: {
                    VideoRow(video: video)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Open in Browser") {
                        openInBrowser(video)
                    }
                    if video.lastPosition > 0 {
                        Button("Resume at \(formatTime(video.lastPosition))") {
                            onPlay(video)
                        }
                    }
                }
                .onAppear {
                    if video.videoID == sortedVideos.last?.videoID {
                        loadMore()
                    }
                }
            }

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("Loading more videos...").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .navigationTitle(channel.displayName)
    }

    private func openInBrowser(_ video: Video) {
        let url = URL(string: "https://www.youtube.com/watch?v=\(video.videoID)")!
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    private func loadMore() {
        guard !isLoadingMore, channel.hasMoreVideos else { return }
        isLoadingMore = true
        Task {
            try? await feedService.loadMoreVideos(for: channel)
            isLoadingMore = false
        }
    }
}

struct VideoRow: View {
    let video: Video

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let urlString = video.thumbnailURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(16/9, contentMode: .fit)
                } placeholder: {
                    Rectangle().fill(.quaternary).aspectRatio(16/9, contentMode: .fit)
                }
                .frame(width: 160)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .fontWeight(video.watched ? .regular : .semibold)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(video.publishedAt, style: .relative)
                    if video.lastPosition > 0 && video.duration > 0 {
                        Text("·")
                        Text("\(formatTime(video.lastPosition)) / \(formatTime(video.duration))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Progress bar for partially watched
                if video.lastPosition > 0 && video.duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.quaternary)
                            Rectangle()
                                .fill(.blue)
                                .frame(width: geo.size.width * min(video.lastPosition / video.duration, 1.0))
                        }
                    }
                    .frame(height: 3)
                    .clipShape(Capsule())
                }
            }

            Spacer()

            if !video.watched {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - History View

struct HistoryView: View {
    @Query(
        filter: #Predicate<Video> { $0.watched },
        sort: \Video.watchedAt,
        order: .reverse
    ) private var watchedVideos: [Video]

    let onPlay: (Video) -> Void

    var body: some View {
        Group {
            if watchedVideos.isEmpty {
                ContentUnavailableView(
                    "No Watch History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Videos you watch will appear here")
                )
            } else {
                List {
                    ForEach(watchedVideos) { video in
                        Button { onPlay(video) } label: {
                            HomeVideoRow(video: video)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open in Browser") {
                                let url = URL(string: "https://www.youtube.com/watch?v=\(video.videoID)")!
                                #if os(macOS)
                                NSWorkspace.shared.open(url)
                                #else
                                UIApplication.shared.open(url)
                                #endif
                            }
                            if video.lastPosition > 0 {
                                Button("Resume at \(formatTime(video.lastPosition))") {
                                    onPlay(video)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

// MARK: - Home View

struct HomeView: View {
    @Query(
        filter: #Predicate<Video> { !$0.isShort && !$0.watched },
        sort: \Video.publishedAt,
        order: .reverse
    ) private var unwatchedVideos: [Video]

    let onPlay: (Video) -> Void

    var body: some View {
        Group {
            if unwatchedVideos.isEmpty {
                ContentUnavailableView(
                    "No Unwatched Videos",
                    systemImage: "tv",
                    description: Text("Add a channel with @handle to get started")
                )
            } else {
                List {
                    ForEach(unwatchedVideos) { video in
                        Button { onPlay(video) } label: {
                            HomeVideoRow(video: video)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open in Browser") {
                                let url = URL(string: "https://www.youtube.com/watch?v=\(video.videoID)")!
                                #if os(macOS)
                                NSWorkspace.shared.open(url)
                                #else
                                UIApplication.shared.open(url)
                                #endif
                            }
                            if video.lastPosition > 0 {
                                Button("Resume at \(formatTime(video.lastPosition))") {
                                    onPlay(video)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Home")
    }
}

struct HomeVideoRow: View {
    let video: Video

    var body: some View {
        HStack(spacing: 12) {
            if let urlString = video.thumbnailURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(16/9, contentMode: .fit)
                } placeholder: {
                    Rectangle().fill(.quaternary).aspectRatio(16/9, contentMode: .fit)
                }
                .frame(width: 160)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let channel = video.channel {
                        Text(channel.handle)
                            .foregroundStyle(.blue)
                    }
                    Text(video.publishedAt, style: .relative)
                    if video.lastPosition > 0 && video.duration > 0 {
                        Text("·")
                        Text("\(formatTime(video.lastPosition)) / \(formatTime(video.duration))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if video.lastPosition > 0 && video.duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.quaternary)
                            Rectangle()
                                .fill(.blue)
                                .frame(width: geo.size.width * min(video.lastPosition / video.duration, 1.0))
                        }
                    }
                    .frame(height: 3)
                    .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Player View

struct PlayerView: View {
    let video: Video
    var isFullScreen: Bool = false
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WebPlayerView(
                videoID: video.videoID,
                maximized: true,
                startAt: video.lastPosition
            ) { position, duration in
                video.lastPosition = position
                video.duration = duration
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(macOS)
            if !isFullScreen {
                playerBar
            }
            #elseif os(iOS)
            playerBar
            #endif
        }
        #if os(tvOS)
        .onExitCommand { onBack() }
        .onPlayPauseCommand {
            // Toggle play/pause via JS — no coordinator reference needed,
            // WKWebView is the first responder and handles it
        }
        #endif
    }

    #if os(macOS) || os(iOS)
    private var playerBar: some View {
        HStack {
            Button {
                onBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            #if os(macOS)
            .keyboardShortcut(.escape, modifiers: [])
            #endif

            Text(video.title)
                .lineLimit(1)
                .font(.headline)

            Spacer()

            Button {
                let url = URL(string: "https://www.youtube.com/watch?v=\(video.videoID)")!
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            .buttonStyle(.borderless)

            Text(video.publishedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
    #endif
}

// MARK: - Helpers

func formatTime(_ seconds: Double) -> String {
    let s = Int(seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
    return String(format: "%d:%02d", m, sec)
}
