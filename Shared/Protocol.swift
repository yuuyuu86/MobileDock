//
//  Protocol.swift
//  MobileDock — shared wire protocol between the Mac host and the iOS/iPadOS remote.
//

import Foundation

public enum MobileDock {
    /// Bonjour service advertised by the Mac host.
    public static let serviceType = "_mobiledock._tcp"
    public static let serviceDomain = "local."
    /// Bumped whenever the wire format changes in an incompatible way.
    public static let protocolVersion = 4
    public static let defaultPort: UInt16 = 53_411
    public static let maxFrameBytes = 8 * 1024 * 1024
}

// MARK: - Peer descriptions

public struct DeviceInfo: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var model: String
    public var isPad: Bool

    public init(id: String, name: String, model: String, isPad: Bool) {
        self.id = id
        self.name = name
        self.model = model
        self.isPad = isPad
    }
}

public struct HostInfo: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var model: String
    public var version: String

    public init(id: String, name: String, model: String, version: String) {
        self.id = id
        self.name = name
        self.model = model
        self.version = version
    }
}

// MARK: - Catalog

public struct AppInfo: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var path: String
    public var isRunning: Bool

    public init(bundleID: String, name: String, path: String, isRunning: Bool) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.isRunning = isRunning
    }
}

public struct ShortcutInfo: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String

    public init(name: String) { self.name = name }
}

public struct Catalog: Codable, Hashable, Sendable {
    public var host: HostInfo
    public var apps: [AppInfo]
    public var shortcuts: [ShortcutInfo]
    public var running: [String]
    public var recents: [String]
    public var frontApp: String?
    public var accessibilityGranted: Bool

    public init(host: HostInfo,
                apps: [AppInfo],
                shortcuts: [ShortcutInfo],
                running: [String],
                recents: [String],
                frontApp: String?,
                accessibilityGranted: Bool) {
        self.host = host
        self.apps = apps
        self.shortcuts = shortcuts
        self.running = running
        self.recents = recents
        self.frontApp = frontApp
        self.accessibilityGranted = accessibilityGranted
    }
}

public struct IconPayload: Codable, Hashable, Sendable {
    public var bundleID: String
    /// PNG bytes, 128×128.
    public var png: Data

    public init(bundleID: String, png: Data) {
        self.bundleID = bundleID
        self.png = png
    }
}

// MARK: - Actions

/// Things done to the front window, or to the arrangement of windows and spaces.
public enum WindowAction: String, Codable, Sendable {
    case minimize
    case maximize
    case fullscreen
    case hide
    case closeWindow
    case nextWindow
    // Snap the front window to a region of its screen.
    case tileLeft
    case tileRight
    case tileTop
    case tileBottom
    case center
    // Spaces and app switching.
    case missionControl
    case appExpose
    case showDesktop
    case spaceLeft
    case spaceRight
    case nextApp
    case previousApp
}

public enum MediaKey: String, Codable, Sendable {
    case playPause, next, previous, volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown
    case keyboardLightUp, keyboardLightDown
}

/// System-wide shortcuts and the standard edit menu, sent to whatever is focused.
public enum SystemAction: String, Codable, Sendable {
    // Launching and finding
    case spotlight, launchpad, emojiPicker, forceQuit
    // Session
    case lockScreen, sleepDisplay
    // Screenshots
    case screenshotRegion, screenshotScreen, screenshotTools
    // Edit menu
    case copy, paste, cut, undo, redo, selectAll, save, find
    // Documents, tabs and windows
    case newTab, closeTab, nextTab, previousTab, reopenTab, newWindow, refresh
    case zoomIn, zoomOut, quitApp
}

// MARK: - Pointer & keyboard

public enum PointerButton: String, Codable, Sendable {
    case left, right, middle
}

/// One window of a running app, as seen through the Accessibility API.
public struct WindowSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var bundleID: String
    public var isMinimized: Bool
    public var isFocused: Bool

    public init(id: String, title: String, bundleID: String, isMinimized: Bool, isFocused: Bool) {
        self.id = id
        self.title = title
        self.bundleID = bundleID
        self.isMinimized = isMinimized
        self.isFocused = isFocused
    }
}

// MARK: - Mac status

public struct NowPlaying: Codable, Hashable, Sendable {
    public var title: String
    public var artist: String
    public var app: String
    public var isPlaying: Bool

    public init(title: String, artist: String, app: String, isPlaying: Bool) {
        self.title = title
        self.artist = artist
        self.app = app
        self.isPlaying = isPlaying
    }
}

public struct MacStatus: Codable, Hashable, Sendable {
    public var batteryPercent: Int?
    public var isCharging: Bool
    public var cpuPercent: Double
    public var memoryUsedGB: Double
    public var memoryTotalGB: Double
    public var diskFreeGB: Double
    public var volume: Double
    public var isMuted: Bool
    public var brightness: Double
    public var networkName: String?
    public var uptime: String
    public var nowPlaying: NowPlaying?

    public init(batteryPercent: Int?,
                isCharging: Bool,
                cpuPercent: Double,
                memoryUsedGB: Double,
                memoryTotalGB: Double,
                diskFreeGB: Double,
                volume: Double,
                isMuted: Bool,
                brightness: Double,
                networkName: String?,
                uptime: String,
                nowPlaying: NowPlaying?) {
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.cpuPercent = cpuPercent
        self.memoryUsedGB = memoryUsedGB
        self.memoryTotalGB = memoryTotalGB
        self.diskFreeGB = diskFreeGB
        self.volume = volume
        self.isMuted = isMuted
        self.brightness = brightness
        self.networkName = networkName
        self.uptime = uptime
        self.nowPlaying = nowPlaying
    }
}

// MARK: - File transfer

public struct FileChunk: Codable, Sendable {
    public var transferID: String
    public var name: String
    public var index: Int
    public var total: Int
    public var data: Data

    public init(transferID: String, name: String, index: Int, total: Int, data: Data) {
        self.transferID = transferID
        self.name = name
        self.index = index
        self.total = total
        self.data = data
    }
}

// MARK: - Messages

public enum ClientMessage: Codable, Sendable {
    case hello(version: Int, device: DeviceInfo)
    case pair(pin: String, device: DeviceInfo)
    case authenticate(token: String, device: DeviceInfo)
    case requestCatalog
    case requestIcons(bundleIDs: [String])
    case launchApp(bundleID: String)
    case quitApp(bundleID: String)
    case hideApp(bundleID: String)
    case runShortcut(name: String)
    case openURL(url: String)
    case insertText(text: String)
    case window(action: WindowAction)
    case media(key: MediaKey)
    case system(action: SystemAction)
    case clipboardPush(text: String)
    case requestClipboard
    case ping

    // Pointer control
    case pointerMove(dx: Double, dy: Double)
    case pointerClick(button: PointerButton, count: Int)
    case pointerScroll(dx: Double, dy: Double)
    case pointerDrag(down: Bool)

    // Keyboard control: a virtual key code plus modifier names.
    case keyPress(code: Int, modifiers: [String])

    // Windows
    case requestWindows(bundleID: String)
    case focusWindow(id: String)
    case windowCommand(id: String, action: WindowAction)

    // Status and levels
    case requestStatus
    case setVolume(level: Double)
    case setBrightness(level: Double)
    case setMuted(Bool)

    // Files
    case sendFile(chunk: FileChunk)
    case requestFinderSelection

    /// Ask the Mac to raise the Accessibility permission prompt.
    case requestAccessibilityPrompt
}

public enum ServerMessage: Codable, Sendable {
    case hello(version: Int, host: HostInfo, requiresPairing: Bool)
    case pairResult(success: Bool, token: String?, host: HostInfo?, message: String?)
    case catalog(Catalog)
    case icons(items: [IconPayload])
    case frontApp(bundleID: String?, recents: [String], running: [String])
    case clipboard(text: String)
    case toast(text: String)
    case failure(reason: String)
    case pong

    case windows(bundleID: String, items: [WindowSummary])
    case status(MacStatus)
    case fileChunk(FileChunk)
    case fileReceived(name: String, path: String)
    /// The host refused an action because this device is not allowed to do it.
    case notPermitted(what: String)
}

// MARK: - Coding helpers

public enum WireCoder {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dataEncodingStrategy = .base64
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dataDecodingStrategy = .base64
        return d
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let body = try encoder.encode(value)
        var frame = Data(capacity: body.count + 4)
        var length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(body)
        return frame
    }
}

/// Accumulates bytes off the socket and yields whole JSON frames.
public final class FrameParser {
    private var buffer = Data()

    public init() {}

    public func append(_ data: Data) { buffer.append(data) }

    /// Returns the next complete frame body, or nil when more bytes are needed.
    public func next() throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        guard length <= UInt32(MobileDock.maxFrameBytes) else {
            throw WireError.frameTooLarge(Int(length))
        }
        let total = 4 + Int(length)
        guard buffer.count >= total else { return nil }
        let body = buffer.subdata(in: 4..<total)
        buffer.removeSubrange(0..<total)
        return body
    }
}

public enum WireError: LocalizedError {
    case frameTooLarge(Int)
    case notConnected
    case handshakeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .frameTooLarge(let n): return "Frame of \(n) bytes exceeds the limit."
        case .notConnected: return "Not connected to a Mac."
        case .handshakeFailed(let reason): return reason
        }
    }
}
