//
//  WindowService.swift
//  MobileDock for Mac — lists and drives individual windows of an app.
//

import Foundation
import AppKit
import ApplicationServices

@MainActor
final class WindowService {

    /// Live AX references, keyed by the id handed to the remote.
    private var handles: [String: AXUIElement] = [:]

    func windows(for bundleID: String) -> [WindowSummary] {
        guard AXPermission.isGranted else { return [] }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return []
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)

        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &raw) == .success,
              let list = raw as? [AXUIElement] else { return [] }

        var focused: AXUIElement?
        var focusedRaw: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focusedRaw) == .success {
            focused = focusedRaw as! AXUIElement?
        }

        // Drop stale handles for this app before handing out fresh ones.
        handles = handles.filter { !$0.key.hasPrefix(bundleID + "#") }

        return list.enumerated().map { index, window in
            let id = "\(bundleID)#\(index)"
            handles[id] = window
            return WindowSummary(id: id,
                                 title: string(from: window, attribute: kAXTitleAttribute) ?? "Untitled",
                                 bundleID: bundleID,
                                 isMinimized: bool(from: window, attribute: kAXMinimizedAttribute),
                                 isFocused: focused.map { CFEqual($0, window) } ?? false)
        }
    }

    func focus(id: String) {
        guard let window = handles[id] else { return }
        let bundleID = String(id.split(separator: "#").first ?? "")
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFBoolean)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFBoolean)
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.activate(options: [.activateAllWindows])
    }

    func perform(_ action: WindowAction, on id: String, executor: ActionExecutor) {
        guard let window = handles[id] else { return }
        switch action {
        case .minimize:
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFBoolean)
        case .closeWindow:
            press(window, button: kAXCloseButtonAttribute)
        case .maximize:
            press(window, button: kAXZoomButtonAttribute)
        case .fullscreen:
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, true as CFBoolean)
        default:
            // Tiling and the rest act on the front window, so raise this one first.
            focus(id: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                executor.window(action)
            }
        }
    }

    // MARK: Attribute helpers

    private func string(from element: AXUIElement, attribute: String) -> String? {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }

    private func bool(from element: AXUIElement, attribute: String) -> Bool {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return false }
        return (raw as? Bool) ?? false
    }

    private func press(_ window: AXUIElement, button attribute: String) {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &raw) == .success,
              let element = raw as! AXUIElement? else { return }
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}
