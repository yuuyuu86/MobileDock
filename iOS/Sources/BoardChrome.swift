//
//  BoardChrome.swift
//  MobileDock for iOS — the furniture around the tile grid: empty slots, the page
//  band, the big side arrows, the selection frame and the flat bottom icons.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Empty slot

/// The faint plate that marks a free position on the board. A dragged tile can
/// be dropped straight onto one.
struct EmptySlotView: View {
    let size: CGFloat
    var slotIndex: Int
    var pageIndex: Int
    @Binding var dragging: Tile?
    var store: DockStore

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                        .strokeBorder(DockTheme.bevel.opacity(0.22), lineWidth: 0.6)
                        .blur(radius: 0.5)
                )
                .frame(width: size, height: size)

            Color.clear.frame(height: 13)
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
            MainActor.assumeIsolated { moveDraggedTile() }
            return true
        }
    }

    private func moveDraggedTile() {
        defer { dragging = nil }
        guard let dragging, store.pages.indices.contains(pageIndex) else { return }
        var tiles = store.pages[pageIndex].tiles
        guard let from = tiles.firstIndex(where: { $0.id == dragging.id }) else { return }
        let target = min(max(slotIndex, 0), tiles.count - 1)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            tiles.move(fromOffsets: IndexSet(integer: from),
                       toOffset: target > from ? target + 1 : target)
            store.pages[pageIndex].tiles = tiles
        }
        Haptics.success()
    }
}

// MARK: - Selection frame

/// Four corner brackets marking the highlighted tile.
struct SelectionFrame: Shape {
    var inset: CGFloat = 0
    var arm: CGFloat = 0.3

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let length = min(r.width, r.height) * arm
        var path = Path()

        path.move(to: CGPoint(x: r.minX, y: r.minY + length))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX + length, y: r.minY))

        path.move(to: CGPoint(x: r.maxX - length, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + length))

        path.move(to: CGPoint(x: r.maxX, y: r.maxY - length))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX - length, y: r.maxY))

        path.move(to: CGPoint(x: r.minX + length, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - length))

        return path
    }
}

/// The lit cursor drawn over the focused tile: a soft blue wash plus glowing brackets.
struct SelectionCursor: View {
    var cornerRadius: CGFloat
    var inset: CGFloat = -5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DockTheme.accent.opacity(0.16))

            SelectionFrame(inset: inset, arm: 0.34)
                .stroke(DockTheme.accent.opacity(0.8),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .blur(radius: 5)

            SelectionFrame(inset: inset, arm: 0.34)
                .stroke(
                    LinearGradient(colors: [Color(red: 0.42, green: 0.82, blue: 1.0),
                                            Color(red: 0.09, green: 0.56, blue: 0.93)],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Page band

/// The little white cloud at the top holding one square per page.
struct PageBand: View {
    let count: Int
    let current: Int
    var onSelect: (Int) -> Void
    var onAdd: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index == current ? DockTheme.accent : Color(red: 0.78, green: 0.80, blue: 0.82))
                    .frame(width: index == current ? 16 : 9, height: 9)
                    .shadow(color: .black.opacity(0.08), radius: 0.5, y: 0.5)
                    .onTapGesture { onSelect(index) }
            }
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(DockTheme.subtext)
                        .frame(width: 14, height: 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.92))
                .overlay(Capsule().strokeBorder(.white, lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: current)
    }
}

// MARK: - Side arrows

/// The oversized pale triangle that turns the page.
struct PageArrow: View {
    enum Direction { case left, right }

    let direction: Direction
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Triangle(direction: direction)
                    .fill(
                        LinearGradient(colors: [Color(red: 0.44, green: 0.82, blue: 1.0),
                                                Color(red: 0.11, green: 0.58, blue: 0.92)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .padding(5)

                Triangle(direction: direction)
                    .stroke(Color.white, lineWidth: 3)

                Triangle(direction: direction)
                    .stroke(DockTheme.bevel.opacity(0.5), lineWidth: 1)
            }
            .frame(width: 40, height: 92)
            .shadow(color: .black.opacity(0.14), radius: 3, x: direction == .left ? 2 : -2, y: 1)
            .opacity(enabled ? 1 : 0.22)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .allowsHitTesting(enabled)
    }

    struct Triangle: Shape {
        let direction: Direction

        func path(in rect: CGRect) -> Path {
            var path = Path()
            switch direction {
            case .left:
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            case .right:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            }
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Bottom icons

/// Flat, brightly coloured glyphs sitting straight on the board — no bar behind them.
struct BoardIcon: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(colors: [color.opacity(0.95), color],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 42, height: 42)
                        .shadow(color: color.opacity(0.35), radius: selected ? 6 : 2, y: 2)

                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(selected ? 1.1 : 1)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(DockTheme.text.opacity(selected ? 0.45 : 0))
                        .frame(width: 18, height: 2.5)
                        .offset(y: 5)
                }

                Text(title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(selected ? DockTheme.text : DockTheme.subtext)
                    .opacity(selected ? 1 : 0.75)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)
    }
}

// MARK: - Footer

/// The footer plate: the top edge sits high at both ends and dips through a
/// symmetric valley in the middle, so the clock reads as sitting in the dip.
struct FooterEdge: Shape {
    /// Drop from the top of the rect at the left and right ends.
    var shoulderDrop: CGFloat = 0
    /// Drop at the centre of the span. Left nil, it scales with the width so a
    /// wide landscape footer dips as much as the design wants.
    var valleyDrop: CGFloat? = nil
    /// Fraction of the width that stays flat at each end.
    var flat: CGFloat = 0.27
    /// Fraction of the width each S-transition runs over.
    var run: CGFloat = 0.13

    static func valley(for width: CGFloat) -> CGFloat {
        min(20, max(10, width * 0.022))
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let shoulder = rect.minY + shoulderDrop
        let valley = rect.minY + (valleyDrop ?? Self.valley(for: width))
        let transition = width * run

        let leftFlatEnd = rect.minX + width * flat
        let leftValley = leftFlatEnd + transition
        let rightFlatStart = rect.maxX - width * flat
        let rightValley = rightFlatStart - transition

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: shoulder))
        path.addLine(to: CGPoint(x: leftFlatEnd, y: shoulder))
        path.addCurve(to: CGPoint(x: leftValley, y: valley),
                      control1: CGPoint(x: leftFlatEnd + transition * 0.55, y: shoulder),
                      control2: CGPoint(x: leftValley - transition * 0.55, y: valley))
        path.addLine(to: CGPoint(x: rightValley, y: valley))
        path.addCurve(to: CGPoint(x: rightFlatStart, y: shoulder),
                      control1: CGPoint(x: rightValley + transition * 0.55, y: valley),
                      control2: CGPoint(x: rightFlatStart - transition * 0.55, y: shoulder))
        path.addLine(to: CGPoint(x: rect.maxX, y: shoulder))
        return path
    }
}

struct FooterShape: Shape {
    var shoulderDrop: CGFloat = 0
    var valleyDrop: CGFloat? = nil
    var flat: CGFloat = 0.27
    var run: CGFloat = 0.13

    func path(in rect: CGRect) -> Path {
        var path = FooterEdge(shoulderDrop: shoulderDrop, valleyDrop: valleyDrop,
                              flat: flat, run: run).path(in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The lit edge that runs along the top of the footer.
struct FooterGlowEdge: View {
    var shoulderDrop: CGFloat = 0
    var valleyDrop: CGFloat? = nil
    var flat: CGFloat = 0.27
    var run: CGFloat = 0.13

    private var edge: FooterEdge {
        FooterEdge(shoulderDrop: shoulderDrop, valleyDrop: valleyDrop, flat: flat, run: run)
    }

    var body: some View {
        ZStack {
            edge.stroke(DockTheme.accent.opacity(0.55), lineWidth: 6).blur(radius: 5)
            edge.stroke(
                LinearGradient(colors: [Color(red: 0.36, green: 0.78, blue: 1.0),
                                        Color(red: 0.10, green: 0.58, blue: 0.92)],
                               startPoint: .leading, endPoint: .trailing),
                lineWidth: 2.2
            )
            edge.stroke(.white.opacity(0.9), lineWidth: 0.8).offset(y: 1.6)
        }
        .allowsHitTesting(false)
    }
}

/// The big round button that sits at each end of the footer.
struct FooterRoundButton: View {
    let symbol: String
    var label: LocalizedStringKey? = nil
    var tint: Color = DockTheme.accent
    var active: Bool = false
    var diameter: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.white, Color(red: 0.88, green: 0.91, blue: 0.94)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .overlay(Circle().strokeBorder(DockTheme.bevel.opacity(0.35), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                    .frame(width: diameter, height: diameter)

                Circle()
                    .strokeBorder(tint.opacity(0.9), lineWidth: 3)
                    .frame(width: diameter - 5, height: diameter - 5)
                    .shadow(color: tint.opacity(active ? 0.8 : 0.3), radius: active ? 6 : 2)

                Circle()
                    .fill(tint.opacity(active ? 0.12 : 0))
                    .frame(width: diameter - 10, height: diameter - 10)

                VStack(spacing: 1) {
                    Image(systemName: symbol)
                        .font(.system(size: diameter * 0.33, weight: .semibold))
                        .foregroundStyle(active ? tint : DockTheme.subtext)
                    if let label {
                        Text(label)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(active ? tint : DockTheme.subtext)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// A small square glyph button for the secondary slots beside the round buttons.
struct FooterSmallButton: View {
    let symbol: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(colors: [color.opacity(0.95), color],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 29, height: 29)
                    .shadow(color: color.opacity(selected ? 0.45 : 0.2), radius: selected ? 5 : 2, y: 1)

                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(selected ? 1.12 : 1)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(DockTheme.text.opacity(selected ? 0.4 : 0))
                    .frame(width: 14, height: 2)
                    .offset(y: 5)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)
    }
}

/// Time and date, centred in the footer.
struct FooterClock: View {

    /// Locales that show a 24-hour clock have no AM/PM to draw.
    private var uses24Hour: Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h"
        return !template.contains("a")
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if !uses24Hour {
                        Text(meridiem(context.date))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DockTheme.subtext)
                    }
                    Text(time(context.date))
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(DockTheme.text)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .fixedSize()

                Text(day(context.date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DockTheme.subtext)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        // Fixed pattern: the localized template would fold AM/PM back in.
        formatter.dateFormat = uses24Hour ? "H:mm" : "h:mm"
        return formatter.string(from: date)
    }

    private func meridiem(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }

    private func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd EEE")
        return formatter.string(from: date)
    }
}
