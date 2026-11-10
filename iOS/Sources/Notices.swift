//
//  Notices.swift
//  MobileDock for iOS — the banners that explain why something is not working.
//

import SwiftUI

/// Shown while the app is finding its way back to a Mac it was already using.
struct ReconnectBanner: View {
    @EnvironmentObject private var client: DockClient

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text("Reconnecting…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DockTheme.text)
                if let name = TokenStore.rememberedHostName {
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundStyle(DockTheme.subtext)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Retry") {
                Haptics.tap()
                client.resume()
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(DockTheme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .plate(cornerRadius: 16)
        .padding(.horizontal, 20)
    }
}

/// Pointer, keyboard and window control all need Accessibility on the Mac.
/// Without it they fail silently, so the panels that rely on it say so.
struct AccessibilityNotice: View {
    @EnvironmentObject private var client: DockClient

    var body: some View {
        if !client.accessibilityGranted {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility is off on the Mac")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Pointer, keyboard and window control do nothing until it is granted.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Button {
                    Haptics.tap()
                    client.requestAccessibility()
                } label: {
                    Text("Open")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DockTheme.accentDeep)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .plate(cornerRadius: 16, fill: DockTheme.warn)
        }
    }
}
