//
//  TileView.swift
//  MobileDock for iOS — one moulded tile on the home board, with its gestures.
//

import SwiftUI

struct TileView: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: DockStore

    let tile: Tile
    var size: CGFloat = 76

    @State private var pressed = false
    @State private var dragOffset: CGSize = .zero
    @State private var showEditor = false
    @State private var showWindows = false

    private var radius: CGFloat { size * 0.2 }

    private var isRunning: Bool {
        tile.kind == .app && client.running.contains(tile.payload)
    }

    private var isFront: Bool {
        tile.kind == .app && client.frontApp == tile.payload
    }

    /// Apps keep a white plate so their own icon reads; everything else takes its tint.
    private var faceColor: Color {
        switch tile.kind {
        case .app: return DockTheme.panel
        default: return tile.color
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DockTheme.face(faceColor))
                    .overlay(GlossOverlay(cornerRadius: radius))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(DockTheme.bevel.opacity(0.6), lineWidth: 0.9)
                    )
                    .shadow(color: .black.opacity(pressed ? 0.10 : 0.22),
                            radius: pressed ? 3 : 7,
                            y: pressed ? 1 : 4)

                content

                if isRunning {
                    runningBadge
                }

                if store.isEditing {
                    removeBadge
                }
            }
            .frame(width: size, height: size)
            .overlay {
                if isFront {
                    SelectionCursor(cornerRadius: radius)
                }
            }
            .scaleEffect(pressed ? 0.94 : 1)
            .offset(dragOffset)
            .rotationEffect(.degrees(store.isEditing ? wiggle : 0))
            .animation(.spring(response: 0.26, dampingFraction: 0.6), value: pressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragOffset)

            Text(tile.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DockTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: size + 14)
                .shadow(color: .white.opacity(0.8), radius: 0.5, y: 0.5)
        }
        .contentShape(Rectangle())
        // Edit mode hands the tile over to drag-and-drop reordering, so the
        // swipe vocabulary steps aside and a tap opens the editor instead.
        .gesture(tileGesture, including: store.isEditing ? .subviews : .all)
        .onTapGesture {
            guard store.isEditing else { return }
            Haptics.tap()
            showEditor = true
        }
        .contextMenu { contextMenu }
        .sheet(isPresented: $showEditor) {
            TileEditorView(tile: tile)
                .environmentObject(store)
        }
        .sheet(isPresented: $showWindows) {
            WindowListView(bundleID: tile.payload, appName: tile.title)
                .environmentObject(client)
        }
    }

    private var wiggle: Double {
        // Deterministic per-tile phase so the whole page doesn't wobble in lockstep.
        (Double(abs(tile.id.hashValue % 2)) * 2 - 1) * 1.4
    }

    @ViewBuilder
    private var content: some View {
        if tile.kind == .app, let icon = client.icons[tile.payload] {
            Image(uiImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size * 0.66, height: size * 0.66)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        } else if tile.kind == .emoji {
            // The emoji itself is the payload it types, so it is content, not an icon.
            Text(tile.payload)
                .font(.system(size: size * 0.42))
        } else {
            Image(systemName: tile.resolvedSymbol)
                .font(.system(size: size * 0.33, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
        }
    }

    private var runningBadge: some View {
        VStack {
            HStack {
                Spacer()
                Circle()
                    .fill(DockTheme.mint)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.2))
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
            Spacer()
        }
        .padding(5)
    }

    private var removeBadge: some View {
        VStack {
            HStack {
                Button {
                    Haptics.firm()
                    store.remove(tile)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(DockTheme.face(DockTheme.danger))
                                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.2))
                                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Spacer()
        }
        .padding(-6)
    }

    // MARK: Gestures

    private var tileGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressed { pressed = true }
                guard !store.isEditing else { return }
                // Vertical flick previews the window gesture it will fire.
                if abs(value.translation.height) > abs(value.translation.width) {
                    dragOffset = CGSize(width: 0, height: max(-40, min(40, value.translation.height)))
                }
            }
            .onEnded { value in
                pressed = false
                let vertical = value.translation.height
                dragOffset = .zero

                if vertical < -34 {
                    Haptics.firm()
                    activateThen(.window(action: .maximize))
                } else if vertical > 34 {
                    Haptics.firm()
                    activateThen(.window(action: .minimize))
                } else if abs(vertical) < 14 && abs(value.translation.width) < 14 {
                    Haptics.tap()
                    trigger()
                }
            }
    }

    /// Bring the app forward first so the window gesture lands on the right app.
    private func activateThen(_ message: ClientMessage) {
        if tile.kind == .app {
            client.send(.launchApp(bundleID: tile.payload))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                client.send(message)
            }
        } else {
            client.send(message)
        }
    }

    private func trigger() {
        switch tile.kind {
        case .app:
            client.send(.launchApp(bundleID: tile.payload))
        case .shortcut:
            client.send(.runShortcut(name: tile.payload))
        case .website:
            client.send(.openURL(url: tile.payload))
        case .emoji:
            client.send(.insertText(text: tile.payload))
        case .control:
            if tile.payload.hasPrefix("media."),
               let key = MediaKey(rawValue: String(tile.payload.dropFirst("media.".count))) {
                client.send(.media(key: key))
            } else if tile.payload.hasPrefix("system."),
                      let action = SystemAction(rawValue: String(tile.payload.dropFirst("system.".count))) {
                client.send(.system(action: action))
            } else if let action = WindowAction(rawValue: tile.payload) {
                client.send(.window(action: action))
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if tile.kind == .app {
            Button("Bring to front", systemImage: "arrow.up.left.and.arrow.down.right") {
                client.send(.launchApp(bundleID: tile.payload))
            }
            Button("Windows…", systemImage: "macwindow.on.rectangle") {
                client.send(.requestWindows(bundleID: tile.payload))
                showWindows = true
            }
            Button("Hide", systemImage: "eye.slash") {
                client.send(.hideApp(bundleID: tile.payload))
            }
            Button("Quit", systemImage: "xmark.circle", role: .destructive) {
                client.send(.quitApp(bundleID: tile.payload))
            }
            Divider()
        }
        Button("Edit tile", systemImage: "pencil") { showEditor = true }
        Button("Remove", systemImage: "trash", role: .destructive) { store.remove(tile) }
    }
}
