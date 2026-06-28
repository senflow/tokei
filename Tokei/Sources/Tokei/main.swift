import AppKit
import SwiftUI
import Combine

final class Store: ObservableObject {
    @Published var usage: Usage?
    @Published var localUsage: Usage?
    @Published var allDevicesUsage: Usage?
    @Published var lastUpdated: String = "加载中…"
    @Published var loadError: String?
    @Published var peers: [PeerDevice] = []
    @Published var syncing = false

    let syncManager = SyncManager()
    let keepAwake = KeepAwake()
    let sitReminder = SitReminder()
    var autoSyncTimer: Timer?

    @AppStorage("showAllDevices") var showAllDevices = true
    @AppStorage("syncEnabled") var syncEnabled = false

    private var retryCount = 0

    func applyDisplayMode(updateStatusTitle: Bool = true) {
        usage = (syncEnabled && showAllDevices) ? (allDevicesUsage ?? localUsage) : localUsage
        if updateStatusTitle {
            (NSApp.delegate as? AppDelegate)?.updateStatusTitle()
        }
    }

    func refresh() {
        DataLoader.load { [weak self] u in
            guard let self = self else { return }
            guard let local = u else {
                if self.usage == nil && self.retryCount < 3 {
                    self.retryCount += 1
                    self.lastUpdated = "加载中…(\(self.retryCount))"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.refresh() }
                } else {
                    self.loadError = "读取用量失败"
                    self.lastUpdated = "加载失败"
                }
                (NSApp.delegate as? AppDelegate)?.updateStatusTitle()
                return
            }
            self.retryCount = 0
            self.loadError = nil
            self.localUsage = local
            var allDevices = local
            if self.syncEnabled {
                let p = self.syncManager.loadPeers()
                self.peers = p
                if !p.isEmpty { allDevices = SyncManager.merge(local: local, peers: p) }
            } else {
                self.peers = []
            }
            self.allDevicesUsage = allDevices
            self.applyDisplayMode(updateStatusTitle: false)
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            self.lastUpdated = "更新 " + f.string(from: Date())
            (NSApp.delegate as? AppDelegate)?.updateStatusTitle()
        }
    }

    func doSync() {
        syncing = true
        syncManager.gitSync { [weak self] ok in
            self?.syncing = false
            if ok { self?.refresh() }
        }
    }

    func startAutoSync(minutes: Int) {
        stopAutoSync()
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60),
                                             repeats: true) { [weak self] _ in self?.doSync() }
    }

    func stopAutoSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var timer: Timer?
    var globalMouseMonitor: Any?

    // 菜单栏家族品牌色(与面板 Theme.claude/codex 一致)。
    static let claudeColor = NSColor(red: 0.92, green: 0.52, blue: 0.40, alpha: 1)
    static let codexColor  = NSColor(red: 0.42, green: 0.68, blue: 0.98, alpha: 1)

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.action = #selector(togglePopover)
            b.target = self
        }
        updateStatusTitle()

        let host = NSHostingController(rootView: PanelView(store: store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .applicationDefined
        popover.animates = true

        store.refresh()
        store.sitReminder.updateRunning()
        Updater.shared.checkForUpdate()
        autoFetchPricing()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }
        Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Updater.shared.checkForUpdate()
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.popover.isShown else { return }
            if let popoverWindow = self.popover.contentViewController?.view.window,
               popoverWindow == event.window { return }
            self.popover.close()
        }

        if CommandLine.arguments.contains("--autoshow") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.togglePopover()
            }
        }
    }

    func updateStatusTitle() {
        guard let b = statusItem?.button else { return }
        let s = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        // 一格 = 时钟图标 + 5h 剩余%,按家族品牌色着色(橙=Claude 青=Codex)。
        func seg(_ value: String, _ color: NSColor) {
            if s.length > 0 {
                s.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            }
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            let img = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = false
            let att = NSTextAttachment(); att.image = img
            s.append(NSAttributedString(attachment: att))
            s.append(NSAttributedString(string: " " + value,
                attributes: [.font: font, .baselineOffset: 1, .foregroundColor: color]))
        }

        if store.keepAwake.active {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [Self.claudeColor]))
            let img = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = false
            let att = NSTextAttachment(); att.image = img
            s.append(NSAttributedString(attachment: att))
        }

        if let u = store.usage {
            let ud = UserDefaults.standard
            if ud.object(forKey: "showClaude") as? Bool ?? true,
               let q5 = u.claude.q5 { seg(String(format: "%.0f", 100 - q5), Self.claudeColor) }
            if ud.object(forKey: "showCodex") as? Bool ?? true,
               let p5 = u.codex.p5 { seg(String(format: "%.0f", 100 - p5), Self.codexColor) }
            if s.length == 0 {
                let showC = ud.object(forKey: "showClaude") as? Bool ?? true
                let showX = ud.object(forKey: "showCodex") as? Bool ?? true
                let showP = ud.object(forKey: "showPi") as? Bool ?? true
                let showO = ud.object(forKey: "showOpenCode") as? Bool ?? true
                let showQ = ud.object(forKey: "showQoderIde") as? Bool ?? false
                var total = 0
                if showC { let r = u.claude.ranges.get(.today); total += Int(r.in + r.out + r.cr + r.cw) }
                if showX { let r = u.codex.ranges.get(.today); total += Int(r.in + r.out + r.cached + r.reason) }
                if showP { let r = u.pi.ranges.get(.today); total += Int(r.in + r.out + r.cr + r.cw + r.reason) }
                if showO { let r = u.opencode.ranges.get(.today); total += Int(r.in + r.out + r.cr + r.cw + r.reason) }
                if showQ { let r = u.qoder.ranges.get(.today); total += Int(r.in + r.out + r.cached) }
                if total > 0 {
                    seg(Fmt.human(total), .secondaryLabelColor)
                } else {
                    let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                        .applying(NSImage.SymbolConfiguration(paletteColors: [Self.claudeColor]))
                    let img = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)?
                        .withSymbolConfiguration(cfg)
                    img?.isTemplate = false
                    let att = NSTextAttachment(); att.image = img
                    s.append(NSAttributedString(attachment: att))
                }
            }
        } else {
            seg("…", .secondaryLabelColor)                        // 加载中
        }
        b.attributedTitle = s
        b.image = nil
    }

    func autoFetchPricing() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["python3", DataLoader.scriptPath, "--update-prices"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            DispatchQueue.main.async { self?.store.refresh() }
        }
    }

    @objc func togglePopover() {
        guard let b = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// 离屏截图模式:Tokei --shot /path/out.png
enum Shot {
    static func run(path: String) {
        _ = NSApplication.shared
        var usage: Usage?
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { usage = DataLoader.loadSync(); sem.signal() }
        sem.wait()
        MainActor.assumeIsolated {
            let store = Store()
            store.usage = usage
            store.lastUpdated = "预览"
            let content = PanelView(store: store, scrollable: false)
                .background(Color(red: 0.22, green: 0.23, blue: 0.26))
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
            }
        }
        exit(0)
    }
}

// 品牌 Logo(用于 app icon / 通知图标):珊瑚渐变 squircle + 白色知度符号。
struct LogoView: View {
    var body: some View {
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .fill(LinearGradient(colors: [
                        Color(red: 0.97, green: 0.64, blue: 0.50),
                        Color(red: 0.90, green: 0.46, blue: 0.37),
                        Color(red: 0.82, green: 0.38, blue: 0.33)],
                        startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .clear],
                        startPoint: .top, endPoint: .center))
                Image(systemName: "timer")
                    .font(.system(size: 440, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.20), radius: 22, y: 10)
            }
            .frame(width: 824, height: 824)
            .shadow(color: .black.opacity(0.28), radius: 34, y: 20)
        }
        .frame(width: 1024, height: 1024)
    }
}

enum Icon {
    static func run(path: String) {
        _ = NSApplication.shared
        MainActor.assumeIsolated {
            let r = ImageRenderer(content: LogoView())
            r.scale = 1
            if let cg = r.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
            }
        }
        exit(0)
    }
}

if let idx = CommandLine.arguments.firstIndex(of: "--make-icon") {
    let out = CommandLine.arguments.count > idx + 1
        ? CommandLine.arguments[idx + 1] : "/tmp/tokei_icon.png"
    Icon.run(path: out)
}

if let idx = CommandLine.arguments.firstIndex(of: "--shot") {
    let out = CommandLine.arguments.count > idx + 1
        ? CommandLine.arguments[idx + 1] : "/tmp/tokei_shot.png"
    Shot.run(path: out)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
