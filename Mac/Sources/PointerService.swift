//
//  PointerService.swift
//  MobileDock for Mac — turns remote gestures into pointer and keyboard events.
//

import Foundation
import AppKit
import CoreGraphics

@MainActor
final class PointerService {

    private var isDragging = false
    private let source = CGEventSource(stateID: .combinedSessionState)

    // MARK: Pointer

    func move(dx: Double, dy: Double) {
        guard AXPermission.isGranted else {
            AXPermission.request()
            return
        }
        let current = CGEvent(source: nil)?.location ?? .zero
        var next = CGPoint(x: current.x + dx, y: current.y + dy)
        next = clamp(next)

        let type: CGEventType = isDragging ? .leftMouseDragged : .mouseMoved
        let event = CGEvent(mouseEventSource: source,
                            mouseType: type,
                            mouseCursorPosition: next,
                            mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }

    func click(_ button: PointerButton, count: Int) {
        guard AXPermission.isGranted else {
            AXPermission.request()
            return
        }
        let location = CGEvent(source: nil)?.location ?? .zero
        let (down, up, cgButton): (CGEventType, CGEventType, CGMouseButton)
        switch button {
        case .left: (down, up, cgButton) = (.leftMouseDown, .leftMouseUp, .left)
        case .right: (down, up, cgButton) = (.rightMouseDown, .rightMouseUp, .right)
        case .middle: (down, up, cgButton) = (.otherMouseDown, .otherMouseUp, .center)
        }

        for step in 1...max(1, min(count, 3)) {
            let downEvent = CGEvent(mouseEventSource: source, mouseType: down,
                                    mouseCursorPosition: location, mouseButton: cgButton)
            let upEvent = CGEvent(mouseEventSource: source, mouseType: up,
                                  mouseCursorPosition: location, mouseButton: cgButton)
            downEvent?.setIntegerValueField(.mouseEventClickState, value: Int64(step))
            upEvent?.setIntegerValueField(.mouseEventClickState, value: Int64(step))
            downEvent?.post(tap: .cghidEventTap)
            upEvent?.post(tap: .cghidEventTap)
            if step < count { usleep(40_000) }
        }
    }

    func scroll(dx: Double, dy: Double) {
        guard AXPermission.isGranted else { return }
        let event = CGEvent(scrollWheelEvent2Source: source,
                            units: .pixel,
                            wheelCount: 2,
                            wheel1: Int32(dy.rounded()),
                            wheel2: Int32(dx.rounded()),
                            wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    /// Press-and-hold so a drag can be carried out with a second finger.
    func drag(down: Bool) {
        guard AXPermission.isGranted else { return }
        let location = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType = down ? .leftMouseDown : .leftMouseUp
        let event = CGEvent(mouseEventSource: source, mouseType: type,
                            mouseCursorPosition: location, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
        isDragging = down
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        // Keep the pointer on whichever display it is closest to.
        let frames = NSScreen.screens.map { screen -> CGRect in
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            return CGRect(x: screen.frame.minX,
                          y: primaryHeight - screen.frame.maxY,
                          width: screen.frame.width,
                          height: screen.frame.height)
        }
        if frames.contains(where: { $0.contains(point) }) { return point }
        guard let nearest = frames.min(by: { distance($0, point) < distance($1, point) }) else { return point }
        return CGPoint(x: min(max(point.x, nearest.minX + 1), nearest.maxX - 1),
                       y: min(max(point.y, nearest.minY + 1), nearest.maxY - 1))
    }

    private func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    // MARK: Keyboard

    func key(code: Int, modifiers: [String]) {
        guard AXPermission.isGranted else {
            AXPermission.request()
            return
        }
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command", "cmd": flags.insert(.maskCommand)
            case "option", "alt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            case "control", "ctrl": flags.insert(.maskControl)
            case "function", "fn": flags.insert(.maskSecondaryFn)
            default: break
            }
        }
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
