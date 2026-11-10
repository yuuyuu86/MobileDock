//
//  WelcomeView.swift
//  MobileDock for Mac — three-step setup guide shown on first launch.
//

import SwiftUI
import AppKit

struct WelcomeView: View {
    @EnvironmentObject private var server: HostServer
    @EnvironmentObject private var catalog: AppCatalogService
    @State private var step = 0

    private let steps = [
        ("iphone.gen3", "Install MobileDock on your iPhone or iPad",
         "Both devices need to be on the same Wi‑Fi network. The Mac advertises itself automatically — no account, no cloud."),
        ("number.square", "Enter the PIN shown here",
         "Open the app on your device, pick this Mac from the list, then type the six digits. The pairing is remembered afterwards."),
        ("hand.tap", "Build your bar",
         "Drop in apps, Shortcuts, websites and emoji. Swipe between up to eight pages and trigger everything with one tap.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                DockTheme.accentGradient
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.black.opacity(0.78))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(DockTheme.accentGradient)
                        )
                    Text("Welcome to MobileDock")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Your phone becomes the third interface on your desk.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.vertical, 30)
            }

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(DockTheme.raised).frame(width: 34, height: 34)
                            Image(systemName: item.0).font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DockTheme.accent)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Step \(index + 1) — \(item.1)")
                                .font(.system(size: 13, weight: .semibold))
                            Text(item.2)
                                .font(.system(size: 11.5))
                                .foregroundStyle(DockTheme.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Divider().overlay(DockTheme.hairline)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PAIRING PIN")
                            .font(.system(size: 10, weight: .bold)).tracking(1.1)
                            .foregroundStyle(DockTheme.subtext)
                        Text(server.pin)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .tracking(6)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Label(server.isRunning ? "Discoverable on this network" : "Starting…",
                              systemImage: server.isRunning ? "checkmark.circle.fill" : "clock")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(server.isRunning ? DockTheme.mint : .secondary)
                        Label(AXPermission.isGranted ? "Accessibility granted" : "Accessibility needed",
                              systemImage: AXPermission.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AXPermission.isGranted ? DockTheme.mint : DockTheme.accent)
                    }
                }

                if !AXPermission.isGranted {
                    Button {
                        AXPermission.request()
                        AXPermission.openSettingsPane()
                    } label: {
                        Text("Open Privacy & Security…")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DockTheme.accentGradient))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
        }
        .frame(width: 460)
        .foregroundStyle(DockTheme.text)
        .background(DockTheme.surfaceGradient)
        .preferredColorScheme(.light)
    }
}
