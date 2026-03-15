import SwiftUI
import SwiftData

@main
struct utvApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
        .modelContainer(for: [Channel.self, Video.self])
    }
}
