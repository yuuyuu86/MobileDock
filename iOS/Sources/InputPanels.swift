//
//  InputPanels.swift
//  MobileDock for iOS — the trackpad and the keyboard.
//

import SwiftUI
import UIKit

// MARK: - Trackpad

struct TrackpadPanel: View {
    @EnvironmentObject private var client: DockClient
    @AppStorage("pointer.speed") private var speed: Double = 1.6
    @AppStorage("pointer.natural") private var naturalScroll = true
    @State private var dragLocked = false

    var body: some View {
        VStack(spacing: 12) {
            AccessibilityNotice()

            TrackpadSurface(speed: speed,
                            naturalScroll: naturalScroll,
                            onMove: { dx, dy in client.send(.pointerMove(dx: dx, dy: dy)) },
                            onScroll: { dx, dy in client.send(.pointerScroll(dx: dx, dy: dy)) },
                            onClick: { button, count in
                                Haptics.tap()
                                client.send(.pointerClick(button: button, count: count))
                            },
                            onDrag: { down in
                                Haptics.firm()
                                client.send(.pointerDrag(down: down))
                            })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .plate(cornerRadius: 20)
                .overlay(alignment: .top) {
                    Text("Drag to move · Tap to click · Two fingers to scroll")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DockTheme.subtext)
                        .padding(.top, 10)
                }

            HStack(spacing: 10) {
                padButton("Left click", systemImage: "cursorarrow.click") {
                    Haptics.tap()
                    client.send(.pointerClick(button: .left, count: 1))
                }
                padButton("Right click", systemImage: "cursorarrow.click.badge.clock") {
                    Haptics.tap()
                    client.send(.pointerClick(button: .right, count: 1))
                }
                padButton(dragLocked ? "Drop" : "Drag", systemImage: "hand.draw", active: dragLocked) {
                    dragLocked.toggle()
                    Haptics.firm()
                    client.send(.pointerDrag(down: dragLocked))
                }
            }

            HStack(spacing: 14) {
                Label("Speed", systemImage: "speedometer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DockTheme.subtext)
                Slider(value: $speed, in: 0.6...3.0)
                Toggle("Natural", isOn: $naturalScroll)
                    .font(.system(size: 11, weight: .semibold))
                    .toggleStyle(.switch)
                    .fixedSize()
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
    }

    private func padButton(_ title: LocalizedStringKey, systemImage: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(active ? .white : DockTheme.subtext)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .plate(cornerRadius: 14, fill: active ? DockTheme.accent : DockTheme.panel)
        }
        .buttonStyle(.plain)
    }
}

/// UIKit does the heavy lifting here: SwiftUI gestures cannot tell one finger
/// from two, which is exactly the distinction a trackpad needs.
struct TrackpadSurface: UIViewRepresentable {
    let speed: Double
    let naturalScroll: Bool
    let onMove: (Double, Double) -> Void
    let onScroll: (Double, Double) -> Void
    let onClick: (PointerButton, Int) -> Void
    let onDrag: (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        view.addGestureRecognizer(doubleTap)

        let twoFingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSecondaryTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerTap)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        view.addGestureRecognizer(longPress)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: TrackpadSurface
        private var lastTranslation: CGPoint = .zero

        init(parent: TrackpadSurface) { self.parent = parent }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            let delta = CGPoint(x: translation.x - lastTranslation.x,
                                y: translation.y - lastTranslation.y)
            lastTranslation = translation

            switch gesture.state {
            case .began:
                lastTranslation = translation
            case .changed:
                if gesture.numberOfTouches >= 2 {
                    let sign: Double = parent.naturalScroll ? 1 : -1
                    parent.onScroll(Double(delta.x) * sign, Double(delta.y) * sign)
                } else {
                    parent.onMove(Double(delta.x) * parent.speed, Double(delta.y) * parent.speed)
                }
            case .ended, .cancelled, .failed:
                lastTranslation = .zero
            default:
                break
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onClick(.left, 1)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            parent.onClick(.left, 2)
        }

        @objc func handleSecondaryTap(_ gesture: UITapGestureRecognizer) {
            parent.onClick(.right, 1)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began: parent.onDrag(true)
            case .ended, .cancelled, .failed: parent.onDrag(false)
            default: break
            }
        }
    }
}

// MARK: - Keyboard

struct KeyboardPanel: View {
    @EnvironmentObject private var client: DockClient

    @State private var draft = ""
    @State private var modifiers: Set<String> = []
    @FocusState private var focused: Bool

    /// Virtual key codes for the keys a phone keyboard cannot produce.
    private let specials: [(String, String, Int)] = [
        ("esc", "escape", 53),
        ("tab", "arrow.right.to.line", 48),
        ("return", "return", 36),
        ("delete", "delete.left", 51),
        ("↑", "arrow.up", 126),
        ("↓", "arrow.down", 125),
        ("←", "arrow.left", 123),
        ("→", "arrow.right", 124),
        ("space", "space", 49),
        ("home", "arrow.up.to.line", 115),
        ("end", "arrow.down.to.line", 119),
        ("⌫ fwd", "delete.right", 117)
    ]

    private let modifierKeys = ["command", "option", "shift", "control"]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AccessibilityNotice()

                VStack(alignment: .leading, spacing: 8) {
                    Text("TYPE ON THE MAC")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(DockTheme.subtext)

                    TextField("Type here — every keystroke lands on the Mac", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .plate(cornerRadius: 14)
                        .onChange(of: draft) { old, new in
                            stream(from: old, to: new)
                        }
                        .onSubmit { press(code: 36) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("MODIFIERS")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(DockTheme.subtext)
                    HStack(spacing: 8) {
                        ForEach(modifierKeys, id: \.self) { key in
                            Button {
                                Haptics.tap()
                                if modifiers.contains(key) { modifiers.remove(key) } else { modifiers.insert(key) }
                            } label: {
                                Text(symbol(for: key))
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(modifiers.contains(key) ? .white : DockTheme.subtext)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .plate(cornerRadius: 12,
                                           fill: modifiers.contains(key) ? DockTheme.accent : DockTheme.panel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("KEYS")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(DockTheme.subtext)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(specials, id: \.2) { item in
                            Button {
                                press(code: item.2)
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: item.1).font(.system(size: 14, weight: .semibold))
                                    Text(item.0).font(.system(size: 9, weight: .medium))
                                }
                                .foregroundStyle(DockTheme.subtext)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .plate(cornerRadius: 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("Modifiers stay on until you tap them again, so ⌘ + a key combination works.")
                    .font(.system(size: 11))
                    .foregroundStyle(DockTheme.subtext)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .onAppear { focused = true }
    }

    private func symbol(for key: String) -> String {
        switch key {
        case "command": return "⌘"
        case "option": return "⌥"
        case "shift": return "⇧"
        case "control": return "⌃"
        default: return key
        }
    }

    /// Sends only what changed, so holding a modifier and typing behaves.
    private func stream(from old: String, to new: String) {
        guard new.count > old.count, new.hasPrefix(old) else {
            if new.count < old.count { press(code: 51) }   // backspace
            return
        }
        let added = String(new.dropFirst(old.count))
        client.send(.insertText(text: added))
    }

    private func press(code: Int) {
        Haptics.tap()
        client.send(.keyPress(code: code, modifiers: Array(modifiers)))
    }
}
