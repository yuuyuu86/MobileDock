//
//  AddTileView.swift
//  MobileDock for iOS — picker for everything that can become a tile.
//

import SwiftUI

struct AddTileView: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: DockStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: TileKind = .app
    @State private var search = ""
    @State private var websiteName = ""
    @State private var websiteURL = ""
    @State private var websiteSymbol = "globe"
    @State private var emojiDraft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Kind", selection: $kind) {
                    ForEach(TileKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                switch kind {
                case .app: appList
                case .shortcut: shortcutList
                case .website: websiteForm
                case .emoji: emojiForm
                case .control: controlList
                }
            }
            .padding(.top, 10)
            .background(DockTheme.board)
            .navigationTitle("Add to \(store.page?.name ?? "bar")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(DockTheme.bg)
    }

    // MARK: Apps

    private var apps: [AppInfo] {
        let all = client.catalog?.apps ?? []
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            SearchField(text: $search, placeholder: "Search apps on your Mac")
            List {
                ForEach(apps) { app in
                    Button {
                        add(Tile(kind: .app, title: app.name, payload: app.bundleID, tint: randomTint()))
                    } label: {
                        HStack(spacing: 12) {
                            if let icon = client.icons[app.bundleID] {
                                Image(uiImage: icon).resizable().frame(width: 30, height: 30)
                            } else {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(DockTheme.raised)
                                    .frame(width: 30, height: 30)
                            }
                            Text(app.name).font(.system(size: 15))
                            Spacer()
                            if client.running.contains(app.bundleID) {
                                Circle().fill(DockTheme.mint).frame(width: 6, height: 6)
                            }
                            Image(systemName: "plus.circle.fill").foregroundStyle(DockTheme.accent)
                        }
                    }
                    .listRowBackground(DockTheme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Shortcuts

    private var shortcuts: [ShortcutInfo] {
        let all = client.catalog?.shortcuts ?? []
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var shortcutList: some View {
        VStack(spacing: 0) {
            SearchField(text: $search, placeholder: "Search Shortcuts")
            if shortcuts.isEmpty {
                emptyState("No Shortcuts found",
                           detail: "Create one in the Shortcuts app on your Mac, then reload from MobileDock’s settings.")
            } else {
                List {
                    ForEach(shortcuts) { shortcut in
                        Button {
                            add(Tile(kind: .shortcut, title: shortcut.name, payload: shortcut.name,
                                     symbol: "sparkles", tint: TileColor.violet.rawValue))
                        } label: {
                            HStack {
                                Image(systemName: "sparkles").foregroundStyle(DockTheme.accent)
                                Text(shortcut.name).font(.system(size: 15))
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(DockTheme.accent)
                            }
                        }
                        .listRowBackground(DockTheme.surface)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: Websites

    private var websiteForm: some View {
        VStack(spacing: 14) {
            LabeledField(title: "Name", text: $websiteName, placeholder: "Docs")
            LabeledField(title: "Address", text: $websiteURL, placeholder: "example.com", keyboard: .URL)

            SymbolPicker(title: "Icon", selection: $websiteSymbol)

            Button {
                let name = websiteName.isEmpty ? websiteURL : websiteName
                guard !websiteURL.isEmpty else { return }
                add(Tile(kind: .website, title: name, payload: websiteURL,
                         symbol: websiteSymbol, tint: TileColor.sky.rawValue))
            } label: {
                Text("Add website")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .plate(cornerRadius: 14, fill: DockTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(websiteURL.isEmpty)
            .opacity(websiteURL.isEmpty ? 0.5 : 1)

            Spacer()
        }
        .padding(18)
    }

    // MARK: Emoji

    private var emojiForm: some View {
        VStack(spacing: 14) {
            Text("Pick an emoji to keep one tap away. Tapping its tile types it on the Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(DockStore.starterEmoji + ["🍫", "🧊", "🛟", "🎬", "🧭", "🪄"], id: \.self) { emoji in
                    Button {
                        add(Tile(kind: .emoji, title: emoji, payload: emoji, tint: TileColor.amber.rawValue))
                    } label: {
                        Text(emoji)
                            .font(.system(size: 26))
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DockTheme.surface))
                    }
                    .buttonStyle(.plain)
                }
            }

            LabeledField(title: "Or paste any emoji", text: $emojiDraft, placeholder: "🍀")
            Button("Add “\(emojiDraft)”") {
                guard !emojiDraft.isEmpty else { return }
                add(Tile(kind: .emoji, title: emojiDraft, payload: emojiDraft, tint: TileColor.amber.rawValue))
            }
            .disabled(emojiDraft.isEmpty)
            .foregroundStyle(DockTheme.accent)

            Spacer()
        }
        .padding(18)
    }

    // MARK: Controls


    private var controls: [ControlCatalog.Action] {
        guard !search.isEmpty else { return ControlCatalog.all }
        return ControlCatalog.all.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private var controlList: some View {
        VStack(spacing: 0) {
            SearchField(text: $search, placeholder: "Search controls")
            List {
                ForEach(ControlCatalog.Category.allCases) { category in
                    let items = controls.filter { $0.category == category }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { control in
                                Button {
                                    add(Tile(kind: .control, title: control.title, payload: control.payload,
                                             symbol: control.symbol, tint: TileColor.graphite.rawValue))
                                } label: {
                                    HStack {
                                        Image(systemName: control.symbol)
                                            .foregroundStyle(DockTheme.accent)
                                            .frame(width: 22)
                                        Text(control.title).font(.system(size: 15))
                                        Spacer()
                                        Image(systemName: "plus.circle.fill").foregroundStyle(DockTheme.accent)
                                    }
                                }
                                .listRowBackground(DockTheme.surface)
                            }
                        } header: {
                            Label(category.title, systemImage: category.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Helpers

    private func add(_ tile: Tile) {
        Haptics.success()
        store.add(tile)
        client.showToast("Added \(tile.title)")
    }

    private func randomTint() -> String {
        TileColor.allCases.randomElement()?.rawValue ?? TileColor.graphite.rawValue
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Small form pieces

struct SearchField: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(DockTheme.face(DockTheme.panel))
                .overlay(Capsule().strokeBorder(DockTheme.bevel.opacity(0.5), lineWidth: 0.8))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct LabeledField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var placeholder: LocalizedStringKey = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .bold)).tracking(1.1)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(DockTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(DockTheme.hairline))
                )
        }
    }
}

struct SymbolPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: String
    var choices: [String] = SymbolLibrary.tiles

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .bold)).tracking(1.1)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(choices, id: \.self) { name in
                        Button {
                            Haptics.tap()
                            selection = name
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selection == name ? .white : DockTheme.subtext)
                                .frame(width: 34, height: 34)
                                .plate(cornerRadius: 10,
                                       fill: selection == name ? DockTheme.accent : DockTheme.panel,
                                       shadow: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 34 * 3 + 8 * 2)
        }
    }
}
