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
    @Published var refreshing = false

    let syncManager = SyncManager()
    var autoSyncTimer: Timer?

    // 数据范围: "__all__"(全部合并)、"__local__"(仅本机)、或某台 peer 的 deviceId。
    static let allScope = "__all__"
    static let localScope = "__local__"
    @AppStorage("deviceScope") var deviceScope: String = Store.allScope
    @AppStorage("syncEnabled") var syncEnabled = false
    @AppStorage("preferredColorScheme") var colorScheme: String = "light"

    private var retryCount = 0

    func applyDisplayMode(updateStatusTitle: Bool = true) {
        usage = resolvedUsage()
        if updateStatusTitle {
            (NSApp.delegate as? AppDelegate)?.updateStatusTitle()
        }
    }

    private func resolvedUsage() -> Usage? {
        guard syncEnabled else { return localUsage }
        switch deviceScope {
        case Store.allScope:
            return allDevicesUsage ?? localUsage
        case Store.localScope:
            return localUsage
        default:
            if let peer = peers.first(where: { $0.deviceId == deviceScope }) {
                return peer.usage
            }
            return allDevicesUsage ?? localUsage
        }
    }

    func refresh() {
        refreshing = true
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
                    self.refreshing = false
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
            self.refreshing = false
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
    var pricingWindow: NSWindow?

    // Menu bar icon colour
    static let iconColor = NSColor.white

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

        // 启动时先把 Qoder IDE 开关状态落盘到 config.json,
        // 确保随后的 refresh() 触发的 Python 扫描能读到正确的 qoder_ide_enabled。
        PanelView.syncQoderIdeConfigOnLaunch()
        store.refresh()
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
            // 若 popover 上还挂着 sheet 或子窗口,直接关掉 popover 会把 sheet 的
            // modal 会话遗留下来,导致整个 app 卡死。此时不主动关闭。
            if let popoverWindow = self.popover.contentViewController?.view.window,
               popoverWindow.attachedSheet != nil || !(popoverWindow.childWindows ?? []).isEmpty {
                return
            }
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
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [Self.iconColor]))
        let img = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = false
        b.image = img
        b.imagePosition = .imageOnly
        b.attributedTitle = NSAttributedString()
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

    /// 在独立窗口里打开价格表。不再用挂在 popover 上的 .sheet,
    /// 避免 popover 生命周期(外部点击关闭等)与 sheet 冲突导致的卡死。
    func showPricingEditor() {
        if let w = pricingWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: PricingEditorView(onClose: { [weak self] in
            self?.pricingWindow?.close()
        }))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "模型价格表"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        pricingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w == pricingWindow {
            pricingWindow = nil
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
                .background(Color(red: 0.11, green: 0.11, blue: 0.13))
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
