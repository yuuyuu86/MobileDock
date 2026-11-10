//
//  DockSettingsView.swift
//  MobileDock for iOS — connection, pages and behaviour settings.
//

import SwiftUI

struct DockSettingsView: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: DockStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("haptics.enabled") private var hapticsEnabled = true
    @AppStorage("keepAwake") private var keepAwake = true
    @AppStorage("followFrontApp") private var followFrontApp = false
    @AppStorage("idleMinutes") private var idleMinutes = 0
    @AppStorage("pointer.speed") private var pointerSpeed: Double = 1.6
    @AppStorage("sync.icloud.enabled") private var icloudSync = true
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connected Mac") {
                    LabeledContent("Name", value: client.host?.name ?? "—")
                    LabeledContent("Model", value: client.host?.model ?? "—")
                    LabeledContent("Host app", value: client.host?.version ?? "—")
                    if let catalog = client.catalog {
                        LabeledContent("Apps", value: "\(catalog.apps.count)")
                        LabeledContent("Shortcuts", value: "\(catalog.shortcuts.count)")
                        if !catalog.accessibilityGranted {
                            Label("Accessibility is off on the Mac — emoji, typing and window gestures will not work until you grant it in System Settings.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DockTheme.accent)
                        }
                    }
                    Button("Refresh catalog") { client.send(.requestCatalog) }
                }

                Section("Pages") {
                    ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                        HStack {
                            Menu {
                                ForEach(SymbolLibrary.pages, id: \.self) { name in
                                    Button {
                                        store.pages[index].symbol = name
                                    } label: {
                                        Label(name, systemImage: name)
                                    }
                                }
                            } label: {
                                Image(systemName: page.symbol)
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(DockTheme.accent)
                            }
                            TextField("Name", text: Binding(
                                get: { store.pages[index].name },
                                set: { store.pages[index].name = $0 }
                            ))
                            Spacer()
                            Text("\(page.tiles.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        offsets.forEach { store.removePage(at: $0) }
                    }

                    if store.pages.count < DockStore.maxPages {
                        Button("Add page", systemImage: "plus") { store.addPage() }
                    }
                }

                Section("Behaviour") {
                    Toggle("Follow the front app", isOn: $followFrontApp)
                    Text("When the Mac switches apps, the bar jumps to the page holding that app's tile.")
                        .font(.system(size: 11))
                        .foregroundStyle(DockTheme.subtext)

                    Picker("Disconnect when idle", selection: $idleMinutes) {
                        Text("Never").tag(0)
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }

                    Toggle("Haptic feedback", isOn: $hapticsEnabled)
                    Toggle("Keep screen awake while connected", isOn: $keepAwake)
                        .onChange(of: keepAwake) { _, value in
                            UIApplication.shared.isIdleTimerDisabled = value
                        }
                }

                Section {
                    Toggle("Sync this bar over iCloud", isOn: $icloudSync)
                        .onChange(of: icloudSync) { _, value in CloudSync.shared.isEnabled = value }
                    LabeledContent("iCloud", value: CloudSync.shared.statusText)

                    if let url = BarDocument.export(pages: store.pages) {
                        ShareLink(item: url) {
                            Label("Export this bar as a file", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import a bar file", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Sync & backup")
                } footer: {
                    Text("Bars are kept per Mac. iCloud sync needs a build signed with the iCloud capability; the file export works on any build.")
                }

                Section("Trackpad") {
                    HStack {
                        Text("Pointer speed")
                        Slider(value: $pointerSpeed, in: 0.6...3.0)
                        Text(String(format: "%.1f×", pointerSpeed))
                            .font(.system(size: 12))
                            .foregroundStyle(DockTheme.subtext)
                    }
                }

                Section("Paired Macs") {
                    if TokenStore.knownHosts.isEmpty {
                        Text("None yet").foregroundStyle(DockTheme.subtext)
                    }
                    ForEach(TokenStore.knownHosts, id: \.self) { name in
                        HStack {
                            Image(systemName: "laptopcomputer")
                                .foregroundStyle(name == client.host?.name ? DockTheme.accent : DockTheme.subtext)
                            Text(name).lineLimit(1)
                            Spacer()
                            if name == client.host?.name {
                                Text("Connected")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DockTheme.accent)
                            } else if let match = client.hosts.first(where: { $0.name == name }) {
                                Button("Switch") {
                                    client.disconnect()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        client.connect(to: match)
                                    }
                                    dismiss()
                                }
                                .font(.system(size: 12, weight: .semibold))
                            } else {
                                Text("Offline")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DockTheme.subtext)
                            }
                        }
                        .swipeActions {
                            Button("Forget", role: .destructive) {
                                TokenStore.forget(hostName: name)
                            }
                        }
                    }
                }

                Section {
                    Button("Disconnect") {
                        client.disconnect()
                        dismiss()
                    }
                    Button("Forget this Mac", role: .destructive) {
                        client.disconnect(forget: true)
                        dismiss()
                    }
                } footer: {
                    Text("MobileDock talks directly to your Mac over the local network, on a TLS channel keyed by the pairing PIN. Nothing leaves your Wi‑Fi.")
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first,
                      let imported = BarDocument.load(from: url) else { return }
                store.replacePages(imported)
                Haptics.success()
                dismiss()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
    }
}
