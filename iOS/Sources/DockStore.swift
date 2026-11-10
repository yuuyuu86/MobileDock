//
//  DockStore.swift
//  MobileDock for iOS — the user's own bar: pages of tiles, persisted on device.
//

import Foundation
import SwiftUI

enum TileKind: String, Codable, CaseIterable {
    case app, shortcut, website, emoji, control

    var label: String {
        switch self {
        case .app: return "App"
        case .shortcut: return "Shortcut"
        case .website: return "Website"
        case .emoji: return "Emoji"
        case .control: return "Control"
        }
    }

    var systemImage: String {
        switch self {
        case .app: return "square.grid.2x2"
        case .shortcut: return "sparkles"
        case .website: return "globe"
        case .emoji: return "face.smiling"
        case .control: return "slider.horizontal.3"
        }
    }
}

struct Tile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: TileKind
    var title: String
    /// bundle ID, shortcut name, URL, emoji character, or a WindowAction/MediaKey raw value.
    var payload: String
    /// SF Symbol name drawn on the tile. Emoji tiles ignore it and draw their payload.
    var symbol: String?
    var tint: String?

    init(id: UUID = UUID(), kind: TileKind, title: String, payload: String, symbol: String? = nil, tint: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.payload = payload
        self.symbol = SymbolLibrary.validated(symbol)
        self.tint = tint
    }

    init(control action: WindowAction, title: String, tint: TileColor) {
        self.init(kind: .control, title: title, payload: action.rawValue,
                  symbol: ControlCatalog.symbol(for: action.rawValue), tint: tint.rawValue)
    }

    init(media key: MediaKey, title: String, tint: TileColor) {
        let payload = "media." + key.rawValue
        self.init(kind: .control, title: title, payload: payload,
                  symbol: ControlCatalog.symbol(for: payload), tint: tint.rawValue)
    }

    var color: Color {
        guard let tint, let color = TileColor(rawValue: tint) else { return TileColor.graphite.color }
        return color.color
    }

    /// What actually gets drawn: the tile's own symbol, else the one its action
    /// implies, else the kind's default.
    var resolvedSymbol: String {
        symbol ?? ControlCatalog.symbol(for: payload) ?? kind.systemImage
    }

    // Tolerates bars saved by the emoji-labelled builds: an old "glyph" that is
    // not an SF Symbol name is dropped, and the kind's default symbol takes over.
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, payload, symbol, glyph, tint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(TileKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        payload = try container.decode(String.self, forKey: .payload)
        tint = try container.decodeIfPresent(String.self, forKey: .tint)
        let stored = try container.decodeIfPresent(String.self, forKey: .symbol)
            ?? container.decodeIfPresent(String.self, forKey: .glyph)
        symbol = SymbolLibrary.validated(stored)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(payload, forKey: .payload)
        try container.encodeIfPresent(symbol, forKey: .symbol)
        try container.encodeIfPresent(tint, forKey: .tint)
    }
}

enum TileColor: String, Codable, CaseIterable {
    case amber, coral, mint, sky, violet, rose, lime, graphite

    var color: Color {
        switch self {
        case .amber: return Color(red: 0.98, green: 0.68, blue: 0.24)
        case .coral: return Color(red: 0.97, green: 0.44, blue: 0.36)
        case .mint: return Color(red: 0.30, green: 0.83, blue: 0.64)
        case .sky: return Color(red: 0.34, green: 0.63, blue: 0.98)
        case .violet: return Color(red: 0.62, green: 0.47, blue: 0.98)
        case .rose: return Color(red: 0.96, green: 0.45, blue: 0.72)
        case .lime: return Color(red: 0.72, green: 0.87, blue: 0.32)
        case .graphite: return Color(red: 0.30, green: 0.31, blue: 0.35)
        }
    }
}

struct DockPage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// SF Symbol name shown in the page pill and the iPad sidebar.
    var symbol: String
    var tiles: [Tile]

    init(id: UUID = UUID(), name: String, symbol: String, tiles: [Tile]) {
        self.id = id
        self.name = name
        self.symbol = SymbolLibrary.validated(symbol) ?? "square.grid.2x2"
        self.tiles = tiles
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, glyph, tiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        tiles = try container.decodeIfPresent([Tile].self, forKey: .tiles) ?? []
        let stored = try container.decodeIfPresent(String.self, forKey: .symbol)
            ?? container.decodeIfPresent(String.self, forKey: .glyph)
        symbol = SymbolLibrary.validated(stored) ?? "square.grid.2x2"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(tiles, forKey: .tiles)
    }
}

/// Every Mac control a tile can fire, with the SF Symbol that represents it.
/// One table so the picker, the starter pages and the icon fallback agree.
enum ControlCatalog {

    enum Category: String, CaseIterable, Identifiable {
        case window, spaces, edit, tabs, system, media

        var id: String { rawValue }

        var title: String {
            switch self {
            case .window: return "Window"
            case .spaces: return "Spaces & Apps"
            case .edit: return "Edit"
            case .tabs: return "Tabs & Documents"
            case .system: return "System"
            case .media: return "Media"
            }
        }

        var symbol: String {
            switch self {
            case .window: return "macwindow"
            case .spaces: return "rectangle.3.group"
            case .edit: return "text.cursor"
            case .tabs: return "doc.on.doc"
            case .system: return "gearshape"
            case .media: return "play.circle"
            }
        }
    }

    struct Action: Identifiable {
        var id: String { payload }
        let title: String
        let symbol: String
        let payload: String
        let category: Category
    }

    private static func window(_ title: String, _ symbol: String, _ action: WindowAction, _ category: Category) -> Action {
        Action(title: title, symbol: symbol, payload: action.rawValue, category: category)
    }

    private static func media(_ title: String, _ symbol: String, _ key: MediaKey) -> Action {
        Action(title: title, symbol: symbol, payload: "media." + key.rawValue, category: .media)
    }

    private static func system(_ title: String, _ symbol: String, _ action: SystemAction, _ category: Category) -> Action {
        Action(title: title, symbol: symbol, payload: "system." + action.rawValue, category: category)
    }

    static let all: [Action] = [
        // Window
        window("Minimize", "arrow.down.right.and.arrow.up.left", .minimize, .window),
        window("Zoom", "arrow.up.left.and.arrow.down.right", .maximize, .window),
        window("Full Screen", "arrow.up.left.and.arrow.down.right.rectangle", .fullscreen, .window),
        window("Close Window", "xmark.rectangle", .closeWindow, .window),
        window("Hide App", "eye.slash", .hide, .window),
        window("Next Window", "macwindow.badge.plus", .nextWindow, .window),
        window("Left Half", "rectangle.lefthalf.filled", .tileLeft, .window),
        window("Right Half", "rectangle.righthalf.filled", .tileRight, .window),
        window("Top Half", "rectangle.tophalf.filled", .tileTop, .window),
        window("Bottom Half", "rectangle.bottomhalf.filled", .tileBottom, .window),
        window("Center", "rectangle.center.inset.filled", .center, .window),

        // Spaces & apps
        window("Mission Control", "rectangle.3.group.fill", .missionControl, .spaces),
        window("App Exposé", "macwindow.on.rectangle", .appExpose, .spaces),
        window("Show Desktop", "menubar.dock.rectangle", .showDesktop, .spaces),
        window("Space Left", "arrow.left.square", .spaceLeft, .spaces),
        window("Space Right", "arrow.right.square", .spaceRight, .spaces),
        window("Next App", "arrow.right.to.line", .nextApp, .spaces),
        window("Previous App", "arrow.left.to.line", .previousApp, .spaces),
        system("Spotlight", "magnifyingglass.circle", .spotlight, .spaces),
        system("Launchpad", "square.grid.3x3.fill", .launchpad, .spaces),
        system("Force Quit", "exclamationmark.octagon", .forceQuit, .spaces),

        // Edit menu
        system("Copy", "doc.on.doc", .copy, .edit),
        system("Paste", "doc.on.clipboard", .paste, .edit),
        system("Cut", "scissors", .cut, .edit),
        system("Undo", "arrow.uturn.backward", .undo, .edit),
        system("Redo", "arrow.uturn.forward", .redo, .edit),
        system("Select All", "selection.pin.in.out", .selectAll, .edit),
        system("Save", "square.and.arrow.down", .save, .edit),
        system("Find", "magnifyingglass", .find, .edit),
        system("Emoji Picker", "face.smiling", .emojiPicker, .edit),

        // Tabs & documents
        system("New Tab", "plus.rectangle.on.rectangle", .newTab, .tabs),
        system("Close Tab", "xmark.rectangle.fill", .closeTab, .tabs),
        system("Next Tab", "chevron.right.square", .nextTab, .tabs),
        system("Previous Tab", "chevron.left.square", .previousTab, .tabs),
        system("Reopen Tab", "arrow.uturn.left.square", .reopenTab, .tabs),
        system("New Window", "macwindow.badge.plus", .newWindow, .tabs),
        system("Refresh", "arrow.clockwise", .refresh, .tabs),
        system("Zoom In", "plus.magnifyingglass", .zoomIn, .tabs),
        system("Zoom Out", "minus.magnifyingglass", .zoomOut, .tabs),
        system("Quit App", "power", .quitApp, .tabs),

        // System
        system("Lock Screen", "lock.fill", .lockScreen, .system),
        system("Sleep Display", "moon.fill", .sleepDisplay, .system),
        system("Screenshot Area", "rectangle.dashed", .screenshotRegion, .system),
        system("Screenshot Screen", "camera.viewfinder", .screenshotScreen, .system),
        system("Screenshot Tools", "camera.on.rectangle", .screenshotTools, .system),
        media("Brightness Up", "sun.max.fill", .brightnessUp),
        media("Brightness Down", "sun.min.fill", .brightnessDown),
        media("Keyboard Light +", "keyboard.badge.ellipsis", .keyboardLightUp),
        media("Keyboard Light −", "keyboard", .keyboardLightDown),

        // Media
        media("Play / Pause", "playpause.fill", .playPause),
        media("Next Track", "forward.fill", .next),
        media("Previous Track", "backward.fill", .previous),
        media("Volume Up", "speaker.wave.3.fill", .volumeUp),
        media("Volume Down", "speaker.wave.1.fill", .volumeDown),
        media("Mute", "speaker.slash.fill", .mute)
    ]

    static func actions(in category: Category) -> [Action] {
        all.filter { $0.category == category }
    }

    static func symbol(for payload: String) -> String? {
        all.first { $0.payload == payload }?.symbol
    }
}

/// The SF Symbols offered in the pickers, and the check that keeps a stored
/// name from silently rendering as a blank tile.
enum SymbolLibrary {

    static func validated(_ name: String?) -> String? {
        guard let name, !name.isEmpty, UIImage(systemName: name) != nil else { return nil }
        return name
    }

    static let pages: [String] = [
        "square.grid.2x2", "briefcase.fill", "globe", "slider.horizontal.3",
        "house.fill", "star.fill", "bolt.fill", "paintbrush.fill",
        "hammer.fill", "music.note", "camera.fill", "gamecontroller.fill",
        "book.fill", "chart.bar.fill", "leaf.fill", "moon.fill"
    ]

    static let tiles: [String] = [
        "square.grid.2x2", "sparkles", "globe", "magnifyingglass", "envelope.fill",
        "message.fill", "calendar", "checklist", "folder.fill", "doc.text.fill",
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "cloud.fill",
        "bolt.fill", "star.fill", "heart.fill", "flame.fill", "bell.fill",
        "cart.fill", "creditcard.fill", "map.fill", "airplane", "car.fill",
        "cup.and.saucer.fill", "fork.knife", "dumbbell.fill", "music.note",
        "headphones", "play.fill", "camera.fill", "photo.fill", "paintpalette.fill",
        "hammer.fill", "wrench.and.screwdriver.fill", "gearshape.fill", "lock.fill",
        "person.2.fill", "brain.head.profile", "lightbulb.fill", "paperplane.fill"
    ]
}

@MainActor
final class DockStore: ObservableObject {

    static let maxPages = 8

    @Published var pages: [DockPage] { didSet { persist() } }
    @Published var currentPage: Int = 0
    @Published var isEditing = false
    /// Dock-only mode: every bit of chrome steps aside and the tiles take the screen.
    @Published var isFullScreen = false
    @Published var favoriteEmoji: [String] {
        didSet { UserDefaults.standard.set(favoriteEmoji, forKey: Keys.emoji) }
    }

    private enum Keys {
        /// The layout before bars were kept per Mac; still read once, to migrate.
        static let legacyPages = "dock.pages.v1"
        static let emoji = "dock.emoji.v1"
        static func pages(for host: String?) -> String {
            guard let host, !host.isEmpty else { return "dock.pages.v2.default" }
            return "dock.pages.v2." + host
        }
    }

    /// Each Mac gets its own bar: a work machine and a home machine rarely want
    /// the same tiles.
    private(set) var hostKey: String?

    init() {
        pages = DockStore.load(for: nil) ?? DockStore.starterPages
        favoriteEmoji = UserDefaults.standard.stringArray(forKey: Keys.emoji) ?? DockStore.starterEmoji
    }

    private static func load(for host: String?) -> [DockPage]? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.pages(for: host)),
           let decoded = try? JSONDecoder().decode([DockPage].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        // First time on this Mac: inherit whatever the device had before.
        if let data = defaults.data(forKey: Keys.legacyPages),
           let decoded = try? JSONDecoder().decode([DockPage].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        return nil
    }

    /// Swap the bar over when the connected Mac changes.
    func activate(host: String?) {
        guard host != hostKey else { return }
        persist()                      // keep whatever the previous Mac had
        hostKey = host
        currentPage = 0
        if let local = DockStore.load(for: host) {
            pages = local
        } else if let cloud = CloudSync.shared.pull(host: host),
                  let decoded = try? JSONDecoder().decode([DockPage].self, from: cloud),
                  !decoded.isEmpty {
            pages = decoded
        } else {
            pages = DockStore.starterPages
        }
    }

    // MARK: Defaults

    /// The emoji bar types real emoji into the Mac, so these stay characters.
    static let starterEmoji = ["👍", "🎉", "🔥", "✅", "🙏", "😂", "❤️", "🚀", "☕️", "👀", "💡", "🤝"]

    static var starterPages: [DockPage] {
        [
            DockPage(name: "Dock", symbol: "square.grid.2x2", tiles: []),
            DockPage(name: "Work", symbol: "briefcase.fill", tiles: []),
            DockPage(name: "Web", symbol: "globe", tiles: [
                Tile(kind: .website, title: "Search", payload: "https://www.google.com",
                     symbol: "magnifyingglass", tint: TileColor.sky.rawValue),
                Tile(kind: .website, title: "Mail", payload: "https://mail.google.com",
                     symbol: "envelope.fill", tint: TileColor.rose.rawValue)
            ]),
            DockPage(name: "Control", symbol: "slider.horizontal.3", tiles: [
                Tile(control: .minimize, title: "Minimize", tint: .graphite),
                Tile(control: .maximize, title: "Zoom", tint: .graphite),
                Tile(control: .missionControl, title: "Mission", tint: .violet),
                Tile(media: .playPause, title: "Play", tint: .mint),
                Tile(media: .volumeDown, title: "Vol −", tint: .graphite),
                Tile(media: .volumeUp, title: "Vol +", tint: .graphite)
            ])
        ]
    }

    /// Fills the first page the first time a Mac connects, so the bar is never empty.
    func seedIfEmpty(with catalog: Catalog) {
        guard pages.indices.contains(0), pages[0].tiles.isEmpty else { return }
        // Only seed apps we can actually name — agents that flash to the front
        // otherwise land on the bar as raw bundle identifiers.
        let known = Set(catalog.apps.map(\.bundleID))
        let preferred = (catalog.recents + catalog.running).filter { known.contains($0) }
        var seen = Set<String>()
        let bundleIDs = preferred.filter { seen.insert($0).inserted }.prefix(8).map { $0 }
        guard !bundleIDs.isEmpty else { return }
        let palette = TileColor.allCases
        pages[0].tiles = bundleIDs.enumerated().map { index, bundleID in
            Tile(kind: .app,
                 title: catalog.apps.first { $0.bundleID == bundleID }?.name ?? bundleID,
                 payload: bundleID,
                 symbol: nil,
                 tint: palette[index % palette.count].rawValue)
        }
    }

    // MARK: Mutation

    var page: DockPage? {
        pages.indices.contains(currentPage) ? pages[currentPage] : pages.first
    }

    func add(_ tile: Tile, toPage index: Int? = nil) {
        let target = index ?? currentPage
        guard pages.indices.contains(target) else { return }
        pages[target].tiles.append(tile)
    }

    func remove(_ tile: Tile) {
        for index in pages.indices {
            pages[index].tiles.removeAll { $0.id == tile.id }
        }
    }

    func update(_ tile: Tile) {
        for pageIndex in pages.indices {
            if let tileIndex = pages[pageIndex].tiles.firstIndex(where: { $0.id == tile.id }) {
                pages[pageIndex].tiles[tileIndex] = tile
            }
        }
    }

    func move(from source: IndexSet, to destination: Int, page index: Int) {
        guard pages.indices.contains(index) else { return }
        pages[index].tiles.move(fromOffsets: source, toOffset: destination)
    }

    func addPage() {
        guard pages.count < Self.maxPages else { return }
        pages.append(DockPage(name: "Page \(pages.count + 1)", symbol: "star.fill", tiles: []))
        currentPage = pages.count - 1
    }

    func removePage(at index: Int) {
        guard pages.count > 1, pages.indices.contains(index) else { return }
        pages.remove(at: index)
        currentPage = min(currentPage, pages.count - 1)
    }

    /// The first page holding a tile for this app, used by the follow-the-front-app setting.
    func page(containing bundleID: String) -> Int? {
        pages.firstIndex { page in
            page.tiles.contains { $0.kind == .app && $0.payload == bundleID }
        }
    }

    /// Replaces the whole bar, used by the JSON import.
    func replacePages(_ newPages: [DockPage]) {
        guard !newPages.isEmpty else { return }
        pages = newPages
        currentPage = 0
    }

    func toggleFavorite(emoji: String) {
        if let index = favoriteEmoji.firstIndex(of: emoji) {
            favoriteEmoji.remove(at: index)
        } else {
            favoriteEmoji.insert(emoji, at: 0)
            if favoriteEmoji.count > 24 { favoriteEmoji.removeLast() }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pages) else { return }
        UserDefaults.standard.set(data, forKey: Keys.pages(for: hostKey))
        CloudSync.shared.push(pages: data, host: hostKey)
    }
}
