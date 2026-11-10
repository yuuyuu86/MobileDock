//
//  SearchView.swift
//  MobileDock for iOS — one field across apps, Shortcuts, tiles and controls.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: DockStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var focused: Bool

    private struct Hit: Identifiable {
        enum Kind { case app, shortcut, tile, control, window }
        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        let symbol: String
        let bundleID: String?
        let run: () -> Void
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchField(text: $query, placeholder: "Apps, Shortcuts, tiles, controls")
                    .focused($focused)
                    .padding(.top, 8)

                if hits.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: query.isEmpty ? "magnifyingglass" : "questionmark.circle")
                            .font(.system(size: 26))
                            .foregroundStyle(DockTheme.subtext)
                        Text(query.isEmpty ? "Search everything on your Mac" : "Nothing matches “\(query)”")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DockTheme.subtext)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(hits) { hit in
                        Button {
                            Haptics.tap()
                            hit.run()
                            dismiss()
                        } label: {
                            HStack(spacing: 11) {
                                icon(for: hit)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .lineLimit(1)
                                    Text(hit.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(DockTheme.subtext)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if hit.kind == .app, let bundleID = hit.bundleID,
                                   client.running.contains(bundleID) {
                                    Circle().fill(DockTheme.mint).frame(width: 6, height: 6)
                                }
                            }
                        }
                        .listRowBackground(DockTheme.panel)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(DockTheme.bg)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func icon(for hit: Hit) -> some View {
        if let bundleID = hit.bundleID, let image = client.icons[bundleID] {
            Image(uiImage: image).resizable().frame(width: 28, height: 28)
        } else {
            Image(systemName: hit.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DockTheme.accent)
                .frame(width: 28, height: 28)
        }
    }

    /// Everything the remote knows about, ranked so exact prefixes come first.
    private var hits: [Hit] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }

        var results: [Hit] = []

        for app in client.catalog?.apps ?? [] where app.name.lowercased().contains(needle) {
            results.append(Hit(id: "app." + app.bundleID,
                               kind: .app,
                               title: app.name,
                               subtitle: "App",
                               symbol: "square.grid.2x2",
                               bundleID: app.bundleID,
                               run: { client.send(.launchApp(bundleID: app.bundleID)) }))
        }

        for shortcut in client.catalog?.shortcuts ?? [] where shortcut.name.lowercased().contains(needle) {
            results.append(Hit(id: "shortcut." + shortcut.name,
                               kind: .shortcut,
                               title: shortcut.name,
                               subtitle: "Shortcut",
                               symbol: "sparkles",
                               bundleID: nil,
                               run: { client.send(.runShortcut(name: shortcut.name)) }))
        }

        for (index, page) in store.pages.enumerated() {
            for tile in page.tiles where tile.kind != .app && tile.title.lowercased().contains(needle) {
                results.append(Hit(id: "tile." + tile.id.uuidString,
                                   kind: .tile,
                                   title: tile.title,
                                   subtitle: "\(tile.kind.label) · \(page.name)",
                                   symbol: tile.resolvedSymbol,
                                   bundleID: nil,
                                   run: {
                                       store.currentPage = index
                                       trigger(tile)
                                   }))
            }
        }

        for action in ControlCatalog.all where action.title.lowercased().contains(needle) {
            results.append(Hit(id: "control." + action.payload,
                               kind: .control,
                               title: action.title,
                               subtitle: action.category.title,
                               symbol: action.symbol,
                               bundleID: nil,
                               run: { fire(payload: action.payload) }))
        }

        for (bundleID, windows) in client.windows {
            for window in windows where window.title.lowercased().contains(needle) {
                results.append(Hit(id: "window." + window.id,
                                   kind: .window,
                                   title: window.title,
                                   subtitle: "Window · \(client.appName(for: bundleID))",
                                   symbol: "macwindow",
                                   bundleID: bundleID,
                                   run: { client.send(.focusWindow(id: window.id)) }))
            }
        }

        return results.sorted { lhs, rhs in
            let left = lhs.title.lowercased().hasPrefix(needle)
            let right = rhs.title.lowercased().hasPrefix(needle)
            if left != right { return left }
            return lhs.title.count < rhs.title.count
        }
    }

    private func trigger(_ tile: Tile) {
        switch tile.kind {
        case .website: client.send(.openURL(url: tile.payload))
        case .shortcut: client.send(.runShortcut(name: tile.payload))
        case .emoji: client.send(.insertText(text: tile.payload))
        case .control: fire(payload: tile.payload)
        case .app: client.send(.launchApp(bundleID: tile.payload))
        }
    }

    private func fire(payload: String) {
        if payload.hasPrefix("media."),
           let key = MediaKey(rawValue: String(payload.dropFirst("media.".count))) {
            client.send(.media(key: key))
        } else if payload.hasPrefix("system."),
                  let action = SystemAction(rawValue: String(payload.dropFirst("system.".count))) {
            client.send(.system(action: action))
        } else if let action = WindowAction(rawValue: payload) {
            client.send(.window(action: action))
        }
    }
}
