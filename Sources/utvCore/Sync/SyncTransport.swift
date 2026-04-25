import Foundation
import MultipeerConnectivity
#if canImport(UIKit)
import UIKit
#endif

// MultipeerConnectivity-based transport for the Mac ↔ Apple TV sync. The protocol
// is a single send + single receive per side (initiator sends first, then receives).
//
// Two modes:
//
// - `SyncAdvertiser` (long-running): advertises the service while the app runs and
//   auto-accepts the first invitation. Calls back into a handler that produces the
//   responder's bundle once the initiator's bundle has arrived.
//
// - `SyncBrowser` (per-attempt): browses for peers, invites the first one found,
//   sends the initiator's bundle, awaits the responder's reply, then disconnects.
//
// Both sides share the same MCSession-per-connection model: the advertiser's
// invitation handler hands the framework a fresh `MCSession`, and the browser
// constructs its own `MCSession` for outgoing invitations. We never share a
// session across roles.

public let syncServiceType = "utv-sync"

// Local peer name — visible to the other device during discovery. Falls back to
// a generic value if the OS gives us nothing useful (rare, but happens in CI).
@MainActor
public func defaultSyncPeerName() -> String {
    #if os(macOS)
    if let name = Host.current().localizedName, !name.isEmpty { return name }
    let host = ProcessInfo.processInfo.hostName
    return host.isEmpty ? "Mac" : host
    #else
    let name = UIDevice.current.name
    return name.isEmpty ? "Apple TV" : name
    #endif
}

// MARK: - Advertiser (responder)

@MainActor
public final class SyncAdvertiser: NSObject {

    public typealias Responder = @MainActor (SyncBundle) async throws -> SyncBundle

    private let peerID: MCPeerID
    private let respond: Responder
    private var advertiser: MCNearbyServiceAdvertiser?
    private var activeSession: ActiveSession?

    public init(peerName: String, respond: @escaping Responder) {
        self.peerID = MCPeerID(displayName: peerName)
        self.respond = respond
        super.init()
    }

    public func start() {
        guard advertiser == nil else { return }
        let a = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: syncServiceType)
        a.delegate = self
        a.startAdvertisingPeer()
        advertiser = a
    }

    public func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        activeSession?.tearDown()
        activeSession = nil
    }
}

extension SyncAdvertiser: MCNearbyServiceAdvertiserDelegate {
    nonisolated public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Auto-accept; trusted personal LAN.
        Task { @MainActor in
            // Only accept one connection at a time. If we already have one
            // in progress, refuse this one.
            if self.activeSession != nil {
                invitationHandler(false, nil)
                return
            }
            let session = MCSession(peer: self.peerID, securityIdentity: nil, encryptionPreference: .required)
            let active = ActiveSession(session: session, remotePeer: peerID, role: .responder, respond: self.respond) { [weak self] in
                self?.activeSession = nil
            }
            self.activeSession = active
            session.delegate = active
            invitationHandler(true, session)
        }
    }

    nonisolated public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor in
            print("SyncAdvertiser failed: \(error)")
        }
    }
}

// MARK: - Browser (initiator)

@MainActor
public final class SyncBrowser: NSObject {

    public typealias OutgoingBundle = @MainActor () async throws -> SyncBundle
    public typealias IncomingBundle = @MainActor (SyncBundle) async throws -> Void

    private let peerID: MCPeerID
    private var browser: MCNearbyServiceBrowser?
    private var session: MCSession?
    private var active: ActiveSession?
    private var found: CheckedContinuation<MCPeerID, Error>?

    public init(peerName: String) {
        self.peerID = MCPeerID(displayName: peerName)
        super.init()
    }

    // Discover, invite, send `outgoing()`, await response, apply via `incoming()`.
    public func runExchange(
        outgoing: @escaping OutgoingBundle,
        incoming: @escaping IncomingBundle,
        timeout: TimeInterval = 15
    ) async throws {
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.session = session

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: syncServiceType)
        browser.delegate = self
        self.browser = browser

        defer { teardown() }

        // 1. Discover a peer.
        let remote = try await withTimeout(timeout) {
            try await self.findPeer(browser: browser)
        }

        // 2. Set up an active-session driver and invite the peer.
        let active = ActiveSession(
            session: session,
            remotePeer: remote,
            role: .initiator,
            outgoing: outgoing,
            incoming: incoming
        ) { [weak self] in
            self?.active = nil
        }
        self.active = active
        session.delegate = active
        browser.invitePeer(remote, to: session, withContext: nil, timeout: timeout)

        // 3. Wait for the exchange to finish.
        try await withTimeout(timeout) {
            try await active.waitUntilDone()
        }
    }

    private func findPeer(browser: MCNearbyServiceBrowser) async throws -> MCPeerID {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<MCPeerID, Error>) in
            self.found = cont
            browser.startBrowsingForPeers()
        }
    }

    private func teardown() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        session?.disconnect()
        session?.delegate = nil
        session = nil
        active = nil
    }
}

extension SyncBrowser: MCNearbyServiceBrowserDelegate {
    nonisolated public func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            guard let cont = self.found else { return }
            self.found = nil
            browser.stopBrowsingForPeers()
            cont.resume(returning: peerID)
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            if let cont = self.found {
                self.found = nil
                cont.resume(throwing: SyncProtocolError.transport("\(error)"))
            }
        }
    }
}

// MARK: - ActiveSession

// Shared state machine for one connected MCSession. Used by both advertiser
// (responder role) and browser (initiator role). Conforms to MCSessionDelegate.
@MainActor
private final class ActiveSession: NSObject, MCSessionDelegate {

    enum Role { case initiator, responder }

    private let session: MCSession
    private let remotePeer: MCPeerID
    private let role: Role
    private let onDone: () -> Void

    // Initiator: send `outgoing()` first, then read remote, then apply via `incoming`.
    private let outgoing: SyncBrowser.OutgoingBundle?
    private let incoming: SyncBrowser.IncomingBundle?
    // Responder: read remote first, then call `respond(remote)` and send the result.
    private let respond: SyncAdvertiser.Responder?

    private var doneContinuation: CheckedContinuation<Void, Error>?
    private var hasFinished = false

    // Initiator init.
    init(
        session: MCSession,
        remotePeer: MCPeerID,
        role: Role,
        outgoing: @escaping SyncBrowser.OutgoingBundle,
        incoming: @escaping SyncBrowser.IncomingBundle,
        onDone: @escaping () -> Void
    ) {
        self.session = session
        self.remotePeer = remotePeer
        self.role = role
        self.outgoing = outgoing
        self.incoming = incoming
        self.respond = nil
        self.onDone = onDone
    }

    // Responder init.
    init(
        session: MCSession,
        remotePeer: MCPeerID,
        role: Role,
        respond: @escaping SyncAdvertiser.Responder,
        onDone: @escaping () -> Void
    ) {
        self.session = session
        self.remotePeer = remotePeer
        self.role = role
        self.outgoing = nil
        self.incoming = nil
        self.respond = respond
        self.onDone = onDone
    }

    func waitUntilDone() async throws {
        if hasFinished { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.doneContinuation = cont
        }
    }

    func tearDown() {
        finish(.success(()))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        if let cont = doneContinuation {
            doneContinuation = nil
            switch result {
            case .success: cont.resume()
            case .failure(let err): cont.resume(throwing: err)
            }
        }
        session.disconnect()
        onDone()
    }

    // MARK: MCSessionDelegate

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if self.role == .initiator {
                    do {
                        guard let outgoing = self.outgoing else { return }
                        let bundle = try await outgoing()
                        let data = try SyncCoding.encoder.encode(bundle)
                        try session.send(data, toPeers: [peerID], with: .reliable)
                    } catch {
                        self.finish(.failure(error))
                    }
                }
                // Responder waits for didReceive data.
            case .notConnected:
                // If we haven't successfully finished the exchange yet, surface the disconnect.
                if !self.hasFinished {
                    self.finish(.failure(SyncProtocolError.transport("disconnected")))
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let bundle = try SyncCoding.decoder.decode(SyncBundle.self, from: data)
                guard bundle.schemaVersion == SyncBundle.currentSchemaVersion else {
                    throw SyncProtocolError.schemaMismatch(local: SyncBundle.currentSchemaVersion, remote: bundle.schemaVersion)
                }
                switch self.role {
                case .initiator:
                    try await self.incoming?(bundle)
                    self.finish(.success(()))
                case .responder:
                    guard let respond = self.respond else { return }
                    let reply = try await respond(bundle)
                    let outData = try SyncCoding.encoder.encode(reply)
                    try session.send(outData, toPeers: [peerID], with: .reliable)
                    self.finish(.success(()))
                }
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Helpers

private func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    _ work: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SyncProtocolError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
