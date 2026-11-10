//
//  TileEditorView.swift
//  MobileDock for iOS — rename a tile, restyle it, or move it to another page.
//

import SwiftUI

struct TileEditorView: View {
    @EnvironmentObject private var store: DockStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Tile

    init(tile: Tile) {
        _draft = State(initialValue: tile)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("Title", text: $draft.title)
                }

                Section("Icon") {
                    if draft.kind == .emoji {
                        LabeledContent("Shown on the tile") {
                            Text(draft.payload).font(.system(size: 22))
                        }
                    } else if draft.kind == .app {
                        Text("App tiles use the Mac’s own app icon.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        SymbolPicker(title: "SF Symbol", selection: Binding(
                            get: { draft.symbol ?? draft.kind.systemImage },
                            set: { draft.symbol = $0 }
                        ))
                    }
                }

                Section("Target") {
                    LabeledContent(draft.kind.label) {
                        Text(draft.payload)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if draft.kind == .website {
                        TextField("Address", text: $draft.payload)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8), spacing: 10) {
                        ForEach(TileColor.allCases, id: \.self) { option in
                            Circle()
                                .fill(option.color)
                                .frame(height: 30)
                                .overlay(
                                    Circle().stroke(.white, lineWidth: draft.tint == option.rawValue ? 2.5 : 0)
                                )
                                .onTapGesture {
                                    Haptics.tap()
                                    draft.tint = option.rawValue
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Page") {
                    ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                        Button {
                            move(to: index)
                        } label: {
                            HStack {
                                Image(systemName: page.symbol).frame(width: 20)
                                Text(page.name)
                                Spacer()
                                if page.tiles.contains(where: { $0.id == draft.id }) {
                                    Image(systemName: "checkmark").foregroundStyle(DockTheme.accent)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Remove tile", role: .destructive) {
                        store.remove(draft)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit tile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.update(draft)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func move(to pageIndex: Int) {
        guard store.pages.indices.contains(pageIndex) else { return }
        store.remove(draft)
        store.add(draft, toPage: pageIndex)
        Haptics.tap()
    }
}
