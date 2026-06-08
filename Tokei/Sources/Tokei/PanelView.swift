import SwiftUI
import AppKit

struct PanelView: View {
    @ObservedObject var store: Store
    var scrollable = true
    @State private var sel: RangeKey = .today
    @State private var claudeModelsOpen = false
    @State private var geminiModelsOpen = false
    @State private var settingsOpen = false
    @State private var mode: PanelMode = .cards
    @State private var trailProjects: [TrailProject]?
    enum PanelMode { case cards, dashboard, projects }
    @AppStorage("showClaude") private var showClaude = true
    @AppStorage("showCodex") private var showCodex = true
    @AppStorage("showGemini") private var showGemini = true
    @AppStorage("showGrok") private var showGrok = true
    @AppStorage("showQoder") private var showQoder = true
    @AppStorage("showHermes") private var showHermes = true
    @AppStorage("showOpenClaw") private var showOpenClaw = true
    @AppStorage("showOpenCode") private var showOpenCode = true

    private var visibleCount: Int {
        [showClaude, showCodex, showGemini, showGrok, showQoder, showHermes, showOpenClaw, showOpenCode].filter { $0 }.count
    }
    private var useWide: Bool { visibleCount > 2 }
    private var panelWidth: CGFloat { useWide ? 640 : Theme.panelWidth }

    private var maxPanelHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 40
    }

    var body: some View {
        let w = mode == .cards ? panelWidth : max(panelWidth, 420)
        if scrollable {
            ScrollView(.vertical, showsIndicators: false) { panelContent }
                .frame(width: w)
                .frame(maxHeight: maxPanelHeight)
                .background(Theme.bg)
                .background(VisualEffect())
                .environment(\.colorScheme, .dark)
        } else {
            panelContent
                .frame(width: w, alignment: .top)
                .background(Theme.bg)
                .background(VisualEffect())
                .environment(\.colorScheme, .dark)
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            if mode == .dashboard {
                DashboardView()
            } else if mode == .projects {
                ProjectTrailView(cached: $trailProjects)
            } else if let u = store.usage {
                let cr = u.claude.ranges.get(sel), xr = u.codex.ranges.get(sel)
                let gr = u.gemini.ranges.get(sel), kr = u.grok.ranges.get(sel)
                let qr = u.qoder.ranges.get(sel), hr = u.hermes.ranges.get(sel)
                let lr = u.openclaw.ranges.get(sel), or = u.opencode.ranges.get(sel)
                let hasClaude = showClaude && cr.sessions > 0
                let hasCodex  = showCodex  && xr.sessions > 0
                let hasGemini = showGemini && gr.sessions > 0
                let hasGrok   = showGrok   && kr.sessions > 0
                let hasQoder  = showQoder  && qr.calls > 0
                let hasHermes = showHermes && hr.sessions > 0
                let hasClaw   = showOpenClaw && lr.tasks > 0
                let hasOCode  = showOpenCode && or.sessions > 0
                SegmentedTabs(sel: $sel)
                if useWide {
                    EqualHeightGrid() {
                        if hasClaude { Card(tint: Theme.claude) { claudeBlock(u.claude, cr) } }
                        if hasCodex  { Card(tint: Theme.codex)  { codexBlock(u.codex, xr) } }
                        if hasGemini { Card(tint: Theme.gemini) { geminiBlock(gr) } }
                        if hasGrok   { Card(tint: Theme.grok)   { grokBlock(kr, model: u.grok.model) } }
                        if hasQoder  { Card(tint: Theme.qoder)  { qoderBlock(u.qoder, qr) } }
                        if hasHermes { Card(tint: Theme.hermes) { hermesBlock(hr) } }
                        if hasClaw   { Card(tint: Theme.openclaw) { openclawBlock(lr) } }
                        if hasOCode  { Card(tint: Theme.opencode) { opencodeBlock(or) } }
                    }
                } else {
                    if hasClaude { Card(tint: Theme.claude) { claudeBlock(u.claude, cr) } }
                    if hasCodex  { Card(tint: Theme.codex)  { codexBlock(u.codex, xr) } }
                    if hasGemini { Card(tint: Theme.gemini) { geminiBlock(gr) } }
                    if hasGrok   { Card(tint: Theme.grok)   { grokBlock(kr, model: u.grok.model) } }
                    if hasQoder  { Card(tint: Theme.qoder)  { qoderBlock(u.qoder, qr) } }
                    if hasHermes { Card(tint: Theme.hermes) { hermesBlock(hr) } }
                    if hasClaw   { Card(tint: Theme.openclaw) { openclawBlock(lr) } }
                    if hasOCode  { Card(tint: Theme.opencode) { opencodeBlock(or) } }
                }
                inactiveToolsLine(hasClaude: hasClaude, hasCodex: hasCodex, hasGemini: hasGemini,
                                  hasGrok: hasGrok, hasQoder: hasQoder, hasHermes: hasHermes,
                                  hasClaw: hasClaw, hasOCode: hasOCode)
            } else {
                HStack(spacing: 8) {
                    Spacer()
                    if let error = store.loadError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.claude)
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.tSecondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                .frame(height: 90)
            }
            footer
        }
        .padding(Theme.outerPad)
    }

    // MARK: - 品牌头部
    // 节日皮肤:特定日期 logo 旁挂个小角标。
    static func festiveEmoji() -> String? {
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        switch (c.month ?? 0, c.day ?? 0) {
        case (12, 24), (12, 25): return "🎄"
        case (1, 1):             return "🎉"
        case (10, 31):           return "🎃"
        case (2, 14):            return "❤️"
        case (2, 16), (2, 17), (2, 18): return "🧧"   // 2026 春节
        default:                 return nil
        }
    }

    var header: some View {
        HStack(spacing: 9) {
            Button {
                if mode != .cards { withAnimation(.easeInOut(duration: 0.35)) { mode = .cards } }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "timer")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.brand)
                        .overlay(alignment: .topTrailing) {
                            if let e = Self.festiveEmoji() {
                                Text(e).font(.system(size: 11)).offset(x: 7, y: -7)
                            }
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Tokei")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .tracking(0.5)
                        Text("时计 · AI 用量")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tip("主页")
            Spacer()
            Text(store.lastUpdated)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.tTertiary)
            Button {
                withAnimation(.easeInOut(duration: 0.35)) { mode = mode == .projects ? .cards : .projects }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(mode == .projects ? Theme.claude : Theme.tTertiary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .tip("项目足迹")
            Button {
                withAnimation(.easeInOut(duration: 0.35)) { mode = mode == .dashboard ? .cards : .dashboard }
            } label: {
                Image(systemName: "chart.bar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(mode == .dashboard ? Theme.claude : Theme.tTertiary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .tip("数据面板")
            Button { settingsOpen.toggle() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tTertiary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .tip("设置")
            .popover(isPresented: $settingsOpen, arrowEdge: .bottom) { settingsContent }
        }
    }

    // MARK: - Claude 卡片
    @ViewBuilder
    func claudeBlock(_ c: ClaudeStat, _ r: ClaudeRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHead("Claude Code", tint: Theme.claude, sessions: r.sessions)
            if r.sessions > 0 {
                CostHeadline(value: Fmt.human(r.in + r.out + r.cr + r.cw), caption: "\(sel.label) 总量", tint: Theme.claude)
                metricGrid([
                    .init("dollarsign.circle", "≈成本", String(format: "$%.2f", r.cost)),
                ], hit: r.hit, extra: [
                    .init("arrow.down", "输入", Fmt.human(r.in)),
                    .init("arrow.up", "输出", Fmt.human(r.out)),
                    .init("bolt.fill", "缓存读", Fmt.human(r.cr)),
                    .init("square.stack.3d.up.fill", "缓存写", Fmt.human(r.cw)),
                ], tint: Theme.claude)
                if !r.models.isEmpty {
                    modelDisclosure(r.models.map { ModelRow(name: $0.name, pin: $0.pin, pout: $0.pout, cost: $0.cost) },
                                    open: $claudeModelsOpen, tint: Theme.claude)
                }
                if c.q5 != nil || c.q7 != nil { thinDivider }
                if let q5 = c.q5 {
                    quotaRow(title: "5h 剩余", pct: 100 - q5, reset: c.q5_reset, tint: Theme.claude)
                }
                if let q7 = c.q7 {
                    quotaRow(title: "周剩余", pct: 100 - q7, reset: c.q7_reset, tint: Theme.claude)
                }
            } else {
                emptyHint
            }
        }
    }

    // MARK: - Codex 卡片
    @ViewBuilder
    func codexBlock(_ x: CodexStat, _ r: CodexRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHead("Codex", tint: Theme.codex, sessions: r.sessions)
            if r.sessions > 0 {
                CostHeadline(value: Fmt.human(r.in + r.cached + r.out + r.reason), caption: "\(sel.label) 总量", tint: Theme.codex)
                metricGrid([.init("dollarsign.circle", "≈成本", String(format: "$%.2f", r.cost))],
                    hit: r.hit, extra: {
                    var items: [Metric] = [
                        .init("arrow.down", "输入", Fmt.human(r.in)),
                        .init("bolt.fill", "缓存读", Fmt.human(r.cached)),
                        .init("arrow.up", "输出", Fmt.human(r.out)),
                    ]
                    if r.reason > 0 { items.append(.init("brain", "推理", Fmt.human(r.reason))) }
                    return items
                }(), tint: Theme.codex)
                if x.p5 != nil || x.pw != nil { thinDivider }
                if let p5 = x.p5 {
                    quotaRow(title: "5h 剩余", pct: 100 - p5, reset: x.r5, tint: Theme.codex)
                }
                if let pw = x.pw {
                    quotaRow(title: "周剩余", pct: 100 - pw, reset: x.rw, tint: Theme.codex)
                }
                if let plan = x.plan {
                    HStack {
                        Text("plan").font(.system(size: 11)).foregroundStyle(Theme.tTertiary)
                        Spacer()
                        Text(plan)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.tSecondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.codex.opacity(0.16)))
                    }
                }
            } else {
                emptyHint
            }
        }
    }

    // MARK: - Gemini 卡片
    @ViewBuilder
    func geminiBlock(_ r: GeminiRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHead("Gemini CLI", tint: Theme.gemini, sessions: r.sessions)
            if r.sessions > 0 {
                CostHeadline(value: Fmt.human(r.in + r.cached + r.out + r.thoughts), caption: "\(sel.label) 总量", tint: Theme.gemini)
                metricGrid([.init("dollarsign.circle", "≈成本", String(format: "$%.2f", r.cost))],
                    hit: r.hit, extra: {
                    var items: [Metric] = [
                        .init("arrow.down", "输入", Fmt.human(r.in)),
                        .init("arrow.up", "输出", Fmt.human(r.out)),
                        .init("bolt.fill", "缓存", Fmt.human(r.cached)),
                    ]
                    if r.thoughts > 0 { items.append(.init("brain", "推理", Fmt.human(r.thoughts))) }
                    return items
                }(), tint: Theme.gemini)
                if !r.models.isEmpty {
                    modelDisclosure(r.models.map { ModelRow(name: $0.name, pin: $0.pin, pout: $0.pout, cost: $0.cost) },
                                    open: $geminiModelsOpen, tint: Theme.gemini)
                }
            } else {
                emptyHint
            }
        }
    }

    // MARK: - Grok 卡片
    @ViewBuilder
    func grokBlock(_ r: GrokRange, model: String?) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHeadPlain("Grok CLI", tint: Theme.grok)
            if r.sessions > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.grok)
                    Text("累计上下文")
                        .font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                    Spacer(minLength: 6)
                    Text(Fmt.human(r.tokens))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.tPrimary)
                        .contentTransition(.numericText())
                    Text("token").font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
                }
                if let model, !model.isEmpty {
                    modelBadge(model, tint: Theme.grok)
                }
            } else {
                emptyHint
            }
        }
    }

    // MARK: - Qoder 卡片
    @ViewBuilder
    func qoderBlock(_ q: QoderStat, _ r: QoderRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHeadPlain("Qoder", tint: Theme.qoder)
            if r.calls > 0 {
                metricGrid({
                    var items: [Metric] = [
                        .init("terminal", "调用", "\(r.calls)"),
                        .init("clock", "耗时", Fmt.duration(r.duration)),
                    ]
                    if r.ctx > 0 {
                        items.append(.init("chart.bar.fill", "上下文", String(format: "%.0f%%", r.ctx)))
                    }
                    if r.in > 0 {
                        items.append(.init("arrow.down", "输入", Fmt.human(r.in)))
                    }
                    return items
                }(), tint: Theme.qoder)
                if let quota = q.quota {
                    thinDivider
                    if let uq = quota.userQuota, let rem = uq.remaining, let tot = uq.total {
                        let pct = tot > 0 ? Double(rem) / Double(tot) * 100 : 0
                        quotaRow(title: "个人额度", pct: pct, reset: quota.expiresAt.map { $0 / 1000 }, tint: Theme.qoder)
                    }
                    if let org = quota.orgResourcePackage, let rem = org.remaining, let cap = org.cap {
                        let pct = cap > 0 ? Double(rem) / Double(cap) * 100 : 0
                        quotaRow(title: "团队额度", pct: pct, reset: nil, tint: Theme.qoder)
                    }
                }
                if let model = q.model, !model.isEmpty {
                    modelBadge(model, tint: Theme.qoder)
                }
            } else {
                emptyHint
            }
        }
    }

    // MARK: - Hermes 卡片
    @ViewBuilder
    func hermesBlock(_ r: HermesRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHead("Hermes", tint: Theme.hermes, sessions: r.sessions)
            if r.sessions > 0 {
                CostHeadline(value: Fmt.human(r.in + r.out + r.cr + r.cw + r.reason), caption: "\(sel.label) 总量", tint: Theme.hermes)
                metricGrid([.init("dollarsign.circle", "≈成本", String(format: "$%.2f", r.cost))],
                    hit: r.hit, extra: {
                    var items: [Metric] = [
                        .init("arrow.down", "输入", Fmt.human(r.in)),
                        .init("arrow.up", "输出", Fmt.human(r.out)),
                        .init("bolt.fill", "缓存读", Fmt.human(r.cr)),
                    ]
                    if r.reason > 0 { items.append(.init("brain", "推理", Fmt.human(r.reason))) }
                    return items
                }(), tint: Theme.hermes)
            } else {
                emptyHint
            }
        }
    }

    // MARK: - OpenClaw 卡片
    @ViewBuilder
    func openclawBlock(_ r: OpenClawRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHeadPlain("OpenClaw", tint: Theme.openclaw)
            if r.tasks > 0 {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("任务").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                        Text("\(r.tasks)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.tPrimary)
                    }
                    if r.completed > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("完成").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                            Text("\(r.completed)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                        }
                    }
                    if r.failed > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("失败").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                            Text("\(r.failed)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                    }
                    Spacer()
                }
            } else {
                emptyHint
            }
        }
    }

    // MARK: - OpenCode 卡片
    @ViewBuilder
    func opencodeBlock(_ r: OpenCodeRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHead("OpenCode", tint: Theme.opencode, sessions: r.sessions)
            if r.sessions > 0 {
                CostHeadline(value: Fmt.human(r.in + r.out + r.cr + r.cw + r.reason), caption: "\(sel.label) 总量", tint: Theme.opencode)
                metricGrid([.init("dollarsign.circle", "≈成本", String(format: "$%.2f", r.cost))],
                    hit: r.hit, extra: {
                    var items: [Metric] = [
                        .init("arrow.down", "输入", Fmt.human(r.in)),
                        .init("arrow.up", "输出", Fmt.human(r.out)),
                        .init("bolt.fill", "缓存读", Fmt.human(r.cr)),
                        .init("square.stack.3d.up.fill", "缓存写", Fmt.human(r.cw)),
                    ]
                    if r.reason > 0 { items.append(.init("brain", "推理", Fmt.human(r.reason))) }
                    return items
                }(), tint: Theme.opencode)
            } else {
                emptyHint
            }
        }
    }

    @ViewBuilder
    func inactiveToolsLine(hasClaude: Bool, hasCodex: Bool, hasGemini: Bool,
                           hasGrok: Bool, hasQoder: Bool, hasHermes: Bool,
                           hasClaw: Bool, hasOCode: Bool) -> some View {
        let names: [(Bool, String)] = [
            (showClaude && !hasClaude, "Claude"), (showCodex && !hasCodex, "Codex"),
            (showGemini && !hasGemini, "Gemini"), (showGrok && !hasGrok, "Grok"),
            (showQoder && !hasQoder, "Qoder"), (showHermes && !hasHermes, "Hermes"),
            (showOpenClaw && !hasClaw, "OpenClaw"), (showOpenCode && !hasOCode, "OpenCode"),
        ]
        let inactive = names.filter(\.0).map(\.1)
        if !inactive.isEmpty {
            Text(inactive.joined(separator: " · ") + " 暂无数据")
                .font(.system(size: 9))
                .foregroundStyle(Theme.tTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    var emptyHint: some View {
        Text("暂无数据")
            .font(.system(size: 10))
            .foregroundStyle(Theme.tTertiary)
    }

    func modelBadge(_ model: String, tint: Color) -> some View {
        HStack {
            Text("model").font(.system(size: 11)).foregroundStyle(Theme.tTertiary)
            Spacer()
            Text(model)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.tSecondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(tint.opacity(0.16)))
        }
    }

    // MARK: - 复用片段
    struct Metric { var icon, label, value: String
        init(_ i: String, _ l: String, _ v: String) { icon = i; label = l; value = v } }

    // 模型明细行(Claude / Gemini 共用)。
    struct ModelRow: Identifiable {
        var name: String
        var pin: Double
        var pout: Double
        var cost: Double
        var id: String { name }
    }

    func cardHead(_ title: String, tint: Color, sessions: Int = 0) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tint.gradient).frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.6), radius: 3)
            Text(title).font(.system(size: 14, weight: .bold))
            if sessions > 0 {
                Text("\(sessions)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(tint.opacity(0.12)))
            }
            Spacer()
        }
    }

    // 无命中环的卡头(Grok 无缓存命中数据)。
    func cardHeadPlain(_ title: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tint.gradient).frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.6), radius: 3)
            Text(title).font(.system(size: 14, weight: .bold))
            Spacer()
        }
    }

    @ViewBuilder
    func metricGrid(_ top: [Metric], hit: Double = 0, extra: [Metric] = [], tint: Color) -> some View {
        let all = top + extra
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  alignment: .leading, spacing: 9) {
            ForEach(top.indices, id: \.self) { i in
                MetricCell(icon: top[i].icon, label: top[i].label,
                           value: top[i].value, tint: tint)
            }
            if hit > 0 {
                RingMetricCell(value: hit, label: "Cache Hit", tint: tint)
            }
            let offset = top.count + (hit > 0 ? 1 : 0)
            ForEach(extra.indices, id: \.self) { i in
                MetricCell(icon: extra[i].icon, label: extra[i].label,
                           value: extra[i].value, tint: tint)
                    .id(offset + i)
            }
        }
    }

    var thinDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }

    func sessionRow(_ name: String, _ total: Int) -> some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
            Text("本会话 \(name)").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
            Spacer()
            Text(Fmt.human(total))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.tSecondary)
        }
    }

    var disclaimer: some View {
        Text("成本按 API 价估算,非订阅实付")
            .font(.system(size: 9))
            .foregroundStyle(Theme.tTertiary)
    }

    @ViewBuilder
    func modelDisclosure(_ models: [ModelRow], open: Binding<Bool>, tint: Color) -> some View {
        Button {
            open.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 9)).foregroundStyle(tint)
                Text("按模型 (\(models.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.tTertiary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: open, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 9) {
                Text("按模型 · \(sel.label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tSecondary)
                ForEach(models) { m in
                    HStack(spacing: 7) {
                        Circle().fill(tint.opacity(0.7)).frame(width: 5, height: 5)
                        Text(m.name).font(.system(size: 11.5)).foregroundStyle(Theme.tPrimary)
                            .lineLimit(1)
                        Text("\(Fmt.price(m.pin))/\(Fmt.price(m.pout))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.tSecondary)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                        Spacer(minLength: 8)
                        Text(String(format: "$%.2f", m.cost))
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.tPrimary)
                    }
                }
            }
            .padding(14)
            .frame(width: 238)
            .background(Theme.bg)
            .environment(\.colorScheme, .dark)
        }
    }

    func quotaRow(title: String, pct: Double, reset: Int?, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.tSecondary)
                Spacer()
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pct <= 15 ? AnyShapeStyle(.red) : AnyShapeStyle(Theme.tPrimary))
                Text("· \(Fmt.reset(reset))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.tTertiary)
            }
            MiniBar(value: pct, tint: pct <= 15 ? .red : tint)
        }
        .help(reset != nil ? "\(Fmt.countdown(reset)) 后重置" : "")
    }

    var footer: some View {
        HStack(spacing: 4) {
            disclaimer
            Spacer()
            KeepAwakeMenu(ka: store.keepAwake)
            IconButton(icon: "arrow.clockwise", label: "刷新") { store.refresh() }
            IconButton(icon: "power", label: "退出") { NSApp.terminate(nil) }
        }
    }

    @State private var priceUpdating = false
    @State private var priceResult = ""
    @AppStorage("syncDir") private var syncDir = ""
    @AppStorage("deviceName") private var deviceName = ""
    @AppStorage("autoSync") private var autoSync = false
    @AppStorage("syncInterval") private var syncInterval = 5
    @AppStorage("sitReminderOn") private var sitReminderOn = false
    @AppStorage("sitReminderInterval") private var sitReminderInterval = 90

    var settingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 显示卡片
            settingsSection("square.grid.2x2", "显示卡片") {
                settingsRow("Claude Code", tint: Theme.claude, isOn: $showClaude)
                settingsRow("Codex", tint: Theme.codex, isOn: $showCodex)
                settingsRow("Gemini CLI", tint: Theme.gemini, isOn: $showGemini)
                settingsRow("Grok CLI", tint: Theme.grok, isOn: $showGrok)
                settingsRow("Qoder", tint: Theme.qoder, isOn: $showQoder)
                settingsRow("Hermes", tint: Theme.hermes, isOn: $showHermes)
                settingsRow("OpenClaw", tint: Theme.openclaw, isOn: $showOpenClaw)
                settingsRow("OpenCode", tint: Theme.opencode, isOn: $showOpenCode)
            }

            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

            // 价格表
            settingsSection("dollarsign.circle", "价格表") {
                HStack(spacing: 8) {
                    Button { runPriceUpdate("--update-prices", "全量更新中…") } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle").font(.system(size: 9))
                            Text("全量更新").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Theme.tPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .disabled(priceUpdating)

                    Button { runPriceUpdate("--update-unknown", "查漏补缺中…") } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass.circle").font(.system(size: 9))
                            Text("查漏补缺").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Theme.tPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .disabled(priceUpdating)

                    if priceUpdating { ProgressView().controlSize(.mini) }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)

                if !priceResult.isEmpty && !priceUpdating {
                    Text(priceResult)
                        .font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
                        .padding(.horizontal, 10)
                        .onTapGesture { priceResult = "" }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                                priceResult = ""
                            }
                        }
                }
            }

            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

            // 久坐提醒
            settingsSection("figure.walk.circle", "久坐提醒") {
                HStack {
                    Text("启用").font(.system(size: 11)).foregroundStyle(Theme.tPrimary)
                    Spacer()
                    Toggle("", isOn: $sitReminderOn)
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        .onChange(of: sitReminderOn) { _ in store.sitReminder.updateRunning() }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04)))

                if sitReminderOn {
                    HStack {
                        Text("间隔").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                        Spacer()
                        Picker("", selection: $sitReminderInterval) {
                            Text("45m").tag(45); Text("60m").tag(60); Text("90m").tag(90)
                        }
                        .pickerStyle(.segmented).frame(width: 130).controlSize(.mini)
                        .onChange(of: sitReminderInterval) { _ in store.sitReminder.updateRunning() }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)

                    Button { store.sitReminder.testPing() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bell.badge").font(.system(size: 9))
                            Text("发送测试提醒").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Theme.tSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)

                    Text("基于系统空闲判断「是否离开电脑」,连续用机达设定时长提醒起身。注:看视频/开会不操作会被当作离开。")
                        .font(.system(size: 8.5)).foregroundStyle(Theme.tTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.top, 2)
                }
            }

            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

            // 多设备同步
            settingsSection("arrow.triangle.2.circlepath", "多设备同步") {
                HStack {
                    Text("启用").font(.system(size: 11)).foregroundStyle(Theme.tPrimary)
                    Spacer()
                    Toggle("", isOn: $store.syncEnabled)
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        .onChange(of: store.syncEnabled) { on in
                            if on { setupSync() } else { store.stopAutoSync() }
                        }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04)))

                if store.syncEnabled {
                    // 设备名
                    HStack {
                        Text("设备名").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                        Spacer()
                        TextField("hostname", text: $deviceName)
                            .font(.system(size: 10, design: .monospaced))
                            .textFieldStyle(.plain)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: deviceName) { _ in saveSync() }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)

                    // 同步目录
                    HStack {
                        Text("目录").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                        Spacer()
                        Text(syncDir.isEmpty ? "未设置" : (syncDir as NSString).lastPathComponent)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(syncDir.isEmpty ? Theme.tTertiary : Theme.tSecondary)
                            .lineLimit(1)
                        Button("选择") { pickSyncDir() }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.claude)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)

                    // 立即同步 + 自动同步
                    HStack(spacing: 8) {
                        Button {
                            store.doSync()
                        } label: {
                            HStack(spacing: 4) {
                                if store.syncing {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 9))
                                }
                                Text("同步").font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(Theme.tPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.syncing || syncDir.isEmpty)

                        Spacer()
                        Text("自动").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                        Toggle("", isOn: $autoSync)
                            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                            .onChange(of: autoSync) { on in
                                if on { store.startAutoSync(minutes: syncInterval) }
                                else { store.stopAutoSync() }
                            }
                        if autoSync {
                            Picker("", selection: $syncInterval) {
                                Text("1m").tag(1); Text("5m").tag(5); Text("15m").tag(15)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 90)
                            .controlSize(.mini)
                            .onChange(of: syncInterval) { v in
                                store.startAutoSync(minutes: v)
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)

                    // 展示范围
                    HStack {
                        Text("展示").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                        Spacer()
                        Picker("", selection: $store.showAllDevices) {
                            Text("本机").tag(false); Text("全部设备").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)

                    // 设备状态
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 8)).foregroundStyle(.green)
                            Text(deviceName.isEmpty ? "本机" : deviceName)
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.tPrimary)
                            Text("(本机)").font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
                        }
                        if store.peers.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "clock")
                                    .font(.system(size: 8)).foregroundStyle(Theme.tTertiary)
                                Text("等待其他设备…")
                                    .font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                            }
                        } else {
                            ForEach(store.peers) { p in
                                HStack(spacing: 5) {
                                    Image(systemName: "laptopcomputer")
                                        .font(.system(size: 8)).foregroundStyle(Theme.codex)
                                    Text(p.deviceId)
                                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.tPrimary)
                                    Spacer()
                                    Text(Fmt.reset(Int(p.lastSync.timeIntervalSince1970)))
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)

                    // 添加设备
                    if store.syncEnabled && !syncDir.isEmpty {
                        let dataRepo = Self.gitRemoteUrl(syncDir)
                        let hasRemote = !dataRepo.contains("未配置")
                        let projectDir = (DataLoader.scriptPath as NSString).deletingLastPathComponent
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle").font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.hermes)
                                Text("添加设备")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.tSecondary)
                            }

                            if hasRemote {
                                // Mac: 装 app + 选同一个数据仓库
                                Text("另一台 Mac:").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.tSecondary)
                                Text("安装 Tokei.app → 设置 → 多设备同步 → 目录选择同一个数据仓库")
                                    .font(.system(size: 8.5)).foregroundStyle(Theme.tTertiary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Rectangle().fill(Color.primary.opacity(0.04)).frame(height: 1)

                                // 远程服务器: 一条命令
                                Text("远程 Linux:").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.tSecondary)
                                copyBlock("git clone \(dataRepo) ~/.tokei/sync && cp ~/.tokei/sync/usage.30s.py ~/.tokei/ 2>/dev/null; echo '{\"sync_dir\":\"~/.tokei/sync\",\"device_id\":\"'$(hostname -s)'\"}' > ~/.tokei/config.json && (crontab -l 2>/dev/null; echo '*/5 * * * * cd ~/.tokei/sync && python3 ~/.tokei/usage.30s.py --json >/dev/null && git pull -q && git add -A && git diff --cached --quiet || git commit -qm sync && git push -q') | crontab -")
                            } else {
                                Text("数据目录未关联 Git 仓库")
                                    .font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
                                Text("对 Agent 说:").font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
                                copyBlock("读取 \(Self.skillPath) 并帮我创建 Tokei 私有数据仓库,配置多设备同步")
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                    }
                }
            }

            // 多设备/远程提示
            if !store.syncEnabled {
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                settingsSection("antenna.radiowaves.left.and.right", "多设备 / 远程采集") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("多台 Mac 或远程服务器的数据通过私有 Git 仓库同步,每台设备独立采集、自动加和")
                            .font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("对 Agent 说:").font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
                        copyBlock("读取 \(Self.skillPath) 帮我配置 Tokei 多设备同步")
                        Text("或手动:开启上方「多设备同步」→ 选择数据仓库目录")
                            .font(.system(size: 8.5)).foregroundStyle(Theme.tTertiary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                }
            }

            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

            HStack {
                Spacer()
                Text("Made by 岚叔")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.tTertiary)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 260)
        .background(Theme.bg)
        .environment(\.colorScheme, .dark)
    }

    func settingsSection<C: View>(_ icon: String, _ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tTertiary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tSecondary)
            }
            VStack(spacing: 2) { content() }
        }
    }

    func setupSync() {
        if deviceName.isEmpty { deviceName = ProcessInfo.processInfo.hostName.components(separatedBy: ".").first ?? "mac" }
        saveSync()
    }

    func saveSync() {
        let cfg = SyncConfig(device_id: deviceName, sync_dir: syncDir,
                             auto_sync: autoSync, sync_interval: syncInterval)
        store.syncManager.saveConfig(cfg)
    }

    func runPriceUpdate(_ flag: String, _ msg: String) {
        priceUpdating = true
        priceResult = msg
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["python3", DataLoader.scriptPath, flag]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try? proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                priceUpdating = false
                if flag == "--update-prices" {
                    priceResult = output.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let count = json["count"] as? Int {
                        priceResult = count > 0 ? "补全 \(count) 个模型" : "所有模型已匹配 ✓"
                    } else {
                        priceResult = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                store.refresh()
            }
        }
    }

    static var skillPath: String {
        let script = DataLoader.scriptPath
        return (script as NSString).deletingLastPathComponent + "/skills/tokei-setup.md"
    }

    static func gitRemoteUrl(_ dir: String) -> String {
        let expanded = (dir as NSString).expandingTildeInPath
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", expanded, "remote", "get-url", "origin"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let url = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return url.isEmpty ? "<未配置 git remote>" : url
    }

    func copyBlock(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Theme.tSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.04)))
    }

    func pickSyncDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择同步目录"
        if panel.runModal() == .OK, let url = panel.url {
            syncDir = url.path
            saveSync()
        }
    }

    func settingsRow(_ name: String, tint: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tint.gradient).frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.4), radius: 2)
            Text(name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.tPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
