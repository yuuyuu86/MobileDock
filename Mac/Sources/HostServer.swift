//
//  HostServer.swift
//  MobileDock for Mac — Bonjour-advertised TCP listener that serves paired iOS remotes.
//

import Foundation
import Network
import AppKit
import Combine

@MainActor
final class HostServer: ObservableObject {

    struct ConnectedDevice: Identifiable, Hashable {
        let id: String
        var name: String
        var model: String
        var isPad: Bool
        var connectedAt: Date
    }

    @Published private(set) var isRunning = false
    @Published private(set) var devices: [ConnectedDevice] = []
    @Published private(set) var lastError: String?
    /// The PIN stays stable across launches so a Mac left running keeps the same
    /// digits on screen; regenerating is an explicit action.
    @Published var pin: String = PairingStore.shared.pin {
        didSet { PairingStore.shared.pin = pin }
    }

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HostConnection] = [:]
    private let queue = DispatchQueue(label: "com.mobiledock.host.listener")

    let catalog: AppCatalogService
    let executor: ActionExecutor
    let pointer = PointerService()
    let windows = WindowService()
    let status = StatusService()
    let files = FileService()

    init(catalog: AppCatalogService, executor: ActionExecutor) {
        self.catalog = catalog
        self.executor = executor
        catalog.onChange = { [weak self] in self?.broadcastState() }
    }

    // MARK: Lifecycle

    func start() {
        guard listener == nil else { return }
        do {
            let params = SecureTransport.parameters(pin: pin)
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: MobileDock.defaultPort) ?? .any)
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac",
                                                  type: MobileDock.serviceType,
                                                  domain: nil)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.handle(state: state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.close() }
        connections.removeAll()
        devices.removeAll()
        isRunning = false
    }

    func restart() {
        stop()
        start()
    }

    func regeneratePIN() {
        pin = Self.makePIN()
        // The PIN keys the TLS channel, so the listener has to come back up with it.
        restart()
    }

    func forgetAllDevices() {
        PairingStore.shared.removeAll()
        connections.values.forEach { $0.close() }
    }

    // MARK: Listener plumbing

    private func handle(state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            lastError = nil
        case .failed(let error):
            isRunning = false
            lastError = error.localizedDescription
            // Port squatted by a stale process: fall back to an ephemeral port.
            listener = nil
            queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                Task { @MainActor in self?.startOnAnyPort() }
            }
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func startOnAnyPort() {
        guard listener == nil else { return }
        do {
            let params = SecureTransport.parameters(pin: pin)
            let listener = try NWListener(using: params)
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac",
                                                  type: MobileDock.serviceType,
                                                  domain: nil)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.handle(state: state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func accept(_ nwConnection: NWConnection) {
        let connection = HostConnection(connection: nwConnection, server: self, queue: queue)
        connections[ObjectIdentifier(connection)] = connection
        connection.start()
    }

    // MARK: Connection callbacks

    func connectionDidAuthenticate(_ connection: HostConnection, device: DeviceInfo) {
        devices.removeAll { $0.id == device.id }
        devices.append(ConnectedDevice(id: device.id,
                                       name: device.name,
                                       model: device.model,
                                       isPad: device.isPad,
                                       connectedAt: Date()))
        NSSound(named: "Tink")?.play()
    }

    func connectionDidClose(_ connection: HostConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        if let id = connection.device?.id {
            devices.removeAll { $0.id == id }
        }
    }

    func verify(pin candidate: String) -> Bool {
        candidate.trimmingCharacters(in: .whitespaces) == pin
    }

    var hostInfo: HostInfo {
        HostInfo(id: PairingStore.shared.hostID,
                 name: Host.current().localizedName ?? "Mac",
                 model: Self.modelName(),
                 version: Bundle.main.shortVersion)
    }

    func currentCatalog() -> Catalog {
        catalog.snapshot(host: hostInfo)
    }

    /// Brightness has no public setter, so walk it with the media keys and keep
    /// our own estimate in step.
    func setBrightness(_ level: Double) {
        let target = min(1, max(0, level))
        let steps = Int(((target - status.brightnessEstimate) * 16).rounded())
        guard steps != 0 else { return }
        for _ in 0..<abs(steps) {
            executor.media(steps > 0 ? .brightnessUp : .brightnessDown)
            usleep(12_000)
        }
        status.noteBrightness(target)
    }

    func broadcastState() {
        let snapshot = ServerMessage.frontApp(bundleID: catalog.frontAppBundleID,
                                              recents: catalog.recents,
                                              running: catalog.runningBundleIDs)
        connections.values.forEach { $0.send(snapshot) }
    }

    func broadcastCatalog() {
        let message = ServerMessage.catalog(currentCatalog())
        connections.values.forEach { $0.send(message) }
    }

    // MARK: Helpers

    static func makePIN() -> String { PairingStore.makePIN() }

    static func modelName() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var chars = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        return String(cString: chars)
    }
}

// MARK: - Per-device connection

final class HostConnection {

    private let connection: NWConnection
    private unowned let server: HostServer
    private let queue: DispatchQueue
    private let parser = FrameParser()
    private var authenticated = false
    private(set) var device: DeviceInfo?

    init(connection: NWConnection, server: HostServer, queue: DispatchQueue) {
        self.connection = connection
        self.server = server
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self.send(.hello(version: MobileDock.protocolVersion,
                                     host: self.server.hostInfo,
                                     requiresPairing: true))
                }
            case .failed, .cancelled:
                Task { @MainActor in self.server.connectionDidClose(self) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func close() {
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.parser.append(data)
                self.drain()
            }
            if isComplete || error != nil {
                Task { @MainActor in self.server.connectionDidClose(self) }
                self.connection.cancel()
                return
            }
            self.receive()
        }
    }

    private func drain() {
        while true {
            do {
                guard let body = try parser.next() else { return }
                let message = try WireCoder.decoder.decode(ClientMessage.self, from: body)
                Task { @MainActor in self.handle(message) }
            } catch {
                Task { @MainActor in self.send(.failure(reason: error.localizedDescription)) }
                return
            }
        }
    }

    func send(_ message: ServerMessage) {
        guard let frame = try? WireCoder.encode(message) else { return }
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    /// Streams a file to the device in frames the socket is happy with.
    private func sendFile(name: String, data: Data) {
        let size = FileService.chunkBytes
        let total = max(1, Int(ceil(Double(data.count) / Double(size))))
        let transferID = UUID().uuidString
        for index in 0..<total {
            let start = index * size
            let end = min(start + size, data.count)
            let slice = data.subdata(in: start..<end)
            send(.fileChunk(FileChunk(transferID: transferID,
                                      name: name,
                                      index: index,
                                      total: total,
                                      data: slice)))
        }
    }

    // MARK: Message handling

    @MainActor
    private func handle(_ message: ClientMessage) {
        switch message {
        case .hello:
            send(.hello(version: MobileDock.protocolVersion, host: server.hostInfo, requiresPairing: true))

        case .pair(let pin, let device):
            guard server.verify(pin: pin) else {
                send(.pairResult(success: false, token: nil, host: nil, message: "That PIN doesn’t match the one on your Mac."))
                return
            }
            let token = PairingStore.shared.issueToken(for: device)
            self.device = device
            authenticated = true
            send(.pairResult(success: true, token: token, host: server.hostInfo, message: nil))
            server.connectionDidAuthenticate(self, device: device)
            send(.catalog(server.currentCatalog()))

        case .authenticate(let token, let device):
            guard PairingStore.shared.isValid(token: token, for: device.id) else {
                send(.pairResult(success: false, token: nil, host: nil, message: "This Mac no longer trusts that device. Enter the PIN again."))
                return
            }
            self.device = device
            authenticated = true
            send(.pairResult(success: true, token: token, host: server.hostInfo, message: nil))
            server.connectionDidAuthenticate(self, device: device)
            send(.catalog(server.currentCatalog()))

        case .ping:
            send(.pong)

        default:
            guard authenticated else {
                send(.failure(reason: "Pair with this Mac first."))
                return
            }
            guard let device, DevicePolicy.shared.allows(message, for: device.id) else {
                send(.notPermitted(what: DevicePolicy.category(of: message).title))
                return
            }
            perform(message)
        }
    }

    @MainActor
    private func perform(_ message: ClientMessage) {
        let executor = server.executor
        switch message {
        case .requestCatalog:
            server.catalog.refresh()
            send(.catalog(server.currentCatalog()))

        case .requestIcons(let bundleIDs):
            let icons = server.catalog.icons(for: bundleIDs)
            // Chunked so a large first sync never blocks the bar from drawing.
            for chunk in icons.chunked(into: 12) {
                send(.icons(items: chunk))
            }

        case .launchApp(let bundleID):
            executor.launch(bundleID: bundleID)

        case .quitApp(let bundleID):
            executor.quit(bundleID: bundleID)

        case .hideApp(let bundleID):
            executor.hide(bundleID: bundleID)

        case .runShortcut(let name):
            executor.runShortcut(named: name)
            send(.toast(text: "Running “\(name)”"))

        case .openURL(let url):
            executor.open(urlString: url)

        case .insertText(let text):
            executor.type(text: text)

        case .window(let action):
            executor.window(action)

        case .media(let key):
            executor.media(key)

        case .system(let action):
            executor.system(action)

        case .clipboardPush(let text):
            executor.setClipboard(text)
            send(.toast(text: "Pasted to Mac clipboard"))

        case .requestClipboard:
            send(.clipboard(text: executor.readClipboard() ?? ""))

        // MARK: Pointer & keyboard

        case .pointerMove(let dx, let dy):
            server.pointer.move(dx: dx, dy: dy)

        case .pointerClick(let button, let count):
            server.pointer.click(button, count: count)

        case .pointerScroll(let dx, let dy):
            server.pointer.scroll(dx: dx, dy: dy)

        case .pointerDrag(let down):
            server.pointer.drag(down: down)

        case .keyPress(let code, let modifiers):
            server.pointer.key(code: code, modifiers: modifiers)

        // MARK: Windows

        case .requestWindows(let bundleID):
            send(.windows(bundleID: bundleID, items: server.windows.windows(for: bundleID)))

        case .focusWindow(let id):
            server.windows.focus(id: id)

        case .windowCommand(let id, let action):
            server.windows.perform(action, on: id, executor: executor)

        // MARK: Status & levels

        case .requestStatus:
            send(.status(server.status.snapshot()))

        case .setVolume(let level):
            server.status.setVolume(level)

        case .setMuted(let muted):
            server.status.setMuted(muted)

        case .setBrightness(let level):
            server.setBrightness(level)

        // MARK: Files

        case .sendFile(let chunk):
            if let saved = server.files.receive(chunk) {
                send(.fileReceived(name: saved.name, path: saved.path))
                send(.toast(text: "Saved \(saved.name) to Downloads"))
            }

        case .requestAccessibilityPrompt:
            AXPermission.request()
            AXPermission.openSettingsPane()

        case .requestFinderSelection:
            let selection = server.files.finderSelection()
            if selection.isEmpty {
                send(.toast(text: "Nothing selected in Finder"))
            } else {
                for file in selection {
                    sendFile(name: file.name, data: file.data)
                }
            }

        default:
            break
        }
    }
}

// MARK: - What each paired device is allowed to do

/// Categories a Mac owner can switch off per device, from the menu bar panel.
enum PermissionCategory: String, CaseIterable, Identifiable {
    case launch, input, files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launch: return "Launch & switch apps"
        case .input: return "Pointer, keyboard & windows"
        case .files: return "Files & clipboard"
        }
    }

    var symbol: String {
        switch self {
        case .launch: return "square.grid.2x2"
        case .input: return "cursorarrow.rays"
        case .files: return "doc.on.doc"
        }
    }
}

final class DevicePolicy {
    static let shared = DevicePolicy()

    private let defaults = UserDefaults.standard
    private func key(_ deviceID: String, _ category: PermissionCategory) -> String {
        "policy.\(deviceID).\(category.rawValue)"
    }

    func isAllowed(_ category: PermissionCategory, for deviceID: String) -> Bool {
        defaults.object(forKey: key(deviceID, category)) as? Bool ?? true
    }

    func set(_ allowed: Bool, _ category: PermissionCategory, for deviceID: String) {
        defaults.set(allowed, forKey: key(deviceID, category))
    }

    func allows(_ message: ClientMessage, for deviceID: String) -> Bool {
        isAllowed(DevicePolicy.category(of: message), for: deviceID)
    }

    /// Read-only requests fall under the category they belong to but are always
    /// harmless, so only the acting messages are gated.
    static func category(of message: ClientMessage) -> PermissionCategory {
        switch message {
        case .launchApp, .quitApp, .hideApp, .runShortcut, .openURL:
            return .launch
        case .pointerMove, .pointerClick, .pointerScroll, .pointerDrag,
             .keyPress, .insertText, .window, .media, .system,
             .focusWindow, .windowCommand, .setVolume, .setBrightness, .setMuted:
            return .input
        case .sendFile, .requestFinderSelection, .clipboardPush, .requestClipboard:
            return .files
        default:
            return .launch
        }
    }
}

// MARK: - Paired device store

final class PairingStore {
    static let shared = PairingStore()

    private let defaults = UserDefaults.standard
    private let tokensKey = "paired.tokens"
    private let hostIDKey = "host.identifier"
    private let pinKey = "pairing.pin"

    static func makePIN() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    var pin: String {
        get {
            if let existing = defaults.string(forKey: pinKey), existing.count == 6 { return existing }
            let generated = PairingStore.makePIN()
            defaults.set(generated, forKey: pinKey)
            return generated
        }
        set { defaults.set(newValue, forKey: pinKey) }
    }

    var hostID: String {
        if let existing = defaults.string(forKey: hostIDKey) { return existing }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: hostIDKey)
        return generated
    }

    private var tokens: [String: String] {
        get { defaults.dictionary(forKey: tokensKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: tokensKey) }
    }

    func issueToken(for device: DeviceInfo) -> String {
        let token = UUID().uuidString + "-" + UUID().uuidString
        var current = tokens
        current[device.id] = token
        tokens = current
        return token
    }

    func isValid(token: String, for deviceID: String) -> Bool {
        tokens[deviceID] == token
    }

    func removeAll() {
        tokens = [:]
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

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}
