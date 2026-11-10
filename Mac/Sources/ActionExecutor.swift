//
//  ActionExecutor.swift
//  MobileDock for Mac — turns remote messages into real actions on the Mac.
//

import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum AXPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that deep-links into Privacy & Security.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettingsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class ActionExecutor: ObservableObject {

    @Published var lastAction: String?

    // MARK: Apps

    func launch(bundleID: String) {
        note("Launch \(bundleID)")
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            // Already open: toggle between activating and hiding, like a Dock click.
            if running.isActive {
                running.hide()
            } else {
                running.unhide()
                running.activate(options: [.activateAllWindows])
            }
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    func activate(bundleID: String) {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            launch(bundleID: bundleID)
            return
        }
        running.unhide()
        running.activate(options: [.activateAllWindows])
    }

    func quit(bundleID: String) {
        note("Quit \(bundleID)")
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
    }

    func hide(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.hide() }
    }

    // MARK: Shortcuts & links

    func runShortcut(named name: String) {
        note("Shortcut \(name)")
        Task.detached(priority: .userInitiated) {
            Shell.run("/usr/bin/shortcuts", ["run", name], capture: false)
        }
    }

    func open(urlString: String) {
        var candidate = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.contains("://") { candidate = "https://" + candidate }
        guard let url = URL(string: candidate) else { return }
        note("Open \(candidate)")
        NSWorkspace.shared.open(url)
    }

    // MARK: Text & emoji injection

    /// Types text into whatever has keyboard focus, without touching the clipboard.
    func type(text: String) {
        guard !text.isEmpty else { return }
        guard AXPermission.isGranted else {
            AXPermission.request()
            return
        }
        note("Insert \(text)")
        let source = CGEventSource(stateID: .combinedSessionState)
        // Unicode payloads go in chunks: the event API takes a bounded UTF-16 buffer.
        for chunk in Array(text.utf16).chunked(into: 20) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            var buffer = chunk
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(1_500)
        }
    }

    // MARK: Clipboard

    func setClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        note("Clipboard ← remote")
    }

    func readClipboard() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    // MARK: Window management

    func window(_ action: WindowAction) {
        guard AXPermission.isGranted else {
            AXPermission.request()
            return
        }
        note("Window \(action.rawValue)")
        switch action {
        case .minimize:
            setFrontWindowAttribute(kAXMinimizedAttribute, value: true)
        case .maximize:
            zoomFrontWindow()
        case .fullscreen:
            setFrontWindowAttribute("AXFullScreen", value: true)
        case .closeWindow:
            pressFrontWindowButton(kAXCloseButtonAttribute)
        case .hide:
            NSWorkspace.shared.frontmostApplication?.hide()
        case .nextWindow:
            key(code: CGKeyCode(kVK_ANSI_Grave), flags: .maskCommand)
        case .tileLeft, .tileRight, .tileTop, .tileBottom, .center:
            tile(action)
        case .missionControl:
            key(code: CGKeyCode(kVK_UpArrow), flags: .maskControl)
        case .appExpose:
            key(code: CGKeyCode(kVK_DownArrow), flags: .maskControl)
        case .showDesktop:
            key(code: CGKeyCode(kVK_F11))
        case .spaceLeft:
            key(code: CGKeyCode(kVK_LeftArrow), flags: .maskControl)
        case .spaceRight:
            key(code: CGKeyCode(kVK_RightArrow), flags: .maskControl)
        case .nextApp:
            key(code: CGKeyCode(kVK_Tab), flags: .maskCommand)
        case .previousApp:
            key(code: CGKeyCode(kVK_Tab), flags: [.maskCommand, .maskShift])
        }
    }

    // MARK: Window tiling

    /// Snaps the front window to part of the screen it currently sits on.
    private func tile(_ action: WindowAction) {
        guard let window = frontWindowElement() else { return }
        let area = visibleArea(for: window)
        let frame: CGRect
        switch action {
        case .tileLeft:
            frame = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        case .tileRight:
            frame = CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
        case .tileTop:
            frame = CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height / 2)
        case .tileBottom:
            frame = CGRect(x: area.minX, y: area.midY, width: area.width, height: area.height / 2)
        case .center:
            let size = CGSize(width: area.width * 0.72, height: area.height * 0.82)
            frame = CGRect(x: area.midX - size.width / 2,
                           y: area.midY - size.height / 2,
                           width: size.width,
                           height: size.height)
        default:
            return
        }
        set(frame: frame, on: window)
    }

    private func set(frame: CGRect, on window: AXUIElement) {
        var origin = frame.origin
        var size = frame.size
        // Size first, then position, so a window that refuses to shrink still lands right.
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }

    /// The window's screen, expressed in Accessibility coordinates (top-left origin,
    /// menu bar and Dock excluded).
    private func visibleArea(for window: AXUIElement) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screen = screenContaining(window) ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return CGRect(x: visible.minX,
                      y: primaryHeight - visible.maxY,
                      width: visible.width,
                      height: visible.height)
    }

    private func screenContaining(_ window: AXUIElement) -> NSScreen? {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &raw) == .success,
              let value = raw, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = CGPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.first { $0.frame.contains(flipped) }
    }

    // MARK: System shortcuts

    func system(_ action: SystemAction) {
        guard AXPermission.isGranted else {
            AXPermission.request()
            return
        }
        note("System \(action.rawValue)")

        switch action {
        case .spotlight:
            key(code: CGKeyCode(kVK_Space), flags: .maskCommand)
        case .launchpad:
            openLaunchpad()
        case .emojiPicker:
            key(code: CGKeyCode(kVK_Space), flags: [.maskCommand, .maskControl])
        case .forceQuit:
            key(code: CGKeyCode(kVK_Escape), flags: [.maskCommand, .maskAlternate])

        case .lockScreen:
            key(code: CGKeyCode(kVK_ANSI_Q), flags: [.maskCommand, .maskControl])
        case .sleepDisplay:
            Task.detached { Shell.run("/usr/bin/pmset", ["displaysleepnow"], capture: false) }

        case .screenshotRegion:
            key(code: CGKeyCode(kVK_ANSI_4), flags: [.maskCommand, .maskShift])
        case .screenshotScreen:
            key(code: CGKeyCode(kVK_ANSI_3), flags: [.maskCommand, .maskShift])
        case .screenshotTools:
            key(code: CGKeyCode(kVK_ANSI_5), flags: [.maskCommand, .maskShift])

        case .copy:      key(code: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        case .paste:     key(code: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        case .cut:       key(code: CGKeyCode(kVK_ANSI_X), flags: .maskCommand)
        case .undo:      key(code: CGKeyCode(kVK_ANSI_Z), flags: .maskCommand)
        case .redo:      key(code: CGKeyCode(kVK_ANSI_Z), flags: [.maskCommand, .maskShift])
        case .selectAll: key(code: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        case .save:      key(code: CGKeyCode(kVK_ANSI_S), flags: .maskCommand)
        case .find:      key(code: CGKeyCode(kVK_ANSI_F), flags: .maskCommand)

        case .newTab:      key(code: CGKeyCode(kVK_ANSI_T), flags: .maskCommand)
        case .closeTab:    key(code: CGKeyCode(kVK_ANSI_W), flags: .maskCommand)
        case .nextTab:     key(code: CGKeyCode(kVK_Tab), flags: .maskControl)
        case .previousTab: key(code: CGKeyCode(kVK_Tab), flags: [.maskControl, .maskShift])
        case .reopenTab:   key(code: CGKeyCode(kVK_ANSI_T), flags: [.maskCommand, .maskShift])
        case .newWindow:   key(code: CGKeyCode(kVK_ANSI_N), flags: .maskCommand)
        case .refresh:     key(code: CGKeyCode(kVK_ANSI_R), flags: .maskCommand)
        case .zoomIn:      key(code: CGKeyCode(kVK_ANSI_Equal), flags: .maskCommand)
        case .zoomOut:     key(code: CGKeyCode(kVK_ANSI_Minus), flags: .maskCommand)
        case .quitApp:     key(code: CGKeyCode(kVK_ANSI_Q), flags: .maskCommand)
        }
    }

    private func openLaunchpad() {
        let candidates = ["/System/Applications/Launchpad.app", "/Applications/Launchpad.app"]
        if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            // Newer macOS folds Launchpad into the Apps view behind Spotlight.
            key(code: CGKeyCode(kVK_Space), flags: .maskCommand)
        }
    }

    private func frontWindowElement() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var window: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success else { return nil }
        // AXUIElementRef is toll-free-bridged through AnyObject here.
        return (window as! AXUIElement?)
    }

    private func setFrontWindowAttribute(_ attribute: String, value: Bool) {
        guard let window = frontWindowElement() else { return }
        AXUIElementSetAttributeValue(window, attribute as CFString, value as CFBoolean)
    }

    private func pressFrontWindowButton(_ attribute: String) {
        guard let window = frontWindowElement() else { return }
        var button: AnyObject?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &button) == .success,
              let element = button as! AXUIElement? else { return }
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    /// The green button toggles zoom; AX exposes it as the zoom button press.
    private func zoomFrontWindow() {
        pressFrontWindowButton(kAXZoomButtonAttribute)
    }

    private func key(code: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Media keys

    func media(_ key: MediaKey) {
        note("Media \(key.rawValue)")
        switch key {
        case .playPause: postSystemKey(NX_KEYTYPE_PLAY)
        case .next: postSystemKey(NX_KEYTYPE_NEXT)
        case .previous: postSystemKey(NX_KEYTYPE_PREVIOUS)
        case .volumeUp: postSystemKey(NX_KEYTYPE_SOUND_UP)
        case .volumeDown: postSystemKey(NX_KEYTYPE_SOUND_DOWN)
        case .mute: postSystemKey(NX_KEYTYPE_MUTE)
        case .brightnessUp: postSystemKey(NX_KEYTYPE_BRIGHTNESS_UP)
        case .brightnessDown: postSystemKey(NX_KEYTYPE_BRIGHTNESS_DOWN)
        case .keyboardLightUp: postSystemKey(NX_KEYTYPE_ILLUMINATION_UP)
        case .keyboardLightDown: postSystemKey(NX_KEYTYPE_ILLUMINATION_DOWN)
        }
    }

    private func postSystemKey(_ keyCode: Int32) {
        func post(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((keyCode << 16) | ((down ? 0xa : 0xb) << 8))
            guard let event = NSEvent.otherEvent(with: .systemDefined,
                                                 location: .zero,
                                                 modifierFlags: flags,
                                                 timestamp: 0,
                                                 windowNumber: 0,
                                                 context: nil,
                                                 subtype: 8,
                                                 data1: data1,
                                                 data2: -1) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    private func note(_ text: String) {
        lastAction = text
    }
}
