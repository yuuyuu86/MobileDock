//
//  Panels.swift
//  MobileDock for iOS — the recents timeline, the emoji bar and the clipboard bridge.
//

import SwiftUI
import UIKit

// MARK: - Recents

struct RecentsPanel: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: DockStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { proxy in
            let metrics = BoardMetrics(width: proxy.size.width,
                                       height: proxy.size.height,
                                       regular: sizeClass == .regular,
                                       arrowMargins: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("RUNNING NOW", subtitle: "Tap to switch, swipe up to zoom, down to minimize")

                    LazyVGrid(columns: metrics.columns, spacing: 18) {
                        ForEach(orderedRunning, id: \.self) { bundleID in
                            TileView(tile: tile(for: bundleID), size: metrics.tileSize)
                        }
                    }

                    if !earlier.isEmpty {
                        sectionTitle("EARLIER", subtitle: "Your app timeline, newest first")
                        LazyVGrid(columns: metrics.columns, spacing: 18) {
                            ForEach(earlier, id: \.self) { bundleID in
                                TileView(tile: tile(for: bundleID), size: metrics.tileSize)
                            }
                        }
                    }

                    if orderedRunning.isEmpty && client.recents.isEmpty {
                        Text("Switch between a few apps on your Mac and they will show up here.")
                            .font(.system(size: 13))
                            .foregroundStyle(DockTheme.subtext)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
        }
    }

    private var orderedRunning: [String] {
        let running = client.running
        let ordered = client.recents.filter { running.contains($0) }
        let rest = running.subtracting(ordered).sorted { client.appName(for: $0) < client.appName(for: $1) }
        return ordered + rest
    }

    private var earlier: [String] {
        client.recents.filter { !client.running.contains($0) }
    }

    private func tile(for bundleID: String) -> Tile {
        Tile(id: UUID(uuidString: stableUUID(from: bundleID)) ?? UUID(),
             kind: .app,
             title: client.appName(for: bundleID),
             payload: bundleID,
             symbol: nil,
             tint: TileColor.graphite.rawValue)
    }

    /// Keeps SwiftUI identity stable across refreshes without persisting anything.
    private func stableUUID(from string: String) -> String {
        var hash = UInt64(5381)
        for byte in string.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        let hex = String(format: "%016llx", hash)
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(12).prefix(3))-8\(hex.prefix(3))-\(hex.prefix(12))"
    }

    private func sectionTitle(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .heavy)).tracking(1.2)
                .foregroundStyle(DockTheme.subtext)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(DockTheme.bevel)
        }
        .padding(.top, 6)
        .shadow(color: .white.opacity(0.7), radius: 0.5, y: 0.5)
    }
}

// MARK: - Emoji

struct EmojiPanel: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: DockStore

    @State private var selectedGroup = 0

    private let groups: [(String, [String])] = [
        ("Reactions", ["👍", "👎", "🙌", "👏", "🤝", "🙏", "🤯", "😂", "🥹", "😍", "😅", "😴", "🤔", "😎", "🫠", "🥳"]),
        ("Status", ["✅", "❌", "⚠️", "⏳", "🚧", "🔥", "💡", "📌", "📎", "🔒", "🚀", "🎯", "📈", "🧪", "🐛", "✨"]),
        ("Work", ["💻", "📱", "⌨️", "🖱", "🗂", "📝", "📅", "☕️", "🍫", "🎧", "🔔", "📬", "🧠", "🛠", "🧹", "🗓"]),
        ("Hearts", ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💯", "⭐️", "🌟", "🌈", "🍀", "🌻", "🌙", "☀️"])
    ]

    var body: some View {
        VStack(spacing: 14) {
            Text("Tap an emoji to type it straight into whatever app is focused on your Mac.")
                .font(.system(size: 12))
                .foregroundStyle(DockTheme.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            if !store.favoriteEmoji.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FAVORITES")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(DockTheme.subtext)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(store.favoriteEmoji, id: \.self) { emoji in
                                emojiKey(emoji, size: 54)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
            }

            Picker("Group", selection: $selectedGroup) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    Text(group.0).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.adaptive(minimum: 56), spacing: 12), count: 1), spacing: 12) {
                    ForEach(groups[selectedGroup].1, id: \.self) { emoji in
                        emojiKey(emoji, size: 56)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
    }

    private func emojiKey(_ emoji: String, size: CGFloat) -> some View {
        Text(emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .plate(cornerRadius: size * 0.26)
            .onTapGesture {
                Haptics.tap()
                client.send(.insertText(text: emoji))
            }
            .contextMenu {
                Button(store.favoriteEmoji.contains(emoji) ? "Remove favorite" : "Add to favorites",
                       systemImage: "star") {
                    store.toggleFavorite(emoji: emoji)
                }
                Button("Add as a tile", systemImage: "plus.square") {
                    store.add(Tile(kind: .emoji, title: emoji, payload: emoji, tint: TileColor.amber.rawValue))
                }
            }
    }
}

// MARK: - Clipboard bridge ("grab and throw")

struct ClipboardPanel: View {
    @EnvironmentObject private var client: DockClient
    @State private var draft: String = ""
    @State private var throwOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("THROW TO MAC")
                        .font(.system(size: 10, weight: .bold)).tracking(1.2)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $draft)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 15))
                        .frame(height: 130)
                        .padding(10)
                        .plate(cornerRadius: 16)
                        .offset(y: throwOffset)

                    HStack(spacing: 10) {
                        Button {
                            guard !draft.isEmpty else { return }
                            Haptics.firm()
                            withAnimation(.easeIn(duration: 0.18)) { throwOffset = -30 }
                            client.send(.clipboardPush(text: draft))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { throwOffset = 0 }
                            }
                        } label: {
                            Label("Throw to clipboard", systemImage: "paperplane.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .plate(cornerRadius: 14, fill: DockTheme.accent)
                        }
                        .buttonStyle(.plain)

                        Button {
                            guard !draft.isEmpty else { return }
                            Haptics.tap()
                            client.send(.insertText(text: draft))
                        } label: {
                            Image(systemName: "keyboard")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DockTheme.subtext)
                                .frame(width: 48, height: 45)
                                .plate(cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                        .help("Type this text on the Mac")
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("GRAB FROM MAC")
                            .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                            .foregroundStyle(DockTheme.subtext)
                        Spacer()
                        Button {
                            Haptics.tap()
                            client.send(.requestClipboard)
                        } label: {
                            Label("Pull", systemImage: "arrow.down.circle")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DockTheme.accent)
                    }

                    Text(client.macClipboard.isEmpty ? "Nothing grabbed yet." : client.macClipboard)
                        .font(.system(size: 14))
                        .foregroundStyle(client.macClipboard.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .plate(cornerRadius: 16)

                    if !client.macClipboard.isEmpty {
                        Button {
                            UIPasteboard.general.string = client.macClipboard
                            client.showToast("Copied on this device")
                            Haptics.success()
                        } label: {
                            Label("Copy on this device", systemImage: "doc.on.doc")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DockTheme.accent)
                    }
                }
            }
            .padding(18)
        }
    }
}
