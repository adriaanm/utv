import Foundation
import SwiftData
#if canImport(WebKit)
import WebKit
#endif

// Glues together the pure SyncMerger with the MultipeerConnectivity transport.
//
// macOS:
// - Owns a long-running `SyncAdvertiser` so the tvOS app can pull from the Mac on its
//   startup (the refinement on top of the design doc — see CLAUDE.md / sync-design.md).
//   Mac is the canonical source of channels + consent cookie, so its responder bundle
//   includes both.
// - On user-invoked `runMacInitiatedSync()`, spins up a `SyncBrowser` that finds the TV,
//   pushes channels + videos + cookie, and applies the TV's reply (videos only).
//
// tvOS:
// - Also runs a `SyncAdvertiser` (so a Mac-side menu sync can land while the TV is open).
//   Its responder bundle carries videos only — channels are read-only on tvOS.
// - On launch, calls `runTVStartupPull()` which opens a `SyncBrowser`, finds the Mac,
//   pushes its videos, and applies the Mac's reply (channels + videos + consent cookie).

@MainActor
public final class SyncCoordinator {

    public static let shared = SyncCoordinator()

    public enum Status: Sendable {
        case idle
        case discovering
        case exchanging
        case done(SyncMerger.MergeStats)
        case failed(String)
    }

    public private(set) var status: Status = .idle

    private weak var modelContainer: ModelContainer?
    private var advertiser: SyncAdvertiser?

    private init() {}

    // Called once per app, from AppRoot, with the SwiftData container.
    public func bootstrap(container: ModelContainer) {
        self.modelContainer = container
        startAdvertiser()
    }

    // MARK: - Advertiser

    private func startAdvertiser() {
        guard advertiser == nil else { return }
        let name = defaultSyncPeerName()
        let adv = SyncAdvertiser(peerName: name) { [weak self] remoteBundle in
            guard let self else { throw SyncProtocolError.transport("coordinator gone") }
            return try await self.handleIncomingBundle(remoteBundle)
        }
        adv.start()
        advertiser = adv
    }

    // Responder side: receives a remote bundle, applies it, and returns our own bundle.
    private func handleIncomingBundle(_ remote: SyncBundle) async throws -> SyncBundle {
        let context = try makeContext()
        let stats = try SyncMerger.apply(remote, into: context, currentConsentCookie: currentConsentCookie())
        await applyConsentCookieIfNeeded(stats.consentCookieReceived)

        let outgoing = try SyncMerger.exportBundle(
            from: context,
            includeChannels: isCanonicalSource,
            consentCookie: isCanonicalSource ? currentConsentCookie() : nil
        )
        return outgoing
    }

    // MARK: - Initiator (Mac → TV, user-invoked)

    @discardableResult
    public func runMacInitiatedSync(timeout: TimeInterval = 20) async -> SyncMerger.MergeStats? {
        await runInitiator(timeout: timeout)
    }

    // MARK: - Initiator (tvOS → Mac, on launch)

    @discardableResult
    public func runTVStartupPull(timeout: TimeInterval = 20) async -> SyncMerger.MergeStats? {
        await runInitiator(timeout: timeout)
    }

    private func runInitiator(timeout: TimeInterval) async -> SyncMerger.MergeStats? {
        status = .discovering
        let browser = SyncBrowser(peerName: defaultSyncPeerName())
        var resultStats: SyncMerger.MergeStats?

        do {
            try await browser.runExchange(
                outgoing: { [weak self] in
                    guard let self else { throw SyncProtocolError.transport("coordinator gone") }
                    self.status = .exchanging
                    let context = try self.makeContext()
                    return try SyncMerger.exportBundle(
                        from: context,
                        includeChannels: self.isCanonicalSource,
                        consentCookie: self.isCanonicalSource ? self.currentConsentCookie() : nil
                    )
                },
                incoming: { [weak self] remote in
                    guard let self else { return }
                    let context = try self.makeContext()
                    let stats = try SyncMerger.apply(
                        remote,
                        into: context,
                        currentConsentCookie: self.currentConsentCookie()
                    )
                    await self.applyConsentCookieIfNeeded(stats.consentCookieReceived)
                    resultStats = stats
                },
                timeout: timeout
            )
            if let stats = resultStats {
                status = .done(stats)
            } else {
                status = .failed("No response received")
            }
            return resultStats
        } catch {
            status = .failed("\(error)")
            return nil
        }
    }

    // MARK: - Helpers

    // True on macOS — Mac is the canonical source for channels + consent cookie.
    private var isCanonicalSource: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    private func makeContext() throws -> ModelContext {
        guard let container = modelContainer else {
            throw SyncProtocolError.transport("model container not bootstrapped")
        }
        return ModelContext(container)
    }

    private func currentConsentCookie() -> String? {
        ConsentManager.shared.socsCookieValue
    }

    private func applyConsentCookieIfNeeded(_ cookie: String?) async {
        guard let cookie else { return }
        // Persist + inject into the WKWebView cookie store. Mirrors what
        // ConsentManager does after the user clicks through the consent banner.
        ConsentManager.shared.socsCookieValue = cookie
        await ConsentManager.shared.ensureConsent()
    }
}
