import Foundation

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

    static func loadSync() -> Usage? { runScript() }

    static func load(_ completion: @escaping (Usage?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let usage = runScript()
            DispatchQueue.main.async { completion(usage) }
        }
    }

    static func runScript(args: [String] = ["--json"]) -> Usage? {
        let result = runScriptRaw(args: args, timeout: 12)
        guard !result.timedOut, result.exitCode == 0 else {
            fputs("Tokei script failed: exit=\(result.exitCode) timeout=\(result.timedOut)\n\(result.stderr)\n", stderr)
            return nil
        }
        let data = Data(result.stdout.utf8)
        do {
            guard var raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            for key in raw.keys where key.hasPrefix("_") { raw.removeValue(forKey: key) }
            let cleaned = try JSONSerialization.data(withJSONObject: raw)
            return try JSONDecoder().decode(Usage.self, from: cleaned)
        } catch {
            fputs("Tokei decode error: \(error)\n", stderr)
            return nil
        }
    }

    static func runScriptRaw(args: [String] = ["--json"], timeout: TimeInterval = 8) -> ScriptResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", scriptPath] + args
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
