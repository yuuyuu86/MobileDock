//
//  Theme.swift
//  MobileDock — the glossy pad palette shared by the Mac panel and the iOS home screen.
//
//  The look is modelled on a game-pad style home menu: a pale brushed background,
//  white bevelled tiles with a highlight across the top, and a row of round
//  buttons along the bottom. All artwork here is drawn with gradients and shapes.
//

import SwiftUI

enum DockTheme {

    // MARK: Surfaces

    static let bg = Color(red: 0.937, green: 0.945, blue: 0.953)
    static let bgDeep = Color(red: 0.808, green: 0.827, blue: 0.851)
    static let panel = Color.white
    static let panelDeep = Color(red: 0.902, green: 0.914, blue: 0.929)
    static let bevel = Color(red: 0.647, green: 0.671, blue: 0.706)

    // MARK: Ink

    static let text = Color(red: 0.216, green: 0.235, blue: 0.263)
    static let subtext = Color(red: 0.451, green: 0.478, blue: 0.518)

    // MARK: Accents

    static let accent = Color(red: 0.125, green: 0.604, blue: 0.878)
    static let accentDeep = Color(red: 0.055, green: 0.404, blue: 0.667)
    static let mint = Color(red: 0.259, green: 0.733, blue: 0.408)
    static let warn = Color(red: 0.965, green: 0.639, blue: 0.145)
    static let danger = Color(red: 0.898, green: 0.325, blue: 0.310)

    // MARK: Aliases kept for the Mac views

    static let ink = bg
    static let surface = panel
    static let raised = panelDeep
    static let hairline = Color.black.opacity(0.10)

    // MARK: Gradients

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .top, endPoint: .bottom)
    }

    static var surfaceGradient: LinearGradient {
        LinearGradient(colors: [bg, bgDeep], startPoint: .top, endPoint: .bottom)
    }

    /// The brushed board the whole home screen sits on.
    static var board: LinearGradient {
        LinearGradient(stops: [
            .init(color: Color(red: 0.965, green: 0.969, blue: 0.976), location: 0),
            .init(color: Color(red: 0.902, green: 0.914, blue: 0.929), location: 0.45),
            .init(color: Color(red: 0.831, green: 0.847, blue: 0.867), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    /// Face of a raised tile: bright at the top, a touch of shade at the base.
    static func face(_ color: Color) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: color.opacity(0.98), location: 0),
            .init(color: color, location: 0.52),
            .init(color: color.opacity(0.86), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// The highlight that sells the moulded-plastic look: a soft white arc across the
/// top half of a tile, plus a thin light rim.
struct GlossOverlay: View {
    var cornerRadius: CGFloat
    var strength: Double = 0.75

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(strength), location: 0),
                        .init(color: .white.opacity(strength * 0.18), location: 0.42),
                        .init(color: .white.opacity(0), location: 0.55)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .blendMode(.softLight)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.15)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Bevelled, glossy plate used for tiles, cards and the bottom bar.
    func plate(cornerRadius: CGFloat,
               fill: Color = DockTheme.panel,
               shadow: Bool = true,
               gloss: Double = 0.75) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DockTheme.face(fill))
        )
        .overlay(GlossOverlay(cornerRadius: cornerRadius, strength: gloss))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(DockTheme.bevel.opacity(0.55), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(shadow ? 0.18 : 0), radius: shadow ? 6 : 0, y: shadow ? 3 : 0)
    }
}
