import SwiftUI
import SwiftData

@main
struct utvApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1280, height: 800)
        .modelContainer(for: [Channel.self, Video.self])
    }
}
