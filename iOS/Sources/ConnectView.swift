//
//  ConnectView.swift
//  MobileDock for iOS — discovery list and PIN entry, on the same glossy board.
//

import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var client: DockClient

    var body: some View {
        ZStack {
            BackdropGlow()

            VStack(spacing: 0) {
                header

                if client.isReconnecting {
                    ReconnectBanner()
                        .padding(.bottom, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Group {
                    switch client.phase {
                    case .needsPIN(let hostName):
                        PinEntryView(hostName: hostName)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    default:
                        hostList
                            .transition(.opacity)
                    }
                }
                // On iPad the column stays readable instead of stretching wall to wall.
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: client.phase)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(DockTheme.face(DockTheme.accent))
                    .overlay(GlossOverlay(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.8), lineWidth: 1))
                    .frame(width: 74, height: 74)
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 4)

                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }

            Text("MobileDock")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(DockTheme.text)
                .shadow(color: .white.opacity(0.8), radius: 1, y: 1)

            Text("The third interface for your Mac.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DockTheme.subtext)
        }
        .padding(.top, 46)
        .padding(.bottom, 28)
    }

    private var hostList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("MACS NEARBY")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(DockTheme.subtext)
                if client.hosts.isEmpty {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
            }
            .padding(.horizontal, 26)

            if client.hosts.isEmpty {
                EmptyHostsCard()
                    .padding(.horizontal, 20)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(client.hosts) { host in
                            Button {
                                Haptics.tap()
                                client.connect(to: host)
                            } label: {
                                HostRow(name: host.name,
                                        isConnecting: isConnecting(to: host.name),
                                        note: isConnecting(to: host.name) ? client.statusNote : nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
            }

            Spacer()

            Text("Both devices need to be on the same Wi‑Fi network, with MobileDock running on your Mac.")
                .font(.system(size: 12))
                .foregroundStyle(DockTheme.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
        }
    }

    private func isConnecting(to name: String) -> Bool {
        // Exact match: two hosts can share a prefix when Bonjour appends "(2)".
        if case .connecting(let current) = client.phase { return current == name }
        return false
    }
}

private struct HostRow: View {
    let name: String
    let isConnecting: Bool
    var note: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DockTheme.face(DockTheme.accent))
                    .overlay(GlossOverlay(cornerRadius: 10))
                    .frame(width: 38, height: 38)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DockTheme.text)
                Text(isConnecting ? (note ?? "Connecting…") : "Tap to connect")
                    .font(.system(size: 12))
                    .foregroundStyle(DockTheme.subtext)
            }

            Spacer()

            if isConnecting {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DockTheme.bevel)
            }
        }
        .padding(14)
        .plate(cornerRadius: 18)
    }
}

private struct EmptyHostsCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DockTheme.accent)
            Text("Looking for your Mac…")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DockTheme.text)
            Text("Open MobileDock on the Mac and keep both devices on the same network.")
                .font(.system(size: 12))
                .foregroundStyle(DockTheme.subtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .plate(cornerRadius: 20)
    }
}

// MARK: - PIN entry

struct PinEntryView: View {
    @EnvironmentObject private var client: DockClient
    let hostName: String

    @State private var digits: String = ""
    @FocusState private var focused: Bool

    private let length = 6

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Enter the PIN from")
                    .font(.system(size: 13))
                    .foregroundStyle(DockTheme.subtext)
                Text(hostName)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(DockTheme.text)
            }

            HStack(spacing: 9) {
                ForEach(0..<length, id: \.self) { index in
                    let character = digits.count > index ? String(Array(digits)[index]) : ""
                    Text(character)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(DockTheme.text)
                        .frame(width: 44, height: 56)
                        .plate(cornerRadius: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(DockTheme.accent,
                                              lineWidth: digits.count == index ? 2.4 : 0)
                        )
                }
            }
            .onTapGesture { focused = true }
            .overlay {
                TextField("", text: $digits)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .opacity(0.01)
                    .onChange(of: digits) { _, value in
                        digits = String(value.filter(\.isNumber).prefix(length))
                        if digits.count == length {
                            Haptics.firm()
                            client.submit(pin: digits)
                        }
                    }
            }

            if let error = client.pinError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DockTheme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Button("Choose a different Mac") {
                digits = ""
                client.disconnect()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DockTheme.accent)

            Spacer()
        }
        .padding(.top, 10)
        .onAppear { focused = true }
    }
}

// MARK: - Background

struct BackdropGlow: View {
    var body: some View {
        ZStack {
            DockTheme.board
            RadialGradient(colors: [.white.opacity(0.85), .clear],
                           center: .top, startRadius: 10, endRadius: 420)
                .blendMode(.softLight)
        }
        .ignoresSafeArea()
    }
}
