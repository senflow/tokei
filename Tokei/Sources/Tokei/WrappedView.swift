import SwiftUI

struct WrappedProject: Codable, Identifiable {
    var name: String; var tokens: Int; var cost: Double
    var id: String { name }
}

struct WrappedBusiest: Codable { var date = ""; var tokens = 0 }
struct WrappedModel: Codable { var name = "-"; var tokens = 0 }

struct WrappedData: Codable {
    var total_tokens = 0
    var total_cost: Double = 0
    var active_days = 0
    var streak_max = 0
    var streak_cur = 0
    var busiest = WrappedBusiest()
    var top_model = WrappedModel()
    var hours: [Int] = []
    var weekday: [Int] = []
    var projects: [WrappedProject] = []
    var max_projs_day = 0
    var night_share: Double = 0
    var first_day = ""
    var period: String = "all"
}

enum WrappedPeriod: String, CaseIterable {
    case day = "1d", week = "7d", month = "30d", year = "365d", all = "all"
    var label: String {
        switch self {
        case .day: return "今日"
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "今年"
        case .all: return "全部"
        }
    }
}

// Tokei 回顾 —— 作息 / 项目 / 连续(Claude 数据)。
struct WrappedView: View {
    let data: WrappedData
    @Binding var period: WrappedPeriod
    var onPeriodChange: (WrappedPeriod) -> Void = { _ in }
    @State private var showConfetti = false
    @State private var loadingPeriod = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hero(data)
            statChips(data)
            Divider().opacity(0.15)
            rhythmSection(data)
        }
        .overlay(alignment: .top) {
            if showConfetti { ConfettiView().frame(height: 220).allowsHitTesting(false) }
        }
        .onAppear {
            if Self.checkMilestone(data.total_tokens) {
                showConfetti = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { showConfetti = false }
            }
        }
    }

    // token 里程碑档位(持久化,驱动撒花动画)
    static func checkMilestone(_ tokens: Int) -> Bool {
        let cur = tokens / 1_000_000_000          // 每 10 亿一档
        let last = UserDefaults.standard.integer(forKey: "lastTokenMilestone")
        if cur > last {
            UserDefaults.standard.set(cur, forKey: "lastTokenMilestone")
            return true
        }
        return false
    }

    // MARK: - Hero
    func hero(_ d: WrappedData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.primary)
                Text("回顾").font(.system(size: 11, weight: .bold)).tracking(1.5)
                    .foregroundStyle(Theme.tSecondary)
                Spacer()
                periodPicker
            }
            HStack(spacing: 4) {
                if !d.first_day.isEmpty {
                    Text(period == .all ? "自 \(d.first_day)" : d.first_day)
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                }
                if d.active_days > 0 {
                    Text("· \(d.active_days) 天活跃")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.human(d.total_tokens))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Theme.primary, Theme.codex],
                                                    startPoint: .leading, endPoint: .trailing))
                    .contentTransition(.numericText())
                Text("tokens").font(.system(size: 10.5)).foregroundStyle(Theme.tTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.primary.opacity(0.16), Theme.codex.opacity(0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.primary.opacity(0.12), lineWidth: 0.75))
        )
    }

    // MARK: - Stat chips
    func statChips(_ d: WrappedData) -> some View {
        let avg = d.active_days > 0 ? d.total_cost / Double(d.active_days) : 0
        return HStack(spacing: 7) {
            chip("总成本", "$" + intStr(d.total_cost), Theme.primary)
            chip("连续", "\(d.streak_cur) 天", Theme.hermes, icon: "flame.fill")
            chip("日均", "$" + intStr(avg), Theme.gemini)
            chip("峰值日", shortDate(d.busiest.date), Color.red.opacity(0.85))
            chip("本命模型", d.top_model.name, Theme.codex)
        }
    }

    func chip(_ label: String, _ value: String, _ tint: Color, icon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(tint.opacity(0.9))
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                }
                Text(value).font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.tPrimary).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7).padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }

    // MARK: - 24h rhythm
    func rhythmSection(_ d: WrappedData) -> some View {
        let maxH = max(d.hours.max() ?? 1, 1)
        let peak = d.hours.firstIndex(of: d.hours.max() ?? 0) ?? -1
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("活跃时段").font(.system(size: 13, weight: .bold))
                Spacer()
                if peak >= 0 {
                    Text(String(format: "高峰 %02d:00", peak))
                        .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                }
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { h in
                    let v = h < d.hours.count ? d.hours[h] : 0
                    let ratio = CGFloat(v) / CGFloat(maxH)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(h == peak ? AnyShapeStyle(Theme.primary.gradient)
                                        : AnyShapeStyle(Theme.primary.opacity(0.32)))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(2, 48 * ratio))
                }
            }
            .frame(height: 48, alignment: .bottom)
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18, 23], id: \.self) { h in
                    Text("\(h)").font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.tTertiary)
                    if h != 23 { Spacer() }
                }
            }
        }
    }

    // MARK: - Period picker
    var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(WrappedPeriod.allCases, id: \.rawValue) { p in
                Button {
                    guard p != period else { return }
                    period = p
                    loadingPeriod = true
                    onPeriodChange(p)
                } label: {
                    Text(p.label)
                        .font(.system(size: 9, weight: p == period ? .bold : .medium))
                        .foregroundStyle(p == period ? .white : Theme.tTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(
                            p == period
                                ? AnyShapeStyle(Theme.primary.gradient)
                                : AnyShapeStyle(Color.clear)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    // MARK: - helpers
    func intStr(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: Int(v))) ?? "\(Int(v))"
    }
    func shortDate(_ s: String) -> String { s.count >= 10 ? String(s.suffix(5)) : s }
}

// 撒花:跨 token 里程碑时从顶部落下的彩屑。
struct ConfettiView: View {
    @State private var fall = false
    private let palette: [Color] = [Theme.claude, Theme.qoder, Theme.qoderwork, Theme.hermes,
                                    Theme.codex, Theme.gemini, Theme.openclaw]
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ForEach(0..<30, id: \.self) { i in
                    let frac = CGFloat((i * 37) % 100) / 100
                    let dur = 1.5 + Double((i * 13) % 10) / 10
                    let dly = Double((i * 7) % 8) / 10
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(palette[i % palette.count])
                        .frame(width: 6, height: 9)
                        .rotationEffect(.degrees(Double(i * 47)))
                        .offset(x: frac * geo.size.width,
                                y: fall ? geo.size.height + 40 : -40)
                        .opacity(fall ? 0 : 1)
                        .animation(.easeIn(duration: dur).delay(dly), value: fall)
                }
            }
        }
        .onAppear { fall = true }
        .allowsHitTesting(false)
    }
}
