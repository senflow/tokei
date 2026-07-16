import SwiftUI

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = Theme.isDark ? .hudWindow : .menu
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = Theme.isDark ? .hudWindow : .menu
    }
}

private class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct Tip: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSView {
        let v = PassthroughView(); v.toolTip = text; return v
    }
    func updateNSView(_ v: NSView, context: Context) { v.toolTip = text }
}

extension View {
    func tip(_ text: String) -> some View { overlay(Tip(text: text)) }
}

// Design system — inspired by cc-switch's Tailwind / shadcn-ui design language.
// Blue primary accent, clean bordered cards, consistent spacing and radius.
enum Theme {
    // Primary accent (cc-switch blue ~ #0A84FF)
    static let primary   = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let primaryBg = Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.12)

    // Tool / model tints — kept distinct for data visualisation
    static let claude    = Color(red: 0.92, green: 0.52, blue: 0.40)   // warm coral
    static let codex     = Color(red: 0.42, green: 0.68, blue: 0.98)   // sky blue
    static let gemini    = Color(red: 0.62, green: 0.52, blue: 0.92)   // lavender
    static let grok      = Color(red: 0.65, green: 0.68, blue: 0.75)   // cool silver
    static let qoder     = Color(red: 0.90, green: 0.75, blue: 0.35)   // amber gold
    static let qoderwork = Color(red: 0.75, green: 0.65, blue: 0.30)   // dark amber
    static let qoderCli  = Color(red: 0.95, green: 0.60, blue: 0.25)   // burnt orange
    static let hermes    = Color(red: 0.40, green: 0.82, blue: 0.60)   // emerald
    static let openclaw  = Color(red: 0.85, green: 0.45, blue: 0.68)   // rose
    static let pi        = Color(red: 0.74, green: 0.58, blue: 0.95)   // soft purple
    static let opencode  = Color(red: 0.55, green: 0.75, blue: 0.90)   // sky grey
    static let zcode     = Color(red: 0.45, green: 0.72, blue: 0.55)   // jade green
    static let mimocode  = Color(red: 0.95, green: 0.68, blue: 0.55)   // peach
    static let workbuddy = Color(red: 0.50, green: 0.60, blue: 0.90)   // periwinkle
    static let qwencode  = Color(red: 0.80, green: 0.35, blue: 0.35)   // brick red

    // Layout
    static let panelWidth: CGFloat = 322
    static let cardRadius: CGFloat = 14
    static let outerPad: CGFloat = 15

    // Current colour scheme — set by PanelView before rendering
    static var isDark: Bool = true

    // Brand gradient (blue primary — cc-switch style)
    static var brand: LinearGradient {
        LinearGradient(colors: [primary.opacity(0.85), primary],
                       startPoint: .leading, endPoint: .trailing)
    }

    // Background
    static var bg: LinearGradient {
        isDark
            ? LinearGradient(
                colors: [Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.96),
                         Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.98)],
                startPoint: .top, endPoint: .bottom)
            : LinearGradient(
                colors: [Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.96),
                         Color(red: 0.90, green: 0.90, blue: 0.93).opacity(0.98)],
                startPoint: .top, endPoint: .bottom)
    }

    static var cardBg: Color {
        isDark ? Color(red: 0.15, green: 0.15, blue: 0.17)
               : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    static var border: Color {
        isDark ? Color.white.opacity(0.08)
               : Color.black.opacity(0.10)
    }

    // Text hierarchy
    static var tPrimary: Color {
        isDark ? Color.white.opacity(0.95) : Color.black.opacity(0.88)
    }
    static var tSecondary: Color {
        isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.60)
    }
    static var tTertiary: Color {
        isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.45)
    }
}

// Card — clean bordered card with subtle hover lift.  Mirrors cc-switch ProviderCard.
struct Card<Content: View>: View {
    var tint: Color
    @ViewBuilder var content: () -> Content
    @State private var hover = false

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Theme.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02), .clear],
                        startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
            .shadow(color: Theme.isDark ? .black.opacity(hover ? 0.40 : 0.25) : .black.opacity(hover ? 0.12 : 0.06),
                    radius: hover ? 14 : 10, x: 0, y: hover ? 8 : 5)
            .scaleEffect(hover ? 1.01 : 1)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.18), value: hover)
    }
}

struct EqualHeightGrid: Layout {
    var columns = 2
    var hSpacing: CGFloat = 13
    var vSpacing: CGFloat = 13

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let colW = colWidth(in: proposal.width ?? 600)
        var h: CGFloat = 0
        for row in stride(from: 0, to: subviews.count, by: columns) {
            if row > 0 { h += vSpacing }
            h += rowHeight(row: row, colW: colW, subviews: subviews)
        }
        return CGSize(width: proposal.width ?? 600, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let colW = colWidth(in: bounds.width)
        var y = bounds.minY
        for row in stride(from: 0, to: subviews.count, by: columns) {
            let rh = rowHeight(row: row, colW: colW, subviews: subviews)
            for i in row..<min(row + columns, subviews.count) {
                let x = bounds.minX + CGFloat(i - row) * (colW + hSpacing)
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                  proposal: .init(width: colW, height: rh))
            }
            y += rh + vSpacing
        }
    }

    private func colWidth(in total: CGFloat) -> CGFloat {
        (total - hSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    }
    private func rowHeight(row: Int, colW: CGFloat, subviews: Subviews) -> CGFloat {
        (row..<min(row + columns, subviews.count)).map {
            subviews[$0].sizeThatFits(.init(width: colW, height: nil)).height
        }.max() ?? 0
    }
}

// Ring gauge — cache-hit rate circular indicator.
struct RingGauge: View {
    var value: Double            // 0...100
    var tint: Color
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value / 100)))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.35), radius: 4)
            VStack(spacing: -1) {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("%")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.5), value: value)
    }
}

// Thin progress bar (quota usage).
struct MiniBar: View {
    var value: Double            // 0...100
    var tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(3, geo.size.width * min(1, value / 100)))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.45), value: value)
    }
}

// Stat bar — capsule bar with sqrt scale, used for model / project rankings.
struct StatBar: View {
    var name: String
    var tokens: Int
    var cost: Double
    var maxTokens: Double
    var tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(name).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tPrimary).lineLimit(1)
                Spacer(minLength: 8)
                Text(Fmt.human(tokens)).font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.tTertiary)
                Text("$\(Int(cost))").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.tSecondary)
            }
            GeometryReader { geo in
                let ratio = maxTokens > 0 ? (Double(tokens) / maxTokens).squareRoot() : 0
                Capsule().fill(LinearGradient(colors: [tint.opacity(0.5), tint],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, geo.size.width * CGFloat(ratio)), height: 5)
            }
            .frame(height: 5)
        }
    }
}

// Metric cell — icon + label + monospaced value.
struct MetricCell: View {
    var icon: String
    var label: String
    var value: String
    var tint: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 21, height: 21)
                .background(Circle().fill(tint.opacity(0.10)))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.tTertiary)
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.tPrimary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct RingMetricCell: View {
    var value: Double
    var label: String
    var tint: Color
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, value / 100)))
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 21, height: 21)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.tTertiary)
                Text("\(Int(value.rounded()))%")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.tPrimary)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.5), value: value)
    }
}

// Large cost headline row.
struct CostHeadline: View {
    var value: String
    var caption: String
    var tint: Color
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.tPrimary)
                .contentTransition(.numericText())
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(Theme.tTertiary)
            Spacer(minLength: 0)
        }
    }
}

// Custom segmented tabs — blue primary active state (cc-switch style).
struct SegmentedTabs: View {
    @Binding var sel: RangeKey
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(RangeKey.displayCases) { k in
                let on = k == sel
                Text(k.label)
                    .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? AnyShapeStyle(Theme.tPrimary) : AnyShapeStyle(Theme.tTertiary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.primary.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Theme.primary.opacity(0.35), lineWidth: 1))
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { sel = k }
                    }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// Footer icon button with hover highlight.
struct IconButton: View {
    var icon: String
    var label: String
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(hover ? AnyShapeStyle(Theme.tPrimary) : AnyShapeStyle(Theme.tTertiary))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hover ? 0.10 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
