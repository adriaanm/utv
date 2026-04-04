import SwiftUI
import SwiftData

@main
struct utvApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Clear Cookies & Re-consent") {
                    Task { @MainActor in
                        await ConsentManager.shared.clearAllCookies()
                        ConsentManager.shared.consentRequest = ConsentRequest(searchQuery: nil)
                    }
                }
            }
        }
        .modelContainer(for: [Channel.self, Video.self])
    }
}
