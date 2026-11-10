//
//  DockBarView.swift
//  MobileDock for iOS — the home board: a fixed grid of slots, page arrows on the
//  sides, a page band on top and flat colour icons along the bottom.
//

import SwiftUI
import UniformTypeIdentifiers

enum DockMode: String, CaseIterable, Identifiable {
    case bar, recents, emoji, clipboard, trackpad, keyboard, status

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .bar: return "Dock"
        case .recents: return "Recents"
        case .emoji: return "Emoji"
        case .clipboard: return "Clipboard"
        case .trackpad: return "Trackpad"
        case .keyboard: return "Keyboard"
        case .status: return "Status"
        }
    }

    var systemImage: String {
        switch self {
        case .bar: return "square.grid.2x2.fill"
        case .recents: return "clock.arrow.circlepath"
        case .emoji: return "face.smiling.inverse"
        case .clipboard: return "doc.on.clipboard.fill"
        case .trackpad: return "rectangle.and.hand.point.up.left.fill"
        case .keyboard: return "keyboard.fill"
        case .status: return "gauge.with.dots.needle.33percent"
        }
    }

    var color: Color {
        switch self {
        case .bar: return Color(red: 0.20, green: 0.58, blue: 0.89)
        case .recents: return Color(red: 0.44, green: 0.78, blue: 0.31)
        case .emoji: return Color(red: 0.97, green: 0.62, blue: 0.19)
        case .clipboard: return Color(red: 0.29, green: 0.64, blue: 0.85)
        case .trackpad: return Color(red: 0.55, green: 0.45, blue: 0.85)
        case .keyboard: return Color(red: 0.38, green: 0.45, blue: 0.55)
        case .status: return Color(red: 0.90, green: 0.42, blue: 0.40)
        }
    }
}

struct DockBarView: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: DockStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Remembered so the app comes back to whatever you were using.
    @AppStorage("dock.mode") private var storedMode: String = DockMode.bar.rawValue
    @State private var mode: DockMode = .bar
    @State private var showAddSheet = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var draggingTile: Tile?
    @AppStorage("followFrontApp") private var followFrontApp = false

    var body: some View {
        ZStack {
            boardBackground

            if !store.isFullScreen {
                footerPlate
            }

            VStack(spacing: 0) {
                if !store.isFullScreen {
                    topStrip
                } else {
                    fullScreenStrip
                }

                content
                    .padding(.bottom, store.isFullScreen ? 0 : 18)

                if !store.isFullScreen {
                    footer
                }
            }
        }
        .onAppear { mode = DockMode(rawValue: storedMode) ?? .bar }
        .onChange(of: mode) { _, new in storedMode = new.rawValue }
        .statusBarHidden(store.isFullScreen)
        .persistentSystemOverlays(store.isFullScreen ? .hidden : .automatic)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: store.isFullScreen)
        .onChange(of: client.frontApp) { _, front in
            guard followFrontApp, mode == .bar, !store.isEditing,
                  let front, let page = store.page(containing: front),
                  page != store.currentPage else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                store.currentPage = page
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTileView()
                .environmentObject(client)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            DockSettingsView()
                .environmentObject(client)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
                .environmentObject(client)
                .environmentObject(store)
        }
    }

    /// Near-white board with a soft bloom in the middle and cooler corners.
    private var boardBackground: some View {
        ZStack {
            Color(red: 0.957, green: 0.965, blue: 0.973)
            RadialGradient(colors: [.white, .white.opacity(0)],
                           center: .center, startRadius: 20, endRadius: 460)
            LinearGradient(colors: [Color(red: 0.78, green: 0.82, blue: 0.86).opacity(0.55), .clear],
                           startPoint: .bottom, endPoint: .center)
            LinearGradient(colors: [Color(red: 0.80, green: 0.84, blue: 0.88).opacity(0.35), .clear],
                           startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    // MARK: Top strip

    private var topStrip: some View {
        ZStack {
            if mode == .bar {
                PageBand(count: store.pages.count,
                         current: store.currentPage,
                         onSelect: { index in
                             Haptics.tap()
                             withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                 store.currentPage = index
                             }
                         },
                         onAdd: store.isEditing && store.pages.count < DockStore.maxPages
                             ? { withAnimation { store.addPage() } }
                             : nil)
            }

            HStack(alignment: .top) {
                hostCard
                Spacer()
                HStack(spacing: 8) {
                    roundChrome("magnifyingglass", active: false) {
                        Haptics.tap()
                        showSearch = true
                    }
                    roundChrome(store.isEditing ? "checkmark" : "slider.horizontal.3",
                                active: store.isEditing) {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            store.isEditing.toggle()
                        }
                    }
                    roundChrome("gearshape.fill", active: false) { showSettings = true }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var fullScreenStrip: some View {
        HStack(alignment: .top) {
            PageBand(count: store.pages.count,
                     current: store.currentPage,
                     onSelect: { index in
                         Haptics.tap()
                         withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                             store.currentPage = index
                         }
                     },
                     onAdd: nil)
            Spacer()
            Button(action: exitFullScreen) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DockTheme.subtext)
                    .frame(width: 36, height: 36)
                    .plate(cornerRadius: 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var hostCard: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(DockTheme.face(DockTheme.accent))
                    .overlay(GlossOverlay(cornerRadius: 7))
                    .frame(width: 26, height: 26)
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(client.host?.name ?? "Mac")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DockTheme.text)
                    .lineLimit(1)
                Text(frontAppLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(DockTheme.subtext)
                    .lineLimit(1)
            }
            .frame(maxWidth: 104, alignment: .leading)
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .plate(cornerRadius: 12)
    }

    private var frontAppLabel: String {
        guard let front = client.frontApp else { return "Connected" }
        return client.appName(for: front)
    }

    private func roundChrome(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? .white : DockTheme.subtext)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(DockTheme.face(active ? DockTheme.accent : DockTheme.panel))
                        .overlay(
                            Circle()
                                .fill(LinearGradient(colors: [.white.opacity(0.85), .clear],
                                                     startPoint: .top, endPoint: .center))
                                .blendMode(.softLight)
                        )
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                        .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Board

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .bar:
            BoardPagesView(showAddSheet: $showAddSheet,
                           draggingTile: $draggingTile,
                           isFullScreen: store.isFullScreen)
        case .recents:
            RecentsPanel()
        case .emoji:
            EmojiPanel()
        case .clipboard:
            ClipboardPanel()
        case .trackpad:
            TrackpadPanel()
        case .keyboard:
            KeyboardPanel()
        case .status:
            StatusPanel()
        }
    }

    /// The secondary modes, laid out two rows deep so they fit beside the clock.
    private var secondaryRows: [[DockMode]] {
        let items = DockMode.allCases.filter { $0 != .bar }
        return stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0..<min($0 + 3, items.count)])
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
                FooterRoundButton(symbol: DockMode.bar.systemImage,
                                  label: "DOCK",
                                  tint: DockMode.bar.color,
                                  active: mode == .bar) {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { mode = .bar }
                }

            VStack(spacing: 5) {
                ForEach(secondaryRows, id: \.first) { row in
                    HStack(spacing: 5) {
                        ForEach(row) { item in
                            FooterSmallButton(symbol: item.systemImage,
                                              color: item.color,
                                              selected: mode == item) {
                                Haptics.tap()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { mode = item }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            FooterClock()
                .layoutPriority(1)

            Spacer(minLength: 4)

            FooterRoundButton(symbol: "arrow.up.left.and.arrow.down.right",
                              label: "FULL",
                              tint: DockTheme.accent,
                              active: false,
                              action: enterFullScreen)
        }
        .padding(.horizontal, 12)
        .frame(height: 92)
        .padding(.top, 6)
    }

    /// The plate itself lives in the root stack so it can run edge to edge, past
    /// the side safe areas a landscape iPhone introduces.
    private var footerPlate: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .top) {
                FooterShape()
                    .fill(
                        LinearGradient(colors: [Color(red: 0.93, green: 0.95, blue: 0.97),
                                                Color(red: 0.83, green: 0.87, blue: 0.91)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 6, y: -3)

                FooterGlowEdge()
            }
            .frame(height: 116)
        }
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .allowsHitTesting(false)
    }

    // MARK: Full screen

    private func enterFullScreen() {
        Haptics.firm()
        mode = .bar
        store.isEditing = false
        store.isFullScreen = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func exitFullScreen() {
        Haptics.tap()
        store.isFullScreen = false
        UIApplication.shared.isIdleTimerDisabled =
            UserDefaults.standard.object(forKey: "keepAwake") as? Bool ?? true
    }
}

// MARK: - Pages of slots

struct BoardPagesView: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: DockStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Binding var showAddSheet: Bool
    @Binding var draggingTile: Tile?
    var isFullScreen: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = BoardMetrics(width: proxy.size.width,
                                       height: proxy.size.height,
                                       regular: sizeClass == .regular,
                                       fullScreen: isFullScreen)
            ZStack {
                TabView(selection: $store.currentPage) {
                    ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                        pageGrid(page, pageIndex: index, metrics: metrics)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack {
                    PageArrow(direction: .left, enabled: store.currentPage > 0) {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            store.currentPage = max(0, store.currentPage - 1)
                        }
                    }
                    Spacer()
                    PageArrow(direction: .right, enabled: store.currentPage < store.pages.count - 1) {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            store.currentPage = min(store.pages.count - 1, store.currentPage + 1)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .allowsHitTesting(true)
            }
        }
    }

    private func pageGrid(_ page: DockPage, pageIndex: Int, metrics: BoardMetrics) -> some View {
        // Always draw a full board: real tiles first, free slots after.
        let slots = max(metrics.slots, page.tiles.count + (store.isEditing ? 1 : 0))

        return ScrollView {
            LazyVGrid(columns: metrics.columns, spacing: metrics.rowSpacing) {
                ForEach(0..<slots, id: \.self) { index in
                    if index < page.tiles.count {
                        let tile = page.tiles[index]
                        TileView(tile: tile, size: metrics.tileSize)
                            .opacity(draggingTile?.id == tile.id ? 0.25 : 1)
                            .reorderable(enabled: store.isEditing,
                                         tile: tile,
                                         pageIndex: pageIndex,
                                         dragging: $draggingTile,
                                         store: store)
                    } else if index == page.tiles.count && (store.isEditing || page.tiles.isEmpty) {
                        AddTileButton(size: metrics.tileSize) { showAddSheet = true }
                    } else {
                        EmptySlotView(size: metrics.tileSize,
                                      slotIndex: index,
                                      pageIndex: pageIndex,
                                      dragging: $draggingTile,
                                      store: store)
                    }
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: max(metrics.boardHeight, 0), alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Drag to reorder

extension View {
    /// In edit mode a tile can be picked up and dropped onto another to swap places.
    func reorderable(enabled: Bool,
                     tile: Tile,
                     pageIndex: Int,
                     dragging: Binding<Tile?>,
                     store: DockStore) -> some View {
        modifier(ReorderableTile(enabled: enabled,
                                 tile: tile,
                                 pageIndex: pageIndex,
                                 dragging: dragging,
                                 store: store))
    }
}

struct ReorderableTile: ViewModifier {
    let enabled: Bool
    let tile: Tile
    let pageIndex: Int
    @Binding var dragging: Tile?
    let store: DockStore

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    dragging = tile
                    Haptics.firm()
                    return NSItemProvider(object: tile.id.uuidString as NSString)
                }
                .onDrop(of: [UTType.text],
                        delegate: TileDropDelegate(target: tile,
                                                   pageIndex: pageIndex,
                                                   dragging: $dragging,
                                                   store: store))
        } else {
            content
        }
    }
}

struct TileDropDelegate: DropDelegate {
    let target: Tile
    let pageIndex: Int
    @Binding var dragging: Tile?
    let store: DockStore

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let dragging, dragging.id != target.id,
                  store.pages.indices.contains(pageIndex) else { return }
            var tiles = store.pages[pageIndex].tiles
            guard let from = tiles.firstIndex(where: { $0.id == dragging.id }),
                  let to = tiles.firstIndex(where: { $0.id == target.id }) else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                tiles.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                store.pages[pageIndex].tiles = tiles
            }
            Haptics.tap()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            dragging = nil
            Haptics.success()
        }
        return true
    }
}

/// The slot that opens the picker — highlighted the way a pad menu marks the
/// action tile at the end of the board.
struct AddTileButton: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                        .fill(DockTheme.face(DockTheme.accent))
                        .overlay(GlossOverlay(cornerRadius: size * 0.2, strength: 0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                                .strokeBorder(.white.opacity(0.8), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 5, y: 3)

                    Image(systemName: "plus.app.fill")
                        .font(.system(size: size * 0.34, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                }
                .frame(width: size, height: size)
                .overlay(SelectionCursor(cornerRadius: size * 0.2))

                Text("Add")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DockTheme.subtext)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Works out the fixed slot grid: how many columns and rows fit the board.
struct BoardMetrics {
    let columns: [GridItem]
    let tileSize: CGFloat
    let spacing: CGFloat
    let rowSpacing: CGFloat
    let horizontalPadding: CGFloat
    let slots: Int
    /// Height the grid should sit centred within.
    let boardHeight: CGFloat

    init(width: CGFloat, height: CGFloat, regular: Bool, fullScreen: Bool = false, arrowMargins: Bool = true) {
        let landscape = width > height
        let columnCount: Int
        if regular {
            columnCount = landscape ? 8 : 6
        } else {
            columnCount = landscape ? 6 : 4
        }

        let spacing: CGFloat = regular ? 20 : 14
        // Side arrows live in the margins, so the grid keeps clear of them.
        let padding: CGFloat = arrowMargins ? (fullScreen ? 44 : 52) : 18
        let usable = max(width - padding * 2, 120)
        let size = max(46, (usable - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))

        let labelHeight: CGFloat = 19
        let rowSpacing: CGFloat = regular ? 18 : 12
        let rowHeight = size + labelHeight + rowSpacing
        // A board, not an endless sheet: cap the rows the way a pad home screen does.
        let maxRows = regular ? (landscape ? 4 : 6) : (landscape ? 3 : 5)
        let rows = min(maxRows, max(2, Int((height - 16) / rowHeight)))

        self.tileSize = size
        self.spacing = spacing
        self.rowSpacing = rowSpacing
        self.horizontalPadding = padding
        self.slots = columnCount * rows
        self.boardHeight = height - 16
        self.columns = Array(repeating: GridItem(.fixed(size), spacing: spacing), count: columnCount)
    }
}
