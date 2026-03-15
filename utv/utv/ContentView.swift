import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Channel.displayName) private var channels: [Channel]

    @State private var selectedChannel: Channel?
    @State private var playingVideo: Video?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var handleInput = ""
    @State private var isAddingChannel = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?

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
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedChannel) {
            Section {
                HStack {
                    TextField("@handle", text: $handleInput)
                        .textFieldStyle(.roundedBorder)
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

            Section("Channels") {
                ForEach(channels) { channel in
                    NavigationLink(value: channel) {
                        ChannelRow(channel: channel)
                    }
                }
                .onDelete(perform: deleteChannels)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
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
            PlayerView(video: playingVideo) {
                stopPlaying()
            }
        } else if let selectedChannel {
            VideoListView(channel: selectedChannel) { video in
                play(video)
            }
        } else {
            ContentUnavailableView(
                "Select a Channel",
                systemImage: "tv",
                description: Text("Add a channel with @handle to get started")
            )
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
            do {
                let channel = try await feedService.addChannel(handle: handle)
                selectedChannel = channel
            } catch {
                errorMessage = error.localizedDescription
            }
            isAddingChannel = false
        }
    }

    private func deleteChannels(at offsets: IndexSet) {
        for index in offsets {
            let channel = channels[index]
            if selectedChannel == channel {
                selectedChannel = nil
            }
            modelContext.delete(channel)
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
    let channel: Channel
    let onPlay: (Video) -> Void

    private var sortedVideos: [Video] {
        channel.videos.sorted { $0.publishedAt > $1.publishedAt }
    }

    var body: some View {
        List {
            ForEach(sortedVideos) { video in
                VideoRow(video: video)
                    .contentShape(Rectangle())
                    .onTapGesture { onPlay(video) }
            }
        }
        .navigationTitle(channel.displayName)
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
                Text(video.publishedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

// MARK: - Player View

struct PlayerView: View {
    let video: Video
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WebPlayerView(videoID: video.videoID, maximized: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut(.escape, modifiers: [])

                Text(video.title)
                    .lineLimit(1)
                    .font(.headline)

                Spacer()

                Text(video.publishedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
