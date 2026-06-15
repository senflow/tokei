import SwiftUI

struct DailyCost: Codable, Identifiable {
    var date: String
    var claude: Double
    var codex: Double
    var pi: Double = 0
    var total: Double
    var c_in: Int = 0
    var c_out: Int = 0
    var c_cr: Int = 0
    var c_cw: Int = 0
    var x_in: Int = 0
    var x_out: Int = 0
    var x_cached: Int = 0
    var x_reason: Int = 0
    var p_in: Int = 0
    var p_out: Int = 0
    var p_cr: Int = 0
    var p_cw: Int = 0
    var p_reason: Int = 0
    var tokens: Int = 0
    var id: String { date }
}

struct ModelCost: Codable, Identifiable {
    var name: String
    var cost: Double
    var tool: String
    var `in`: Int?
    var out: Int?
    var cr: Int?
    var cw: Int?
    var reason: Int?
    var tokens: Int?
    var cost_per_k: Double = 0
    var out_ratio: Double = 0
    var id: String { name }
}

struct DashboardData: Codable {
    var daily: [DailyCost]
    var models: [ModelCost]
}

struct DashboardView: View {
    @State private var daily: [DailyCost] = []
    @State private var models: [ModelCost] = []
    @State private var wrapped: WrappedData? = nil
    @State private var loading = true
    @State private var wrappedPeriod: WrappedPeriod = .all
    @AppStorage("hideProjects") private var hideProjects = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if loading {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .frame(height: 200)
            } else {
                if let w = wrapped, w.total_tokens > 0 {
                    WrappedView(data: w, period: $wrappedPeriod) { p in loadWrapped(p) }
                }
                if !daily.isEmpty {
                    Divider().opacity(0.15)
                    modelSection
                    if let w = wrapped, !w.projects.isEmpty {
                        Divider().opacity(0.15)
                        projectsSection(w.projects)
                    }
                    Divider().opacity(0.15)
                    heatmapSection
                }
            }
        }
        .onAppear { loadData() }
    }

    // MARK: - Summary

    // MARK: - Model Chart

    var modelSection: some View {
        let sorted = models.sorted { ($0.tokens ?? 0) > ($1.tokens ?? 0) }
        let top = Array(sorted.prefix(8))
        let maxTokens = Double(top.first?.tokens ?? 1)
        return VStack(alignment: .leading, spacing: 9) {
            Text("模型用量").font(.system(size: 13, weight: .bold))
            ForEach(top) { m in
                StatBar(name: m.name,
                        tokens: m.tokens ?? ((m.in ?? 0) + (m.out ?? 0)),
                        cost: m.cost, maxTokens: maxTokens,
                        tint: modelTint(m.tool))
            }
        }
    }

    func modelTint(_ tool: String) -> Color {
        switch tool {
        case "codex": return Theme.codex
        case "pi": return Theme.pi
        default: return Theme.claude
        }
    }

    // MARK: - Projects
    func projectsSection(_ projects: [WrappedProject]) -> some View {
        let maxTok = Double(projects.first?.tokens ?? 1)
        return VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { hideProjects.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text("项目排行").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.tPrimary)
                    Image(systemName: hideProjects ? "eye.slash.fill" : "eye")
                        .font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
                    Spacer()
                    Image(systemName: hideProjects ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if hideProjects {
                Text("已隐藏 \(projects.count) 个项目")
                    .font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
            } else {
                ForEach(projects) { p in
                    StatBar(name: p.name, tokens: p.tokens, cost: p.cost,
                            maxTokens: maxTok, tint: Theme.claude)
                }
            }
        }
    }

    // MARK: - Heatmap

    @State private var heatRange = 2  // 0=日(7天) 1=月 2=年
    @State private var selectedCell: String? = nil

    var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("活跃热力")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Picker("", selection: $heatRange) {
                    Text("周").tag(0); Text("月").tag(1); Text("年").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .controlSize(.mini)
                .onChange(of: heatRange) { _ in selectedCell = nil }
            }
            if heatRange == 0 { weekStrip } else { heatmapGrid }
            if let sel = selectedCell, let day = daily.first(where: { $0.date == sel }) {
                heatDetail(day)
            }
            heatmapLegend
        }
    }

    func heatDetail(_ d: DailyCost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(d.date).font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.tPrimary)
                Spacer()
                Text(String(format: "$%.2f", d.total))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Button { selectedCell = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .foregroundStyle(Theme.tTertiary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.claude).frame(width: 6, height: 6)
                        Text("Claude").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.claude)
                    }
                    Text("\(Fmt.human(d.c_in + d.c_out + d.c_cr + d.c_cw)) tok")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                    Text(String(format: "$%.2f", d.claude))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.tSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.codex).frame(width: 6, height: 6)
                        Text("Codex").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.codex)
                    }
                    Text("\(Fmt.human(d.x_in + d.x_out + d.x_reason)) tok")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                    Text(String(format: "$%.2f", d.codex))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.tSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.pi).frame(width: 6, height: 6)
                        Text("Pi").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.pi)
                    }
                    Text("\(Fmt.human(d.p_in + d.p_out + d.p_cr + d.p_cw + d.p_reason)) tok")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                    Text(String(format: "$%.2f", d.pi))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.tSecondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.3))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.claude.opacity(0.2), lineWidth: 0.5)))
    }

    var weekStrip: some View {
        let cal = Calendar.current
        let today = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]
        let costMap = Dictionary(uniqueKeysWithValues: daily.map { ($0.date, $0.total) })
        let maxCost = daily.map(\.total).max() ?? 1

        return HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { r in
                    Text(dayLabels[r])
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Theme.tTertiary)
                        .frame(width: 14, height: 20)
                }
            }
            ForEach(0..<1, id: \.self) { _ in
                VStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { i in
                        let realD = cal.date(byAdding: .day, value: -(6 - i), to: today)!
                        let ds = fmt.string(from: realD)
                        let cost = costMap[ds] ?? 0
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(heatColor(cost: cost, max: maxCost))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(selectedCell == ds ? Theme.claude : .clear, lineWidth: 1.5)
                                )
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedCell = selectedCell == ds ? nil : ds
                                    }
                                }
                            Text(String(ds.suffix(5)))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.tTertiary)
                                .frame(width: 38, alignment: .leading)
                            if cost > 0 {
                                Text(String(format: "$%.0f", cost))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.tSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    var heatmapGrid: some View {
        let cal = Calendar.current
        let today = Date()
        let totalDays: Int = heatRange == 1 ? 35 : 371
        let startDate = cal.date(byAdding: .day, value: -(totalDays - 1), to: today)!
        let costMap = Dictionary(uniqueKeysWithValues: daily.map { ($0.date, $0.total) })
        let maxCost = daily.map(\.total).max() ?? 1

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]

        struct Cell: Identifiable {
            var id: Int; var row: Int; var col: Int; var cost: Double; var dateStr: String
        }

        var cells: [Cell] = []
        let startWeekday = (cal.component(.weekday, from: startDate) + 5) % 7
        for i in 0..<totalDays {
            guard let d = cal.date(byAdding: .day, value: i, to: startDate) else { continue }
            let ds = fmt.string(from: d)
            let offset = startWeekday + i
            let row = offset % 7
            let col = offset / 7
            cells.append(Cell(id: i, row: row, col: col, cost: costMap[ds] ?? 0, dateStr: ds))
        }
        let cols = (cells.last?.col ?? 0) + 1
        let cellSize: CGFloat = heatRange == 1 ? 20 : 12
        let gap: CGFloat = heatRange == 1 ? 3 : 2
        let radius: CGFloat = heatRange == 1 ? 4 : 2.5

        return HStack(alignment: .top, spacing: 4) {
            VStack(spacing: gap) {
                ForEach(0..<7, id: \.self) { r in
                    Text(dayLabels[r])
                        .font(.system(size: heatRange == 2 ? 8 : 10, weight: .medium))
                        .foregroundStyle(Theme.tTertiary)
                        .frame(width: 16, height: cellSize)
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: gap) {
                        ForEach(0..<cols, id: \.self) { c in
                            VStack(spacing: gap) {
                                ForEach(0..<7, id: \.self) { r in
                                    let cell = cells.first { $0.row == r && $0.col == c }
                                    let ds = cell?.dateStr ?? ""
                                    let cost = cell?.cost ?? 0
                                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                                        .fill(heatColor(cost: cost, max: maxCost))
                                        .frame(width: cellSize, height: cellSize)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                                            .strokeBorder(selectedCell == ds ? Theme.claude : .clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            selectedCell = selectedCell == ds ? nil : ds
                                        }
                                    }
                                }
                            }
                            .id(c)
                        }
                        Color.clear.frame(width: 1, height: 1).id("heatEnd")
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        proxy.scrollTo("heatEnd", anchor: .trailing)
                    }
                }
                .onChange(of: heatRange) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        proxy.scrollTo("heatEnd", anchor: .trailing)
                    }
                }
            }
        }
    }

    static let heatColors: [Color] = [
        Color(red: 0.18, green: 0.20, blue: 0.24),       // L0: 深灰(无活动)
        Color(red: 0.45, green: 0.32, blue: 0.22),       // L1: 暗棕
        Color(red: 0.72, green: 0.42, blue: 0.25),       // L2: 暖铜
        Color(red: 0.90, green: 0.55, blue: 0.30),       // L3: 亮橙
        Color(red: 0.98, green: 0.72, blue: 0.35),       // L4: 金黄
    ]

    func heatColor(cost: Double, max: Double) -> Color {
        if cost <= 0 { return Color.primary.opacity(0.04) }
        let ratio = min(cost / max, 1.0)
        if ratio < 0.15 { return Self.heatColors[1] }
        if ratio < 0.35 { return Self.heatColors[2] }
        if ratio < 0.60 { return Self.heatColors[3] }
        return Self.heatColors[4]
    }

    var heatmapLegend: some View {
        HStack(spacing: 5) {
            Spacer()
            Text("少").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(i == 0 ? Color.primary.opacity(0.04) : Self.heatColors[i])
                    .frame(width: 12, height: 12)
            }
            Text("多").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
        }
    }

    func loadData() {
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let dd = try? JSONDecoder().decode(DashboardData.self, from: Self.runScript(["--daily-costs"]))
            let wd = try? JSONDecoder().decode(WrappedData.self, from: Self.runScript(["--wrapped", "--period", wrappedPeriod.rawValue]))
            DispatchQueue.main.async {
                daily = dd?.daily ?? []
                models = dd?.models ?? []
                wrapped = wd
                loading = false
            }
        }
    }

    func loadWrapped(_ period: WrappedPeriod) {
        DispatchQueue.global(qos: .utility).async {
            let periodArgs = ["--period", period.rawValue]
            let wd = try? JSONDecoder().decode(WrappedData.self, from: Self.runScript(["--wrapped"] + periodArgs))
            let dd = try? JSONDecoder().decode(DashboardData.self, from: Self.runScript(["--daily-costs"] + periodArgs))
            DispatchQueue.main.async {
                wrapped = wd
                if let dd { daily = dd.daily; models = dd.models }
            }
        }
    }

    static func runScript(_ args: [String]) -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", DataLoader.scriptPath] + args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        let raw = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return raw
    }
}
