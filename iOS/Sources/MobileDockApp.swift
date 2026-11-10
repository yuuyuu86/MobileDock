//
//  MobileDockApp.swift
//  MobileDock for iPhone & iPad — the remote side of the dock.
//

import SwiftUI

@main
struct MobileDockApp: App {
    @StateObject private var client = DockClient()
    @StateObject private var store = DockStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(DockTheme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: DockStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            DockTheme.board.ignoresSafeArea()

            Group {
                if client.isConnected {
                    DockBarView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    ConnectView()
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: client.isConnected)

            ToastOverlay()
        }
        .onAppear { client.startBrowsing() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { client.resume() }
        }
        .onChange(of: client.host?.name) { _, name in
            store.activate(host: name)
        }
        .onChange(of: client.catalog) { _, catalog in
            if let catalog { store.seedIfEmpty(with: catalog) }
        }
    }
}

struct ToastOverlay: View {
    @EnvironmentObject private var client: DockClient

    var body: some View {
        VStack {
            if let toast = client.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(DockTheme.face(DockTheme.accent))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                    )
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: client.toast)
        .allowsHitTesting(false)
    }
}
