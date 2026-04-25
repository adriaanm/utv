import SwiftUI
import SwiftData

// Root scene shared by the macOS executable and the tvOS Xcode target.
// Both entry points are thin @main wrappers that instantiate AppRoot().
public struct AppRoot: Scene {
    // We construct the container manually (rather than letting `.modelContainer(for:)`
    // build one for us) so SyncCoordinator can be bootstrapped against the same instance.
    private let container: ModelContainer

    public init() {
        do {
            self.container = try ModelContainer(for: Channel.self, Video.self)
        } catch {
            fatalError("Failed to build ModelContainer: \(error)")
        }
        SyncCoordinator.shared.bootstrap(container: container)
    }

    public var body: some Scene {
        WindowGroup {
            // The tvOS startup pull is driven from ContentView (it gates WebPlayerView
            // on the consent cookie that the pull delivers — see docs/tvos-port.md).
            ContentView()
        }
        #if os(macOS)
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
            CommandMenu("Device") {
                Button("Sync with Apple TV…") {
                    NotificationCenter.default.post(name: .utvSyncMenuRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        #endif
        .modelContainer(container)
    }
}

#if os(macOS)
public extension Notification.Name {
    static let utvSyncMenuRequested = Notification.Name("utv.sync.menuRequested")
}
#endif
