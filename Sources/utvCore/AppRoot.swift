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
            ContentView()
                #if os(tvOS)
                .task {
                    // Pull from the Mac on every cold start. The Mac is assumed to
                    // be running and advertising; if not, the timeout fires and we
                    // continue with whatever local state we already have.
                    await SyncCoordinator.shared.runTVStartupPull()
                }
                #endif
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
