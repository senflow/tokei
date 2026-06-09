import Foundation
import AppKit

final class Updater: NSObject, ObservableObject, URLSessionDownloadDelegate {
    enum State: Equatable {
        case idle, checking, available(String, URL), downloading(Double), installing, failed(String)
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking), (.installing, .installing): return true
            case (.available(let a, _), .available(let b, _)): return a == b
            case (.downloading(let a), .downloading(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    static let releaseTag = "v1.0.0"
    @Published var state: State = .idle

    private let apiURL = URL(string: "https://api.github.com/repos/cclank/tokei/releases/latest")!
    private var downloadTask: URLSessionDownloadTask?
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }()

    private static func isNewer(remote: String, local: String) -> Bool {
        let parse: (String) -> [Int] = { v in
            v.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                .split(separator: ".").compactMap { Int($0) }
        }
        let r = parse(remote), l = parse(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    func checkForUpdate() {
        guard state == .idle || {
            if case .failed = state { return true }; return false
        }() else { return }
        state = .checking
        var req = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self, let data = data else {
                    self?.state = .idle
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let assets = json["assets"] as? [[String: Any]],
                      let first = assets.first,
                      let urlStr = first["browser_download_url"] as? String,
                      let url = URL(string: urlStr) else {
                    self.state = .idle
                    return
                }
                if Self.isNewer(remote: tag, local: Self.releaseTag) {
                    self.state = .available(tag, url)
                } else {
                    self.state = .idle
                }
            }
        }.resume()
    }

    func performUpdate() {
        guard case .available(_, let url) = state else { return }
        state = .downloading(0)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        state = .downloading(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let dmgPath = "/tmp/tokei_update.dmg"
        try? FileManager.default.removeItem(atPath: dmgPath)
        do {
            try FileManager.default.moveItem(at: location, to: URL(fileURLWithPath: dmgPath))
        } catch {
            state = .failed("移动文件失败")
            return
        }
        install(dmgPath: dmgPath)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Install

    private func install(dmgPath: String) {
        state = .installing
        let appPath = Bundle.main.bundlePath
        let script = """
        #!/bin/bash
        sleep 1
        hdiutil attach "\(dmgPath)" -nobrowse -quiet -mountpoint /tmp/tokei_mnt
        if [ -d /tmp/tokei_mnt/Tokei.app ]; then
            rm -rf "\(appPath).bak"
            mv "\(appPath)" "\(appPath).bak"
            cp -R /tmp/tokei_mnt/Tokei.app "\(appPath)"
            if [ $? -eq 0 ]; then
                xattr -cr "\(appPath)"
                rm -rf "\(appPath).bak"
            else
                mv "\(appPath).bak" "\(appPath)"
            fi
        fi
        hdiutil detach /tmp/tokei_mnt -quiet
        rm -f "\(dmgPath)" /tmp/tokei_update.sh
        open "\(appPath)"
        """
        let scriptPath = "/tmp/tokei_update.sh"
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptPath]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}
