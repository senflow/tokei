import Foundation

final class DataLoader {
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
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", scriptPath] + args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        do {
            return try JSONDecoder().decode(Usage.self, from: data)
        } catch {
            fputs("Tokei decode error: \(error)\n", stderr)
            return nil
        }
    }
}
