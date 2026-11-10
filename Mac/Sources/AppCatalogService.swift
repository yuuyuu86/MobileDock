//
//  AppCatalogService.swift
//  MobileDock for Mac — keeps the list of launchable apps, their icons, and a
//  timeline of recently used apps so the remote can mirror them.
//

import Foundation
import AppKit
import Combine

@MainActor
final class AppCatalogService: ObservableObject {

    @Published private(set) var apps: [AppInfo] = []
    @Published private(set) var shortcuts: [ShortcutInfo] = []
    @Published private(set) var recents: [String] = []
    @Published private(set) var runningBundleIDs: [String] = []
    @Published private(set) var frontAppBundleID: String?

    /// Fired whenever the volatile part of the catalog (front app, recents) moves.
    var onChange: (() -> Void)?

    private var iconCache: [String: Data] = [:]
    private var observers: [NSObjectProtocol] = []
    private let maxRecents = 24

    private let searchPaths: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications"
    ]

    init() {
        observeWorkspace()
        refresh()
        reloadShortcuts()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
    }

    // MARK: Observation

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.noteActivation(of: bundleID) }
        })

        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRunning() }
        })

        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRunning() }
        })
    }

    private func noteActivation(of bundleID: String) {
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        frontAppBundleID = bundleID
        recents.removeAll { $0 == bundleID }
        recents.insert(bundleID, at: 0)
        if recents.count > maxRecents { recents.removeLast(recents.count - maxRecents) }
        refreshRunning()
    }

    private func refreshRunning() {
        runningBundleIDs = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
        for index in apps.indices {
            apps[index].isRunning = runningBundleIDs.contains(apps[index].bundleID)
        }
        onChange?()
    }

    // MARK: Catalog

    func refresh() {
        var found: [String: AppInfo] = [:]
        let fm = FileManager.default

        for path in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let full = path + "/" + entry
                guard let bundle = Bundle(path: full), let bundleID = bundle.bundleIdentifier else { continue }
                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? (entry as NSString).deletingPathExtension
                found[bundleID] = AppInfo(bundleID: bundleID, name: name, path: full, isRunning: false)
            }
        }

        // Anything running from an unusual location still deserves a tile.
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, found[bundleID] == nil else { continue }
            found[bundleID] = AppInfo(bundleID: bundleID,
                                      name: app.localizedName ?? bundleID,
                                      path: app.bundleURL?.path ?? "",
                                      isRunning: true)
        }

        apps = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        refreshRunning()
    }

    func reloadShortcuts() {
        Task.detached(priority: .utility) {
            let names = Shell.run("/usr/bin/shortcuts", ["list"])?
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty } ?? []
            await MainActor.run {
                self.shortcuts = names.map(ShortcutInfo.init(name:))
            }
        }
    }

    func snapshot(host: HostInfo) -> Catalog {
        Catalog(host: host,
                apps: apps,
                shortcuts: shortcuts,
                running: runningBundleIDs,
                recents: recents,
                frontApp: frontAppBundleID,
                accessibilityGranted: AXPermission.isGranted)
    }

    // MARK: Icons

    func icons(for bundleIDs: [String]) -> [IconPayload] {
        bundleIDs.compactMap { bundleID in
            if let cached = iconCache[bundleID] {
                return IconPayload(bundleID: bundleID, png: cached)
            }
            guard let png = renderIcon(bundleID: bundleID) else { return nil }
            iconCache[bundleID] = png
            return IconPayload(bundleID: bundleID, png: png)
        }
    }

    private func renderIcon(bundleID: String) -> Data? {
        let path: String?
        if let app = apps.first(where: { $0.bundleID == bundleID }), !app.path.isEmpty {
            path = app.path
        } else {
            path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        }
        guard let path else { return nil }

        let icon = NSWorkspace.shared.icon(forFile: path)
        let side: CGFloat = 128
        let target = NSImage(size: NSSize(width: side, height: side))
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                  from: .zero,
                  operation: .sourceOver,
                  fraction: 1)
        target.unlockFocus()

        guard let tiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - Tiny process helper

enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String], capture: Bool = true) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        if capture {
            process.standardOutput = pipe
            process.standardError = Pipe()
        }
        do {
            try process.run()
        } catch {
            return nil
        }
        guard capture else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
