import Combine
import Darwin
import Foundation
import ServiceManagement

protocol LoginItemServicing: AnyObject {
    var status: SMAppService.Status { get }
    var diagnosticName: String { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServicing {
    var diagnosticName: String { "serviceManagement" }
}

private enum LaunchAgentLoginItemError: LocalizedError {
    case invalidApplication
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            return "找不到 Tokei.app，请将应用移到“应用程序”后重试"
        case .commandFailed(let message):
            return message.isEmpty ? "系统未能加载登录项" : "系统未能加载登录项：\(message)"
        }
    }
}

/// SMAppService 对 ad-hoc 签名的 app(我们 package.sh 里 codesign --sign - )注册常常不稳定——
/// 每次重新签名身份都会变,系统可能认不出"这还是同一个 app"而悄悄丢失登录项注册。
/// 这里直接管理一份 LaunchAgent plist 作为兜底,不依赖代码签名身份。
final class LaunchAgentLoginItemService: LoginItemServicing {
    typealias CommandResult = (status: Int32, output: String)
    typealias CommandRunner = ([String]) -> CommandResult

    static let label = "com.tokei.app.login"

    let diagnosticName = "launchAgent"
    let applicationURL: URL
    let plistURL: URL

    private let commandRunner: CommandRunner
    private let fileManager: FileManager
    private var domain: String { "gui/\(getuid())" }
    private var serviceTarget: String { "\(domain)/\(Self.label)" }

    init(applicationURL: URL = Bundle.main.bundleURL,
         plistURL: URL? = nil,
         fileManager: FileManager = .default,
         commandRunner: @escaping CommandRunner = LaunchAgentLoginItemService.runLaunchctl) {
        self.applicationURL = applicationURL.standardizedFileURL
        self.fileManager = fileManager
        self.plistURL = plistURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
        self.commandRunner = commandRunner
    }

    var hasConfiguration: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    var status: SMAppService.Status {
        guard configurationMatchesCurrentApplication() else { return .notRegistered }
        return commandRunner(["print", serviceTarget]).status == 0 ? .enabled : .requiresApproval
    }

    func register() throws {
        guard applicationURL.pathExtension == "app",
              fileManager.fileExists(atPath: applicationURL.path) else {
            throw LaunchAgentLoginItemError.invalidApplication
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: configuration(),
            format: .xml,
            options: 0
        )
        try fileManager.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: plistURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)

        _ = commandRunner(["bootout", serviceTarget])
        _ = commandRunner(["enable", serviceTarget])
        let result = commandRunner(["bootstrap", domain, plistURL.path])
        guard result.status == 0 else {
            throw LaunchAgentLoginItemError.commandFailed(result.output)
        }
    }

    func unregister() throws {
        _ = commandRunner(["bootout", serviceTarget])
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }
    }

    private func configuration() -> [String: Any] {
        [
            "Label": Self.label,
            "ProgramArguments": ["/usr/bin/open", applicationURL.path],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
    }

    private func configurationMatchesCurrentApplication() -> Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any],
              plist["Label"] as? String == Self.label,
              let arguments = plist["ProgramArguments"] as? [String] else {
            return false
        }
        return arguments == ["/usr/bin/open", applicationURL.path]
    }

    private static func runLaunchctl(arguments: [String]) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}

enum LoginItemServiceFactory {
    static func make() -> LoginItemServicing {
        let fallback = LaunchAgentLoginItemService()
        if fallback.hasConfiguration {
            return fallback
        }
        let service = SMAppService.mainApp
        return service.status == .notFound ? fallback : service
    }
}

private enum LoginItemManagerError: LocalizedError {
    case applicationNotFound

    var errorDescription: String? {
        switch self {
        case .applicationNotFound:
            return "找不到可注册的 Tokei.app，请将应用移到“应用程序”后重试"
        }
    }
}

@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()
    nonisolated static let requestedDefaultsKey = "launchAtLoginRequested"

    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    private let service: LoginItemServicing
    private let defaults: UserDefaults

    private init() {
        service = LoginItemServiceFactory.make()
        defaults = .standard
        refresh()
        repairRegistrationIfNeeded()
    }

    init(service: LoginItemServicing, defaults: UserDefaults) {
        self.service = service
        self.defaults = defaults
        refresh()
        repairRegistrationIfNeeded()
    }

    func refresh() {
        let status = service.status
        enabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
        if enabled {
            defaults.set(true, forKey: Self.requestedDefaultsKey)
            if status == .enabled {
                errorMessage = nil
            }
        } else if status == .notFound,
                  defaults.bool(forKey: Self.requestedDefaultsKey) {
            errorMessage = LoginItemManagerError.applicationNotFound.localizedDescription
        }
    }

    func setEnabled(_ shouldEnable: Bool) {
        errorMessage = nil
        defaults.set(shouldEnable, forKey: Self.requestedDefaultsKey)
        do {
            switch (shouldEnable, service.status) {
            case (true, .notRegistered):
                try service.register()
            case (true, .notFound):
                throw LoginItemManagerError.applicationNotFound
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        scheduleRefresh()
    }

    /// 每次启动都检查:用户之前明明要求开机自启动(这份意图单独存在 UserDefaults,不完全
    /// 信任系统自己报告的状态),但注册状态却是 notRegistered——多半是重新签名/重装导致
    /// 系统悄悄丢了注册,这里自动补一次,不需要用户手动去开关里重新点一下。
    @discardableResult
    func repairRegistrationIfNeeded() -> Bool {
        guard defaults.bool(forKey: Self.requestedDefaultsKey),
              service.status == .notRegistered else {
            refresh()
            return false
        }
        do {
            try service.register()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        scheduleRefresh()
        return enabled
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }
}
