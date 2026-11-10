//
//  DockClient.swift
//  MobileDock for iOS — discovers Macs on the local network and talks to the host app.
//

import Foundation
import Network
import SwiftUI
import UIKit
import Combine

@MainActor
final class DockClient: ObservableObject {

    enum Phase: Equatable {
        case idle
        case browsing
        case connecting(String)
        case needsPIN(String)
        case connected(HostInfo)
        case failed(String)
    }

    struct DiscoveredHost: Identifiable, Hashable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
    }

    // MARK: Published state

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var hosts: [DiscoveredHost] = []
    @Published private(set) var catalog: Catalog?
    @Published private(set) var icons: [String: UIImage] = [:]
    @Published private(set) var running: Set<String> = []
    @Published private(set) var recents: [String] = []
    @Published private(set) var frontApp: String?
    @Published private(set) var macClipboard: String = ""
    @Published private(set) var windows: [String: [WindowSummary]] = [:]
    @Published private(set) var status: MacStatus?
    @Published private(set) var lastReceivedFile: URL?
    @Published var toast: String?
    @Published var pinError: String?
    /// Extra detail about the current attempt (for example a network wait reason).
    @Published var statusNote: String?

    var host: HostInfo? {
        if case .connected(let info) = phase { return info }
        return nil
    }

    var isConnected: Bool { host != nil }

    /// False when macOS has not granted Accessibility, which silently disables
    /// the pointer, the keyboard and every window action.
    var accessibilityGranted: Bool { catalog?.accessibilityGranted ?? true }

    func requestAccessibility() {
        send(.requestAccessibilityPrompt)
        showToast("Opening Privacy & Security on the Mac")
    }

    // MARK: Private

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var pendingEndpoint: NWEndpoint?
    private var pendingHostName: String?
    private var pendingPIN: String?
    private var idleTimer: Timer?
    private var lastActivity = Date()
    private let parser = FrameParser()
    private let queue = DispatchQueue(label: "com.mobiledock.client")
    private var keepAlive: Timer?
    private var handshake: Timer?
    private var requestedIcons: Set<String> = []
    private var incomingFiles: [String: (name: String, total: Int, parts: [Int: Data])] = [:]
    private var statusPoll: Timer?
    private var reconnectAttempts = 0
    /// Set once a session has been established, so a drop can be told from a
    /// first-time connection and retried on its own.
    private(set) var wasConnected = false
    @Published private(set) var isReconnecting = false

    private let device: DeviceInfo = {
        let idKey = "device.identifier"
        let stored = UserDefaults.standard.string(forKey: idKey) ?? {
            let generated = UUID().uuidString
            UserDefaults.standard.set(generated, forKey: idKey)
            return generated
        }()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        return DeviceInfo(id: stored,
                          name: UIDevice.current.name,
                          model: UIDevice.current.model,
                          isPad: isPad)
    }()

    // MARK: Discovery

    /// Called when the app returns to the foreground.
    func resume() {
        startBrowsing()
        guard !isConnected else {
            send(.requestCatalog)
            return
        }
        guard let name = TokenStore.rememberedHostName, TokenStore.pin(for: name) != nil else { return }
        isReconnecting = true
        if let match = hosts.first(where: { $0.name == name }) {
            connect(to: match)
        }
    }

    func startBrowsing() {
        guard browser == nil else { return }
        phase = .browsing
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: MobileDock.serviceType, domain: nil), using: params)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.hosts = results.compactMap { result in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    return DiscoveredHost(id: name, name: name, endpoint: result.endpoint)
                }
                .sorted { $0.name < $1.name }
                self?.autoConnectIfRemembered()
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in self?.phase = .failed(error.localizedDescription) }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    private func autoConnectIfRemembered() {
        guard !isConnected,
              let remembered = TokenStore.rememberedHostName,
              TokenStore.pin(for: remembered) != nil,
              let match = hosts.first(where: { $0.name == remembered }) else { return }
        if case .connecting = phase { return }
        if case .needsPIN = phase { return }
        connect(to: match)
    }

    // MARK: Connection

    func connect(to host: DiscoveredHost) {
        pendingEndpoint = host.endpoint
        pendingHostName = host.name
        // The PIN is the TLS pre-shared key, so it has to be known before dialling.
        guard let pin = TokenStore.pin(for: host.name) else {
            connection?.cancel()
            connection = nil
            phase = .needsPIN(host.name)
            return
        }
        connect(to: host, pin: pin)
    }

    func connect(to host: DiscoveredHost, pin: String) {
        connection?.cancel()
        pendingEndpoint = host.endpoint
        pendingHostName = host.name
        pendingPIN = pin
        phase = .connecting(host.name)

        let params = SecureTransport.parameters(pin: pin)
        let connection = NWConnection(to: host.endpoint, using: params)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handle(state: state, hostName: host.name) }
        }
        connection.start(queue: queue)
        self.connection = connection
        startHandshakeTimeout(hostName: host.name)
        receive()
    }

    func disconnect(forget: Bool = false) {
        keepAlive?.invalidate()
        keepAlive = nil
        cancelHandshakeTimeout()
        stopStatusUpdates()
        idleTimer?.invalidate()
        idleTimer = nil
        connection?.cancel()
        connection = nil
        catalog = nil
        icons.removeAll()
        requestedIcons.removeAll()
        if forget {
            if let name = host?.name { TokenStore.forget(hostName: name) } else { TokenStore.clear() }
        }
        phase = .browsing
        startBrowsing()
    }

    private func handle(state: NWConnection.State, hostName: String) {
        switch state {
        case .ready:
            statusNote = nil
            reconnectAttempts = 0
            send(.hello(version: MobileDock.protocolVersion, device: device))
            if let token = TokenStore.token(for: hostName) {
                send(.authenticate(token: token, device: device))
            } else if let pin = pendingPIN {
                send(.pair(pin: pin, device: device))
            }
            startKeepAlive()
        case .failed(let error):
            if !isConnected && TokenStore.token(for: hostName) == nil {
                pinError = "That PIN doesn’t match this Mac."
                TokenStore.forgetPIN(for: hostName)
                phase = .needsPIN(hostName)
                Haptics.error()
                return
            }
            phase = .failed(error.localizedDescription)
            isReconnecting = wasConnected
            scheduleReconnect(hostName: hostName)
        case .cancelled:
            if wasConnected, isConnected {
                // The socket went away under us — come back on our own.
                phase = .browsing
                isReconnecting = true
                scheduleReconnect(hostName: hostName)
            }
        case .waiting(let error):
            // Keep the phase's host name exact; the detail rides alongside it.
            statusNote = error.localizedDescription
            phase = .connecting(hostName)
        default:
            break
        }
    }

    private func scheduleReconnect(hostName: String) {
        guard reconnectAttempts < 8,
              let endpoint = pendingEndpoint,
              let pin = pendingPIN ?? TokenStore.pin(for: hostName) else {
            isReconnecting = false
            return
        }
        reconnectAttempts += 1
        let delay = Double(reconnectAttempts) * 1.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.connect(to: DiscoveredHost(id: hostName, name: hostName, endpoint: endpoint), pin: pin)
        }
    }

    /// A host that accepts the socket but never greets us (a wedged or half-dead
    /// instance still holding the port) would otherwise spin on "Connecting…".
    private func startHandshakeTimeout(hostName: String) {
        handshake?.invalidate()
        handshake = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isConnected else { return }
                if case .needsPIN = self.phase { return }
                self.connection?.cancel()
                self.connection = nil
                if TokenStore.token(for: hostName) == nil {
                    // Never got through the handshake on a fresh pairing: the PIN is the suspect.
                    TokenStore.forgetPIN(for: hostName)
                    self.pinError = "Couldn’t reach \(hostName) with that PIN."
                    self.phase = .needsPIN(hostName)
                } else {
                    self.phase = .browsing
                    self.showToast("\(hostName) didn’t answer — pick it again to retry.")
                }
                Haptics.error()
            }
        }
    }

    private func cancelHandshakeTimeout() {
        handshake?.invalidate()
        handshake = nil
    }

    /// Drops the connection after a spell of inactivity, so a phone left on a
    /// desk is not a live remote for the rest of the day.
    private func startIdleWatch() {
        idleTimer?.invalidate()
        lastActivity = Date()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let minutes = UserDefaults.standard.object(forKey: "idleMinutes") as? Int ?? 0
                guard minutes > 0 else { return }
                if Date().timeIntervalSince(self.lastActivity) > Double(minutes) * 60 {
                    self.showToast("Disconnected after \(minutes) min idle")
                    self.disconnect()
                }
            }
        }
    }

    private func startKeepAlive() {
        keepAlive?.invalidate()
        keepAlive = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.send(.ping) }
        }
    }

    // MARK: Pairing

    func submit(pin: String) {
        pinError = nil
        guard let name = pendingHostName, let endpoint = pendingEndpoint else { return }
        TokenStore.savePIN(pin, hostName: name)
        connect(to: DiscoveredHost(id: name, name: name, endpoint: endpoint), pin: pin)
    }

    // MARK: Sending

    func send(_ message: ClientMessage) {
        if case .ping = message {} else { lastActivity = Date() }
        guard let connection, let frame = try? WireCoder.encode(message) else { return }
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.parser.append(data)
                self.drain()
            }
            if isComplete || error != nil { return }
            self.receive()
        }
    }

    private func drain() {
        while true {
            guard let body = try? parser.next(), let body2 = Optional(body) else { return }
            guard let message = try? WireCoder.decoder.decode(ServerMessage.self, from: body2) else { continue }
            Task { @MainActor in self.handle(message) }
        }
    }

    private func handle(_ message: ServerMessage) {
        switch message {
        case .hello:
            // The host is alive and speaking our protocol.
            cancelHandshakeTimeout()

        case .pairResult(let success, let token, let hostInfo, let text):
            cancelHandshakeTimeout()
            if success, let hostInfo {
                wasConnected = true
                isReconnecting = false
                if let token { TokenStore.save(token: token, hostName: hostInfo.name) }
                if let pin = pendingPIN { TokenStore.savePIN(pin, hostName: hostInfo.name) }
                startIdleWatch()
                phase = .connected(hostInfo)
                Haptics.success()
                send(.requestCatalog)
            } else {
                pinError = text ?? "Pairing failed."
                if case .connected = phase {} else if case .connecting(let name) = phase {
                    phase = .needsPIN(name)
                }
                Haptics.error()
            }

        case .catalog(let catalog):
            self.catalog = catalog
            running = Set(catalog.running)
            recents = catalog.recents
            frontApp = catalog.frontApp
            requestIconsIfNeeded(for: catalog.apps.map(\.bundleID))

        case .icons(let items):
            for item in items {
                if let image = UIImage(data: item.png) {
                    icons[item.bundleID] = image
                }
            }

        case .frontApp(let bundleID, let recents, let running):
            frontApp = bundleID
            self.recents = recents
            self.running = Set(running)

        case .clipboard(let text):
            macClipboard = text

        case .toast(let text):
            showToast(text)

        case .failure(let reason):
            showToast(reason)

        case .pong:
            break

        case .windows(let bundleID, let items):
            windows[bundleID] = items

        case .status(let status):
            self.status = status

        case .fileChunk(let chunk):
            assemble(chunk)

        case .fileReceived(let name, _):
            showToast("\(name) saved on the Mac")
            Haptics.success()

        case .notPermitted(let what):
            showToast("This Mac blocks: \(what)")
            Haptics.error()
        }
    }

    /// Rebuilds a file streamed from the Mac and drops it in this app's Documents.
    private func assemble(_ chunk: FileChunk) {
        var transfer = incomingFiles[chunk.transferID] ?? (chunk.name, chunk.total, [:])
        transfer.parts[chunk.index] = chunk.data
        incomingFiles[chunk.transferID] = transfer
        guard transfer.parts.count == transfer.total else { return }
        incomingFiles.removeValue(forKey: chunk.transferID)

        var data = Data()
        for index in 0..<transfer.total {
            guard let part = transfer.parts[index] else { return }
            data.append(part)
        }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent(transfer.name)
        do {
            try data.write(to: url)
            lastReceivedFile = url
            showToast("Received \(transfer.name)")
            Haptics.success()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    // MARK: Files out

    func sendFile(name: String, data: Data) {
        let size = 512 * 1024
        let total = max(1, Int(ceil(Double(data.count) / Double(size))))
        let transferID = UUID().uuidString
        for index in 0..<total {
            let start = index * size
            let end = min(start + size, data.count)
            send(.sendFile(chunk: FileChunk(transferID: transferID,
                                            name: name,
                                            index: index,
                                            total: total,
                                            data: data.subdata(in: start..<end))))
        }
        showToast("Sending \(name)…")
    }

    // MARK: Status polling

    func startStatusUpdates() {
        send(.requestStatus)
        statusPoll?.invalidate()
        statusPoll = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.send(.requestStatus) }
        }
    }

    func stopStatusUpdates() {
        statusPoll?.invalidate()
        statusPoll = nil
    }

    func requestIconsIfNeeded(for bundleIDs: [String]) {
        let missing = bundleIDs.filter { icons[$0] == nil && !requestedIcons.contains($0) }
        guard !missing.isEmpty else { return }
        requestedIcons.formUnion(missing)
        for chunk in missing.chunked(into: 40) {
            send(.requestIcons(bundleIDs: chunk))
        }
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if toast == text { toast = nil }
        }
    }

    func appName(for bundleID: String) -> String {
        catalog?.apps.first { $0.bundleID == bundleID }?.name ?? bundleID
    }
}

// MARK: - Token persistence

/// Remembers every Mac this device has paired with, not just the last one.
enum TokenStore {
    private static let tokensKey = "paired.tokens.v2"
    private static let lastKey = "paired.host"

    private static var tokens: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: tokensKey) }
    }

    static var rememberedHostName: String? {
        UserDefaults.standard.string(forKey: lastKey)
    }

    static var knownHosts: [String] {
        tokens.keys.sorted()
    }

    static func token(for hostName: String) -> String? {
        tokens[hostName]
    }

    static func save(token: String, hostName: String) {
        var current = tokens
        current[hostName] = token
        tokens = current
        UserDefaults.standard.set(hostName, forKey: lastKey)
    }

    private static let pinsKey = "paired.pins.v1"

    private static var pins: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: pinsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: pinsKey) }
    }

    static func pin(for hostName: String) -> String? {
        pins[hostName]
    }

    static func savePIN(_ pin: String, hostName: String) {
        var current = pins
        current[hostName] = pin
        pins = current
    }

    static func forgetPIN(for hostName: String) {
        var current = pins
        current.removeValue(forKey: hostName)
        pins = current
    }

    static func forget(hostName: String) {
        forgetPIN(for: hostName)
        var current = tokens
        current.removeValue(forKey: hostName)
        tokens = current
        if rememberedHostName == hostName {
            UserDefaults.standard.removeObject(forKey: lastKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: tokensKey)
        UserDefaults.standard.removeObject(forKey: pinsKey)
        UserDefaults.standard.removeObject(forKey: lastKey)
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func firm() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
