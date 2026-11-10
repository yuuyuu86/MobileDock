//
//  CloudSync.swift
//  MobileDock for iOS — keeps a bar in step across the devices you use.
//
//  iCloud key-value storage carries the layout when the app is signed with an
//  iCloud capability; without it the calls are harmless no-ops and the file
//  export below is the way to move a bar between devices.
//

import Foundation
import SwiftUI

final class CloudSync {
    static let shared = CloudSync()

    private let store = NSUbiquitousKeyValueStore.default
    private let enabledKey = "sync.icloud.enabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// True only when the device is actually signed into iCloud and the app was
    /// built with the capability; otherwise syncing silently does nothing.
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func key(for host: String?) -> String {
        guard let host, !host.isEmpty else { return "pages.default" }
        return "pages." + host
    }

    func push(pages: Data, host: String?) {
        guard isEnabled, isAvailable else { return }
        store.set(pages, forKey: key(for: host))
        store.synchronize()
    }

    func pull(host: String?) -> Data? {
        guard isEnabled, isAvailable else { return nil }
        return store.data(forKey: key(for: host))
    }

    func observe(_ handler: @escaping () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { _ in handler() }
        store.synchronize()
    }

    var statusText: String {
        guard isEnabled else { return "Off" }
        return isAvailable ? "On" : "Unavailable on this build"
    }
}

// MARK: - File export / import

/// Works on any build, including one signed with a personal team: the bar is
/// written out as JSON and can be handed to another device however you like.
enum BarDocument {
    static func export(pages: [DockPage]) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(pages) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MobileDock-bar.json")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static func load(from url: URL) -> [DockPage]? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([DockPage].self, from: data)
    }
}
