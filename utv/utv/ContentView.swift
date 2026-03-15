import SwiftUI

struct ContentView: View {
    @State private var channelInput = ""
    @State private var videoID: String?
    @State private var status = "Enter a channel ID, @handle, or URL"
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                TextField("Channel ID, @handle, or URL", text: $channelInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { playLatest() }

                Button("Play Latest") { playLatest() }
                    .disabled(channelInput.isEmpty || isLoading)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()

            // Status
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 8)
            }
            Text(status)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            // Player
            WebPlayerView(videoID: videoID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func playLatest() {
        guard !channelInput.isEmpty else { return }
        isLoading = true
        status = "Resolving channel..."

        Task {
            do {
                let channelID = try await ChannelFeed.resolveChannelID(from: channelInput)
                status = "Fetching feed for \(channelID)..."
                let latestID = try await ChannelFeed.latestVideoID(channelID: channelID)
                status = "Playing video \(latestID)"
                videoID = latestID
            } catch {
                status = "Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
