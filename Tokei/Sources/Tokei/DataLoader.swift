import Foundation
import CZstd

final class DataLoader {
    struct ScriptResult {
        var stdout: String
        var stderr: String
        var exitCode: Int32
        var elapsed: TimeInterval
        var timedOut: Bool
    }

    static var scriptPath: String = {
        let userScript = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tokei/usage.30s.py").path
        if let bundled = Bundle.main.resourcePath {
            let bundledScript = (bundled as NSString).appendingPathComponent("usage.30s.py")
            if FileManager.default.fileExists(atPath: bundledScript) {
                syncToUserDir(from: bundled)
            }
        }
        return userScript
    }()

    private static func syncToUserDir(from resourceDir: String) {
        let dest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tokei")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for name in ["usage.30s.py", "pricing.json", "pricing_overrides.json"] {
            let src = (resourceDir as NSString).appendingPathComponent(name)
            let dst = dest.appendingPathComponent(name).path
            guard FileManager.default.fileExists(atPath: src) else { continue }
            if name == "usage.30s.py" {
                try? FileManager.default.removeItem(atPath: dst)
                try? FileManager.default.copyItem(atPath: src, toPath: dst)
            } else if !FileManager.default.fileExists(atPath: dst) {
                try? FileManager.default.copyItem(atPath: src, toPath: dst)
            }
        }
    }

    static func scanClaudeQuota() -> [String: Any]? {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/Cache/Cache_Data").path
        guard FileManager.default.fileExists(atPath: cacheDir) else { return nil }
        let zstdMagic: [UInt8] = [0x28, 0xb5, 0x2f, 0xfd]
        let fm = FileManager.default
        guard let allFiles = try? fm.contentsOfDirectory(atPath: cacheDir) else { return nil }
        let cacheFiles = allFiles.filter { $0.hasSuffix("_0") }.map { name -> (String, Date) in
            let path = (cacheDir as NSString).appendingPathComponent(name)
            let mt = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
            return (path, mt)
        }.sorted { $0.1 > $1.1 }
        let needle1 = "organizations/".data(using: .utf8)!
        let needle2 = "/usage".data(using: .utf8)!
        var raw: Data?
        for (path, _) in cacheFiles.prefix(200) {
            guard let data = fm.contents(atPath: path) else { continue }
            guard data.range(of: needle1) != nil,
                  data.range(of: needle2) != nil,
                  data.range(of: Data(zstdMagic)) != nil else { continue }
            raw = data
            break
        }
        guard let raw = raw else { return nil }
        guard let magicRange = raw.range(of: Data(zstdMagic)) else { return nil }
        let compressed = raw[magicRange.lowerBound...]
        guard let decompressed = zstdDecompress(Data(compressed)) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: decompressed) as? [String: Any] else { return nil }
        let fh = json["five_hour"] as? [String: Any] ?? [:]
        let sd = json["seven_day"] as? [String: Any] ?? [:]
        var result: [String: Any] = [:]
        result["q5"] = fh["utilization"]
        result["q5_reset"] = isoToEpoch(fh["resets_at"] as? String)
        result["q7"] = sd["utilization"]
        result["q7_reset"] = isoToEpoch(sd["resets_at"] as? String)
        return result
    }

    private static func zstdDecompress(_ src: Data) -> Data? {
        let bufSize = src.count
        let frameSize = src.withUnsafeBytes { ptr -> Int in
            ZSTD_findFrameCompressedSize(ptr.baseAddress, bufSize)
        }
        guard ZSTD_isError(frameSize) == 0 else { return nil }
        let bound = src.withUnsafeBytes { ptr -> UInt64 in
            ZSTD_getFrameContentSize(ptr.baseAddress, frameSize)
        }
        let dstSize = (bound == ZSTD_CONTENTSIZE_ERROR || bound == ZSTD_CONTENTSIZE_UNKNOWN)
            ? max(frameSize * 20, 4096)
            : Int(bound)
        var dst = [UInt8](repeating: 0, count: dstSize)
        let ret = src.withUnsafeBytes { srcPtr -> Int in
            ZSTD_decompress(&dst, dstSize, srcPtr.baseAddress, frameSize)
        }
        guard ZSTD_isError(ret) == 0 else { return nil }
        return Data(dst.prefix(ret))
    }

    private static func isoToEpoch(_ s: String?) -> Int? {
        guard let s = s else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: s) { return Int(d.timeIntervalSince1970) }
        fmt.formatOptions = [.withInternetDateTime]
        if let d = fmt.date(from: s) { return Int(d.timeIntervalSince1970) }
        return nil
    }

    static func loadSync() -> Usage? { runScript() }

    static func load(_ completion: @escaping (Usage?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let usage = runScript()
            DispatchQueue.main.async { completion(usage) }
        }
    }

    static func runScript(args: [String] = ["--json"]) -> Usage? {
        let result = runScriptRaw(args: args, timeout: 45)
        guard !result.timedOut, result.exitCode == 0 else {
            fputs("Tokei script failed: exit=\(result.exitCode) timeout=\(result.timedOut)\n\(result.stderr)\n", stderr)
            return nil
        }
        let data = Data(result.stdout.utf8)
        do {
            guard var raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            for key in raw.keys where key.hasPrefix("_") { raw.removeValue(forKey: key) }
            if var claude = raw["claude"] as? [String: Any],
               claude["q5"] == nil || (claude["q5"] as? Double) == nil {
                if let quota = scanClaudeQuota() {
                    for (k, v) in quota { claude[k] = v }
                    raw["claude"] = claude
                }
            }
            let cleaned = try JSONSerialization.data(withJSONObject: raw)
            return try JSONDecoder().decode(Usage.self, from: cleaned)
        } catch {
            fputs("Tokei decode error: \(error)\n", stderr)
            return nil
        }
    }

    private static let pythonPath: String = {
        for p in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return "/usr/bin/env"
    }()

    static func runScriptRaw(args: [String] = ["--json"], timeout: TimeInterval = 8) -> ScriptResult {
        let proc = Process()
        if pythonPath == "/usr/bin/env" {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["python3", scriptPath] + args
        } else {
            proc.executableURL = URL(fileURLWithPath: pythonPath)
            proc.arguments = [scriptPath] + args
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        let started = Date()
        do {
            try proc.run()
        } catch {
            return ScriptResult(stdout: "", stderr: error.localizedDescription, exitCode: -1,
                                elapsed: Date().timeIntervalSince(started), timedOut: false)
        }

        var timedOut = false
        let killer = DispatchWorkItem {
            if proc.isRunning {
                timedOut = true
                proc.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        killer.cancel()

        return ScriptResult(stdout: String(data: outData, encoding: .utf8) ?? "",
                            stderr: String(data: errData, encoding: .utf8) ?? "",
                            exitCode: proc.terminationStatus,
                            elapsed: Date().timeIntervalSince(started),
                            timedOut: timedOut)
    }
}
