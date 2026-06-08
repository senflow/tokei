import Foundation

enum RangeKey: String, CaseIterable, Identifiable {
    case yesterday, today, week, lastWeek = "last_week", month, year
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: return "今日"
        case .yesterday: return "昨日"
        case .week: return "本周"
        case .lastWeek: return "上周"
        case .month: return "本月"
        case .year: return "本年"
        }
    }
}

struct ClaudeModelStat: Codable, Identifiable {
    var name: String
    var `in`: Int
    var out: Int
    var cr: Int
    var cw: Int
    var cost: Double
    var pin: Double      // 输入单价 $/M
    var pout: Double     // 输出单价 $/M
    var id: String { name }
    var total: Int { `in` + out + cr + cw }
}

struct ClaudeRange: Codable {
    var hit: Double
    var `in`: Int
    var out: Int
    var cr: Int
    var cw: Int
    var cost: Double
    var models: [ClaudeModelStat] = []
    var sessions: Int = 0
}

struct ClaudeRanges: Codable {
    var today: ClaudeRange
    var yesterday: ClaudeRange
    var week: ClaudeRange
    var last_week: ClaudeRange
    var month: ClaudeRange
    var year: ClaudeRange
    func get(_ k: RangeKey) -> ClaudeRange {
        switch k {
        case .today: return today; case .yesterday: return yesterday
        case .week: return week; case .lastWeek: return last_week
        case .month: return month; case .year: return year
        }
    }
    mutating func set(_ k: RangeKey, _ v: ClaudeRange) {
        switch k {
        case .today: today = v; case .yesterday: yesterday = v
        case .week: week = v; case .lastWeek: last_week = v
        case .month: month = v; case .year: year = v
        }
    }
}

struct ClaudeStat: Codable {
    var ranges: ClaudeRanges
    var session_name: String
    var session_total: Int
    var q5: Double?
    var q5_reset: Int?
    var q7: Double?
    var q7_reset: Int?
}

struct CodexRange: Codable {
    var hit: Double
    var `in`: Int
    var cached: Int
    var out: Int
    var reason: Int
    var cost: Double
    var sessions: Int = 0
}

struct CodexRanges: Codable {
    var today: CodexRange
    var yesterday: CodexRange
    var week: CodexRange
    var last_week: CodexRange
    var month: CodexRange
    var year: CodexRange
    func get(_ k: RangeKey) -> CodexRange {
        switch k {
        case .today: return today; case .yesterday: return yesterday
        case .week: return week; case .lastWeek: return last_week
        case .month: return month; case .year: return year
        }
    }
    mutating func set(_ k: RangeKey, _ v: CodexRange) {
        switch k {
        case .today: today = v; case .yesterday: yesterday = v
        case .week: week = v; case .lastWeek: last_week = v
        case .month: month = v; case .year: year = v
        }
    }
}

struct CodexStat: Codable {
    var ranges: CodexRanges
    var p5: Double?
    var pw: Double?
    var r5: Int?
    var rw: Int?
    var plan: String?
}

struct GeminiModelStat: Codable, Identifiable {
    var name: String
    var `in`: Int
    var out: Int
    var cached: Int
    var thoughts: Int
    var cost: Double
    var pin: Double      // 输入单价 $/M
    var pout: Double     // 输出单价 $/M
    var id: String { name }
}

struct GeminiRange: Codable {
    var hit: Double
    var `in`: Int
    var out: Int
    var cached: Int
    var thoughts: Int
    var cost: Double
    var models: [GeminiModelStat] = []
    var sessions: Int = 0
}

struct GeminiRanges: Codable {
    var today: GeminiRange
    var yesterday: GeminiRange
    var week: GeminiRange
    var last_week: GeminiRange
    var month: GeminiRange
    var year: GeminiRange
    func get(_ k: RangeKey) -> GeminiRange {
        switch k {
        case .today: return today; case .yesterday: return yesterday
        case .week: return week; case .lastWeek: return last_week
        case .month: return month; case .year: return year
        }
    }
    mutating func set(_ k: RangeKey, _ v: GeminiRange) {
        switch k {
        case .today: today = v; case .yesterday: yesterday = v
        case .week: week = v; case .lastWeek: last_week = v
        case .month: month = v; case .year: year = v
        }
    }
}

struct GeminiStat: Codable {
    var ranges: GeminiRanges
}

struct GrokRange: Codable {
    var tokens: Int
    var sessions: Int = 0
}

struct GrokRanges: Codable {
    var today: GrokRange
    var yesterday: GrokRange
    var week: GrokRange
    var last_week: GrokRange
    var month: GrokRange
    var year: GrokRange
    func get(_ k: RangeKey) -> GrokRange {
        switch k {
        case .today: return today; case .yesterday: return yesterday
        case .week: return week; case .lastWeek: return last_week
        case .month: return month; case .year: return year
        }
    }
    mutating func set(_ k: RangeKey, _ v: GrokRange) {
        switch k {
        case .today: today = v; case .yesterday: yesterday = v
        case .week: week = v; case .lastWeek: last_week = v
        case .month: month = v; case .year: year = v
        }
    }
}

struct GrokStat: Codable {
    var ranges: GrokRanges
    var model: String?
}

struct QoderRange: Codable {
    var `in`: Int
    var out: Int
    var sessions: Int = 0
    var calls: Int = 0
    var duration: Int = 0
    var ctx: Double = 0
}

struct QoderRanges: Codable {
    var today: QoderRange
    var yesterday: QoderRange
    var week: QoderRange
    var last_week: QoderRange
    var month: QoderRange
    var year: QoderRange
    func get(_ k: RangeKey) -> QoderRange {
        switch k {
        case .today: return today; case .yesterday: return yesterday
        case .week: return week; case .lastWeek: return last_week
        case .month: return month; case .year: return year
        }
    }
    mutating func set(_ k: RangeKey, _ v: QoderRange) {
        switch k {
        case .today: today = v; case .yesterday: yesterday = v
        case .week: week = v; case .lastWeek: last_week = v
        case .month: month = v; case .year: year = v
        }
    }
}

struct QoderQuotaBucket: Codable {
    var total: Int?
    var used: Int?
    var remaining: Int?
    var percentage: Double?
    var cap: Int?
    var unit: String?
}

struct QoderQuota: Codable {
    var userQuota: QoderQuotaBucket?
    var orgResourcePackage: QoderQuotaBucket?
    var totalUsagePercentage: Double?
    var expiresAt: Int?
}

struct QoderStat: Codable {
    var ranges: QoderRanges
    var quota: QoderQuota?
    var model: String?
}

struct HermesRange: Codable {
    var hit: Double
    var `in`: Int
    var out: Int
    var cr: Int
    var cw: Int
    var reason: Int
    var cost: Double
    var sessions: Int = 0
    var models: [HermesModelStat] = []
}
struct HermesModelStat: Codable, Identifiable {
    var name: String; var `in`: Int; var out: Int; var cost: Double
    var id: String { name }
}
struct HermesRanges: Codable {
    var today, yesterday, week, last_week, month, year: HermesRange
    func get(_ k: RangeKey) -> HermesRange {
        switch k {
        case .today: return today; case .yesterday: return yesterday
        case .week: return week; case .lastWeek: return last_week
        case .month: return month; case .year: return year
        }
    }
    mutating func set(_ k: RangeKey, _ v: HermesRange) {
        switch k {
        case .today: today = v; case .yesterday: yesterday = v
        case .week: week = v; case .lastWeek: last_week = v
        case .month: month = v; case .year: year = v
        }
    }
}
struct HermesStat: Codable { var ranges: HermesRanges }

struct OpenClawRange: Codable {
    var tasks: Int
    var completed: Int
    var failed: Int
}
struct OpenClawRanges: Codable {
    var today, yesterday, week, last_week, month, year: OpenClawRange
    func get(_ k: RangeKey) -> OpenClawRange {
        switch k {
        case .today: return today; case .yesterday: return yesterday
        case .week: return week; case .lastWeek: return last_week
        case .month: return month; case .year: return year
        }
    }
}
struct OpenClawStat: Codable { var ranges: OpenClawRanges }

struct OpenCodeRange: Codable {
    var hit: Double
    var `in`: Int
    var out: Int
    var cr: Int
    var cw: Int
    var reason: Int
    var cost: Double
    var sessions: Int = 0
    var models: [HermesModelStat] = []
}
struct OpenCodeRanges: Codable {
    var today, yesterday, week, last_week, month, year: OpenCodeRange
    func get(_ k: RangeKey) -> OpenCodeRange {
        switch k {
        case .today: return today; case .yesterday: return yesterday
        case .week: return week; case .lastWeek: return last_week
        case .month: return month; case .year: return year
        }
    }
    mutating func set(_ k: RangeKey, _ v: OpenCodeRange) {
        switch k {
        case .today: today = v; case .yesterday: yesterday = v
        case .week: week = v; case .lastWeek: last_week = v
        case .month: month = v; case .year: year = v
        }
    }
}
struct OpenCodeStat: Codable { var ranges: OpenCodeRanges }

struct Usage: Codable {
    var claude: ClaudeStat
    var codex: CodexStat
    var gemini: GeminiStat
    var grok: GrokStat
    var qoder: QoderStat
    var hermes: HermesStat
    var openclaw: OpenClawStat
    var opencode: OpenCodeStat
}

enum Fmt {
    static func human(_ n: Int) -> String {
        let v = Double(n)
        if v >= 100_000_000 { return String(format: "%.1f亿", v / 100_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(format: "%.0f", v)
    }

    static func reset(_ epoch: Int?) -> String {
        guard let e = epoch else { return "?" }
        let d = Date(timeIntervalSince1970: TimeInterval(e))
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    static func countdown(_ epoch: Int?) -> String {
        guard let e = epoch else { return "?" }
        let s = TimeInterval(e) - Date().timeIntervalSince1970
        if s <= 0 { return "即将重置" }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }

    static func duration(_ ms: Int) -> String {
        let s = ms / 1000
        if s >= 3600 { return String(format: "%dh%dm", s / 3600, (s % 3600) / 60) }
        if s >= 60 { return String(format: "%dm%ds", s / 60, s % 60) }
        return "\(s)s"
    }

    static func price(_ x: Double) -> String { String(format: "%g", x) }

    static func relativeDate(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d),
                                                    to: Calendar.current.startOfDay(for: Date())).day ?? 0
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days <= 7 { return "\(days)天前" }
        if days <= 30 { return "\(days / 7)周前" }
        return "\(days / 30)月前"
    }
}
