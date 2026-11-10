//
//  MobileDockMacApp.swift
//  MobileDock for Mac — a menu bar companion that lets an iPhone or iPad drive this Mac.
//

import SwiftUI
import AppKit
import ServiceManagement

@main
struct MobileDockMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(delegate.server)
                .environmentObject(delegate.catalog)
                .environmentObject(delegate.executor)
        } label: {
            Image(systemName: delegate.server.devices.isEmpty ? "iphone.gen3" : "iphone.gen3.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environmentObject(delegate.server)
                .environmentObject(delegate.catalog)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let catalog = AppCatalogService()
    lazy var executor = ActionExecutor()
    lazy var server = HostServer(catalog: catalog, executor: executor)

    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        server.start()

        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showWelcome()
            }
        }
    }

    /// A plain hosted window: a SwiftUI `Window` scene stays hidden behind an
    /// accessory-policy menu bar app, so the guide is built by hand instead.
    func showWelcome() {
        if let welcomeWindow {
            NSApp.activate(ignoringOtherApps: true)
            welcomeWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = WelcomeView()
            .environmentObject(server)
            .environmentObject(catalog)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "MobileDock"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        welcomeWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("MobileDock: launch-at-login toggle failed — \(error.localizedDescription)")
            }
        }
    }
}
