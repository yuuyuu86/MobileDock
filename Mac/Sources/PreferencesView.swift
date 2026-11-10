//
//  PreferencesView.swift
//  MobileDock for Mac — settings window.
//

import SwiftUI
import AppKit

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefs()
                .tabItem { Label("General", systemImage: "gearshape") }
            SecurityPrefs()
                .tabItem { Label("Connection", systemImage: "lock.shield") }
            AboutPrefs()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 440, height: 300)
        .preferredColorScheme(.light)
    }
}

private struct GeneralPrefs: View {
    @EnvironmentObject private var catalog: AppCatalogService
    @AppStorage("hideSystemApps") private var hideSystemApps = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Toggle("Launch MobileDock at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in LaunchAtLogin.isEnabled = newValue }

            Toggle("Hide system utilities from the app list", isOn: $hideSystemApps)

            LabeledContent("Apps found") {
                Text("\(catalog.apps.count)")
            }
            LabeledContent("Shortcuts found") {
                Text("\(catalog.shortcuts.count)")
            }

            HStack {
                Button("Rescan apps") { catalog.refresh() }
                Button("Reload Shortcuts") { catalog.reloadShortcuts() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SecurityPrefs: View {
    @EnvironmentObject private var server: HostServer

    var body: some View {
        Form {
            LabeledContent("Status") {
                Text(server.isRunning ? "Listening" : "Offline")
                    .foregroundStyle(server.isRunning ? .green : .orange)
            }
            LabeledContent("Current PIN") {
                Text(server.pin).monospacedDigit()
            }
            Button("Generate a new PIN") { server.regeneratePIN() }
            Button("Forget all paired devices", role: .destructive) { server.forgetAllDevices() }

            Section {
                Text("MobileDock only ever talks to devices on your local network. Nothing is sent to a server, and no account is required.")
                    .font(.callout)
                    .foregroundStyle(DockTheme.subtext)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutPrefs: View {
    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DockTheme.accentGradient)
                .frame(width: 58, height: 58)
                .overlay(Image(systemName: "square.grid.2x2.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(.black.opacity(0.75)))
            Text("MobileDock").font(.title2.bold())
            Text("Version \(Bundle.main.shortVersion)").foregroundStyle(DockTheme.subtext)
            Text("Turn an iPhone or iPad into a control surface for your Mac.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(DockTheme.subtext)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
