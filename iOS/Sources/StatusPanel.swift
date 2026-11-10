//
//  StatusPanel.swift
//  MobileDock for iOS — how the Mac is doing, plus the levels and file transfer.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct StatusPanel: View {
    @EnvironmentObject private var client: DockClient

    @State private var volume: Double = 0.5
    @State private var brightness: Double = 0.7
    @State private var editingVolume = false
    @State private var editingBrightness = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false

    private var status: MacStatus? { client.status }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let status {
                    metrics(status)
                    levels(status)
                    if let playing = status.nowPlaying {
                        nowPlaying(playing)
                    }
                } else {
                    ProgressView("Reading the Mac…")
                        .font(.system(size: 12))
                        .padding(.vertical, 30)
                }

                transfer
            }
            .padding(16)
        }
        .onAppear {
            client.startStatusUpdates()
            if let status {
                volume = status.volume
                brightness = status.brightness
            }
        }
        .onDisappear { client.stopStatusUpdates() }
        .onChange(of: client.status) { _, new in
            guard let new else { return }
            if !editingVolume { volume = new.volume }
            if !editingBrightness { brightness = new.brightness }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    // MARK: Metrics

    private func metrics(_ status: MacStatus) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            if let battery = status.batteryPercent {
                card(title: "Battery",
                     value: "\(battery)%",
                     detail: status.isCharging ? "Charging" : "On battery",
                     symbol: status.isCharging ? "battery.100.bolt" : "battery.75",
                     tint: battery < 20 ? DockTheme.danger : DockTheme.mint,
                     fraction: Double(battery) / 100)
            }
            card(title: "CPU",
                 value: String(format: "%.0f%%", status.cpuPercent),
                 detail: "Processor load",
                 symbol: "cpu",
                 tint: DockTheme.accent,
                 fraction: status.cpuPercent / 100)
            card(title: "Memory",
                 value: String(format: "%.1f GB", status.memoryUsedGB),
                 detail: LocalizedStringKey(String(format: "of %.0f GB", status.memoryTotalGB)),
                 symbol: "memorychip",
                 tint: DockTheme.warn,
                 fraction: status.memoryTotalGB > 0 ? status.memoryUsedGB / status.memoryTotalGB : 0)
            card(title: "Disk",
                 value: String(format: "%.0f GB", status.diskFreeGB),
                 detail: "Free space",
                 symbol: "internaldrive",
                 tint: DockTheme.accent,
                 fraction: nil)
            card(title: "Network",
                 value: status.networkName ?? "—",
                 detail: "Connected",
                 symbol: "wifi",
                 tint: DockTheme.mint,
                 fraction: nil)
            card(title: "Uptime",
                 value: status.uptime,
                 detail: "Since last restart",
                 symbol: "clock.arrow.circlepath",
                 tint: DockTheme.subtext,
                 fraction: nil)
        }
    }

    private func card(title: LocalizedStringKey, value: String, detail: LocalizedStringKey,
                      symbol: String, tint: Color, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .textCase(.uppercase)
                    .font(.system(size: 9.5, weight: .heavy)).tracking(1)
                    .foregroundStyle(DockTheme.subtext)
            }
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(DockTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(DockTheme.subtext)
                .lineLimit(1)

            if let fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DockTheme.bevel.opacity(0.25))
                        Capsule().fill(tint)
                            .frame(width: proxy.size.width * min(1, max(0, fraction)))
                    }
                }
                .frame(height: 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .plate(cornerRadius: 16)
    }

    // MARK: Levels

    private func levels(_ status: MacStatus) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    client.send(.setMuted(!status.isMuted))
                } label: {
                    Image(systemName: status.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(status.isMuted ? .white : DockTheme.subtext)
                        .frame(width: 36, height: 36)
                        .plate(cornerRadius: 11, fill: status.isMuted ? DockTheme.danger : DockTheme.panel)
                }
                .buttonStyle(.plain)

                Slider(value: $volume, in: 0...1) { editing in
                    editingVolume = editing
                    if !editing { client.send(.setVolume(level: volume)) }
                }
                Text("\(Int(volume * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DockTheme.subtext)
                    .frame(width: 38, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DockTheme.warn)
                    .frame(width: 36, height: 36)
                    .plate(cornerRadius: 11)

                Slider(value: $brightness, in: 0...1) { editing in
                    editingBrightness = editing
                    if !editing { client.send(.setBrightness(level: brightness)) }
                }
                Text("\(Int(brightness * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DockTheme.subtext)
                    .frame(width: 38, alignment: .trailing)
            }

            Text("Brightness is stepped with the display keys, so it lands close to the mark rather than exactly on it.")
                .font(.system(size: 10))
                .foregroundStyle(DockTheme.subtext)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .plate(cornerRadius: 16)
    }

    // MARK: Now playing

    private func nowPlaying(_ playing: NowPlaying) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DockTheme.face(DockTheme.accent))
                    .overlay(GlossOverlay(cornerRadius: 12))
                    .frame(width: 46, height: 46)
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(playing.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DockTheme.text)
                    .lineLimit(1)
                Text("\(playing.artist) · \(playing.app)")
                    .font(.system(size: 11))
                    .foregroundStyle(DockTheme.subtext)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                transport("backward.fill") { client.send(.media(key: .previous)) }
                transport(playing.isPlaying ? "pause.fill" : "play.fill") { client.send(.media(key: .playPause)) }
                transport("forward.fill") { client.send(.media(key: .next)) }
            }
        }
        .padding(12)
        .plate(cornerRadius: 16)
    }

    private func transport(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DockTheme.subtext)
                .frame(width: 32, height: 32)
                .plate(cornerRadius: 10, shadow: false)
        }
        .buttonStyle(.plain)
    }

    // MARK: Files

    private var transfer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FILES")
                .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                .foregroundStyle(DockTheme.subtext)

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .any(of: [.images, .videos])) {
                    transferButton("Send photo", systemImage: "photo.on.rectangle")
                }
                Button {
                    showFileImporter = true
                } label: {
                    transferButton("Send file", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.plain)
            }

            Button {
                Haptics.tap()
                client.send(.requestFinderSelection)
            } label: {
                transferButton("Pull what's selected in Finder", systemImage: "arrow.down.doc", wide: true)
            }
            .buttonStyle(.plain)

            if let received = client.lastReceivedFile {
                ShareLink(item: received) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text(received.lastPathComponent).lineLimit(1)
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DockTheme.accent)
                    .padding(12)
                    .plate(cornerRadius: 14, shadow: false)
                }
            }

            Text("Files land in the Mac's Downloads folder and are revealed in Finder.")
                .font(.system(size: 10))
                .foregroundStyle(DockTheme.subtext)
        }
        .padding(14)
        .plate(cornerRadius: 16)
    }

    private func transferButton(_ title: LocalizedStringKey, systemImage: String, wide: Bool = false) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage).font(.system(size: 14, weight: .semibold))
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(DockTheme.subtext)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .plate(cornerRadius: 14)
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        let name = "MobileDock-\(Int(Date().timeIntervalSince1970)).\(ext)"
        client.sendFile(name: name, data: data)
        photoItem = nil
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            client.showToast("Could not read that file")
            return
        }
        client.sendFile(name: url.lastPathComponent, data: data)
    }
}

// MARK: - Window list

struct WindowListView: View {
    @EnvironmentObject private var client: DockClient
    @Environment(\.dismiss) private var dismiss

    let bundleID: String
    let appName: String

    var body: some View {
        NavigationStack {
            Group {
                let windows = client.windows[bundleID] ?? []
                if windows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 26))
                            .foregroundStyle(DockTheme.subtext)
                        Text("No windows reported")
                            .font(.system(size: 15, weight: .semibold))
                        Text("The app may have none open, or Accessibility access is off on the Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(DockTheme.subtext)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(windows) { window in
                            Button {
                                Haptics.tap()
                                client.send(.focusWindow(id: window.id))
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: window.isMinimized ? "macwindow.badge.plus" : "macwindow")
                                        .foregroundStyle(window.isFocused ? DockTheme.accent : DockTheme.subtext)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(window.title).font(.system(size: 14)).lineLimit(1)
                                        if window.isMinimized {
                                            Text("Minimized").font(.system(size: 10)).foregroundStyle(DockTheme.subtext)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    client.send(.windowCommand(id: window.id, action: .closeWindow))
                                    client.send(.requestWindows(bundleID: bundleID))
                                } label: { Label("Close", systemImage: "xmark") }

                                Button {
                                    client.send(.windowCommand(id: window.id, action: .minimize))
                                    client.send(.requestWindows(bundleID: bundleID))
                                } label: { Label("Minimize", systemImage: "arrow.down.right.and.arrow.up.left") }
                                .tint(DockTheme.accent)
                            }
                            .listRowBackground(DockTheme.panel)
                        }

                        Section("Place the front window") {
                            ForEach(ControlCatalog.actions(in: .window).filter { $0.payload.hasPrefix("tile") || $0.payload == "center" }) { action in
                                Button {
                                    Haptics.tap()
                                    if let windowAction = WindowAction(rawValue: action.payload) {
                                        client.send(.window(action: windowAction))
                                    }
                                } label: {
                                    Label(action.title, systemImage: action.symbol)
                                        .font(.system(size: 14))
                                }
                                .listRowBackground(DockTheme.panel)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(DockTheme.bg)
            .navigationTitle(appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        client.send(.requestWindows(bundleID: bundleID))
                    } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .onAppear { client.send(.requestWindows(bundleID: bundleID)) }
    }
}
