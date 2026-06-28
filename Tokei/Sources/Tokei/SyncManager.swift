import Foundation

struct SyncConfig: Codable {
    var device_id: String
    var sync_dir: String
    var auto_sync: Bool?
    var sync_interval: Int?     // minutes
}

struct PeerDevice: Identifiable {
    var id: String { deviceId }
    var deviceId: String
    var lastSync: Date
    var usage: Usage
}

final class SyncManager {
    static let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".tokei/config.json")
    static let syncDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".tokei/sync").path

    var config: SyncConfig?

    init() { config = Self.loadConfig() }

    static func resolvedSyncDir(_ cfg: SyncConfig) -> String {
        let raw = cfg.sync_dir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return Self.syncDir }
        return (raw as NSString).expandingTildeInPath
    }

    // MARK: - Config

    static func loadConfig() -> SyncConfig? {
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? JSONDecoder().decode(SyncConfig.self, from: data)
    }

    func saveConfig(_ cfg: SyncConfig) {
        config = cfg
        let dir = Self.configPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: Self.configPath)
        }
    }

    // MARK: - Read peers

    func loadPeers() -> [PeerDevice] {
        guard let cfg = config else { return [] }
        let dir = Self.resolvedSyncDir(cfg)
        guard FileManager.default.fileExists(atPath: dir) else { return [] }
        var peers: [PeerDevice] = []
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        for file in files where file.hasSuffix(".json") {
            let deviceId = String(file.dropLast(5)) // remove .json
            if deviceId.caseInsensitiveCompare(cfg.device_id) == .orderedSame { continue }
            let path = (dir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = raw["_ts"] as? Int else { continue }
            var cleaned = raw
            for key in cleaned.keys where key.hasPrefix("_") { cleaned.removeValue(forKey: key) }
            guard let cleanData = try? JSONSerialization.data(withJSONObject: cleaned),
                  let usage = try? JSONDecoder().decode(Usage.self, from: cleanData) else { continue }
            peers.append(PeerDevice(
                deviceId: deviceId,
                lastSync: Date(timeIntervalSince1970: TimeInterval(ts)),
                usage: usage
            ))
        }
        return peers
    }

    // MARK: - Merge

    static func merge(local: Usage, peers: [PeerDevice]) -> Usage {
        var u = local
        for peer in peers {
            mergeRanges(&u.claude.ranges, peer.usage.claude.ranges)
            mergeRanges(&u.codex.ranges, peer.usage.codex.ranges)
            mergeRanges(&u.gemini.ranges, peer.usage.gemini.ranges)
            mergeRanges(&u.grok.ranges, peer.usage.grok.ranges)
            mergeRanges(&u.qoderwork.ranges, peer.usage.qoderwork.ranges)
            mergeRanges(&u.qoder.ranges, peer.usage.qoder.ranges)
            mergeRanges(&u.hermes.ranges, peer.usage.hermes.ranges)
            mergeRanges(&u.openclaw.ranges, peer.usage.openclaw.ranges)
            mergeRanges(&u.pi.ranges, peer.usage.pi.ranges)
            mergeRanges(&u.opencode.ranges, peer.usage.opencode.ranges)
        }
        return u
    }

    private static func mergeRanges(_ dst: inout ClaudeRanges, _ src: ClaudeRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.in += s.in; d.out += s.out; d.cr += s.cr; d.cw += s.cw
            d.cost += s.cost; d.sessions += s.sessions
            d.hit = hitRate(cached: d.cr, input: d.in, cacheWrite: d.cw)
            mergeClaudeModels(&d.models, s.models)
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout CodexRanges, _ src: CodexRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.in += s.in; d.out += s.out; d.cached += s.cached
            d.reason += s.reason; d.cost += s.cost; d.sessions += s.sessions
            d.hit = hitRate(cached: d.cached, input: d.in)
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout GeminiRanges, _ src: GeminiRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.in += s.in; d.out += s.out; d.cached += s.cached
            d.thoughts += s.thoughts; d.cost += s.cost; d.sessions += s.sessions
            d.hit = hitRate(cached: d.cached, input: d.in)
            mergeGeminiModels(&d.models, s.models)
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout GrokRanges, _ src: GrokRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            let originalSessions = d.sessions
            d.tokens += s.tokens; d.sessions += s.sessions
            d.turns = add(d.turns, s.turns)
            d.tools = add(d.tools, s.tools)
            d.duration = add(d.duration, s.duration)
            d.ctx_used = add(d.ctx_used, s.ctx_used)
            d.ctx_window = add(d.ctx_window, s.ctx_window)
            d.errors = add(d.errors, s.errors)
            d.cancellations = add(d.cancellations, s.cancellations)
            d.ttft = weightedAverage(d.ttft, originalSessions, s.ttft, s.sessions)
            d.response = weightedAverage(d.response, originalSessions, s.response, s.sessions)
            let ctxUsed = d.ctx_used ?? 0
            let ctxWindow = d.ctx_window ?? 0
            d.ctx = ctxWindow > 0 ? Double(ctxUsed) / Double(ctxWindow) * 100 : 0
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout QoderRanges, _ src: QoderRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            let originalSessions = d.sessions
            d.sessions += s.sessions
            d.calls += s.calls; d.sub_agents += s.sub_agents
            d.turns += s.turns; d.duration += s.duration
            d.ctx = weightedAverage(d.ctx, originalSessions, s.ctx, s.sessions)
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout QoderIdeRanges, _ src: QoderIdeRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            let originalSessions = d.sessions
            d.in += s.in; d.out += s.out; d.cached += s.cached
            d.sessions += s.sessions
            d.sub_agents += s.sub_agents; d.calls += s.calls
            d.messages += s.messages; d.duration += s.duration
            d.ctx = weightedAverage(d.ctx, originalSessions, s.ctx, s.sessions)
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout HermesRanges, _ src: HermesRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.in += s.in; d.out += s.out; d.cr += s.cr; d.cw += s.cw
            d.reason += s.reason; d.cost += s.cost; d.sessions += s.sessions
            d.hit = hitRate(cached: d.cr, input: d.in, cacheWrite: d.cw)
            mergeTokenModels(&d.models, s.models)
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout OpenClawRanges, _ src: OpenClawRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.tasks += s.tasks; d.completed += s.completed; d.failed += s.failed
            d.in += s.in; d.out += s.out; d.cr += s.cr; d.cw += s.cw
            d.cost += s.cost; d.sessions += s.sessions
            d.hit = hitRate(cached: d.cr, input: d.in, cacheWrite: d.cw)
            mergeTokenModels(&d.models, s.models)
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout TokenUsageRanges, _ src: TokenUsageRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.in += s.in; d.out += s.out; d.cr += s.cr; d.cw += s.cw
            d.reason += s.reason; d.cost += s.cost; d.sessions += s.sessions
            d.hit = hitRate(cached: d.cr, input: d.in, cacheWrite: d.cw)
            mergeTokenModels(&d.models, s.models)
            dst.set(k, d)
        }
    }

    private static func hitRate(cached: Int, input: Int, cacheWrite: Int = 0) -> Double {
        let denom = cached + input + cacheWrite
        return denom > 0 ? Double(cached) / Double(denom) * 100 : 0
    }

    private static func add(_ lhs: Int?, _ rhs: Int?) -> Int? {
        let sum = (lhs ?? 0) + (rhs ?? 0)
        return sum > 0 ? sum : 0
    }

    private static func weightedAverage(_ lhs: Int?, _ lhsWeight: Int, _ rhs: Int?, _ rhsWeight: Int) -> Int? {
        let totalWeight = lhsWeight + rhsWeight
        guard totalWeight > 0 else { return 0 }
        return (((lhs ?? 0) * lhsWeight) + ((rhs ?? 0) * rhsWeight)) / totalWeight
    }

    private static func weightedAverage(_ lhs: Double, _ lhsWeight: Int, _ rhs: Double, _ rhsWeight: Int) -> Double {
        let totalWeight = lhsWeight + rhsWeight
        guard totalWeight > 0 else { return 0 }
        return ((lhs * Double(lhsWeight)) + (rhs * Double(rhsWeight))) / Double(totalWeight)
    }

    private static func mergeClaudeModels(_ dst: inout [ClaudeModelStat], _ src: [ClaudeModelStat]) {
        for m in src {
            if let idx = dst.firstIndex(where: { $0.name == m.name }) {
                dst[idx].in += m.in
                dst[idx].out += m.out
                dst[idx].cr += m.cr
                dst[idx].cw += m.cw
                dst[idx].cost += m.cost
            } else {
                dst.append(m)
            }
        }
        dst.sort { $0.cost > $1.cost }
    }

    private static func mergeGeminiModels(_ dst: inout [GeminiModelStat], _ src: [GeminiModelStat]) {
        for m in src {
            if let idx = dst.firstIndex(where: { $0.name == m.name }) {
                dst[idx].in += m.in
                dst[idx].out += m.out
                dst[idx].cached += m.cached
                dst[idx].thoughts += m.thoughts
                dst[idx].cost += m.cost
            } else {
                dst.append(m)
            }
        }
        dst.sort { $0.cost > $1.cost }
    }

    private static func mergeTokenModels(_ dst: inout [TokenModelStat], _ src: [TokenModelStat]) {
        for m in src {
            if let idx = dst.firstIndex(where: { $0.name == m.name }) {
                dst[idx].in += m.in
                dst[idx].out += m.out
                dst[idx].cr += m.cr
                dst[idx].cw += m.cw
                dst[idx].reason += m.reason
                dst[idx].cost += m.cost
            } else {
                dst.append(m)
            }
        }
        dst.sort { $0.cost > $1.cost }
    }

    // MARK: - Git sync

    func gitSync(completion: @escaping (Bool) -> Void) {
        guard let cfg = config else { completion(false); return }
        let dir = Self.resolvedSyncDir(cfg)
        let escapedDir = dir.replacingOccurrences(of: "'", with: "'\\''")
        DispatchQueue.global(qos: .utility).async {
            let script = """
            cd '\(escapedDir)' && \
            git pull --rebase --autostash 2>/dev/null; \
            git add -A && \
            (git diff --cached --quiet || git commit -m "tokei sync \(cfg.device_id)") && \
            git push 2>/dev/null
            """
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-c", script]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            DispatchQueue.main.async { completion(proc.terminationStatus == 0) }
        }
    }
}
