//
//  MenuBarPanel.swift
//  MobileDock for Mac — the panel that drops out of the menu bar item.
//

import SwiftUI
import AppKit

struct MenuBarPanel: View {
    @EnvironmentObject private var server: HostServer
    @EnvironmentObject private var catalog: AppCatalogService
    @EnvironmentObject private var executor: ActionExecutor
    @Environment(\.openSettings) private var openSettings

    @State private var pinRevealed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DockTheme.hairline)
            pinSection
            Divider().overlay(DockTheme.hairline)
            devicesSection
            if !AXPermission.isGranted {
                Divider().overlay(DockTheme.hairline)
                permissionBanner
            }
            Divider().overlay(DockTheme.hairline)
            footer
        }
        .frame(width: 320)
        // The panel paints its own light surface, so it must not inherit the
        // system's dark-mode label colours.
        .foregroundStyle(DockTheme.text)
        .background(DockTheme.surfaceGradient)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DockTheme.accentGradient)
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: "square.grid.2x2.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 1) {
                Text("MobileDock").font(.system(size: 14, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(DockTheme.subtext)
            }

            Spacer()

            Circle()
                .fill(server.isRunning ? DockTheme.mint : Color.orange)
                .frame(width: 8, height: 8)
                .shadow(color: (server.isRunning ? DockTheme.mint : .orange).opacity(0.8), radius: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var statusText: String {
        if let error = server.lastError { return error }
        if !server.isRunning { return "Starting…" }
        if server.devices.isEmpty { return "Waiting for a device on this network" }
        return "\(server.devices.count) device\(server.devices.count == 1 ? "" : "s") connected"
    }

    private var pinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PAIRING PIN")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(DockTheme.subtext)
                Spacer()
                Button {
                    server.regeneratePIN()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DockTheme.subtext)
                .help("Generate a new PIN")
            }

            HStack(spacing: 6) {
                ForEach(Array(server.pin.enumerated()), id: \.offset) { _, digit in
                    Text(pinRevealed ? String(digit) : "•")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 38, height: 46)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DockTheme.raised))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DockTheme.hairline))
                }
                Spacer()
                Button {
                    pinRevealed.toggle()
                } label: {
                    Image(systemName: pinRevealed ? "eye" : "eye.slash").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DockTheme.subtext)
            }

            Text("Enter this on your iPhone or iPad to connect.")
                .font(.system(size: 11))
                .foregroundStyle(DockTheme.subtext)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEVICES")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(DockTheme.subtext)

            if server.devices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "wifi").foregroundStyle(DockTheme.subtext)
                    Text("No device connected yet")
                        .font(.system(size: 12))
                        .foregroundStyle(DockTheme.subtext)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(server.devices) { device in
                    DeviceRow(device: device)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var permissionBanner: some View {
        Button {
            AXPermission.request()
            AXPermission.openSettingsPane()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Grant Accessibility access").font(.system(size: 12, weight: .semibold))
                    Text("Needed for emoji, text and window gestures.")
                        .font(.system(size: 10))
                        .opacity(0.75)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DockTheme.accentGradient))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Setup Guide") {
                (NSApp.delegate as? AppDelegate)?.showWelcome()
            }
            Button("Settings…") { openSettings(); NSApp.activate(ignoringOtherApps: true) }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit MobileDock")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(DockTheme.subtext)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// One connected device, with the switches that say what it may do.
private struct DeviceRow: View {
    let device: HostServer.ConnectedDevice
    @State private var expanded = false
    @State private var allowed: [PermissionCategory: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: device.isPad ? "ipad.landscape" : "iphone")
                    .font(.system(size: 14))
                    .foregroundStyle(DockTheme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(.system(size: 12, weight: .medium))
                    Text(device.model).font(.system(size: 10)).foregroundStyle(DockTheme.subtext)
                }
                Spacer()
                Circle().fill(DockTheme.mint).frame(width: 6, height: 6)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DockTheme.subtext)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(PermissionCategory.allCases) { category in
                        Toggle(isOn: binding(for: category)) {
                            Label(category.title, systemImage: category.symbol)
                                .font(.system(size: 11))
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.leading, 30)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 3)
        .onAppear {
            for category in PermissionCategory.allCases {
                allowed[category] = DevicePolicy.shared.isAllowed(category, for: device.id)
            }
        }
    }

    private func binding(for category: PermissionCategory) -> Binding<Bool> {
        Binding(
            get: { allowed[category] ?? true },
            set: { newValue in
                allowed[category] = newValue
                DevicePolicy.shared.set(newValue, category, for: device.id)
            }
        )
    }
}
