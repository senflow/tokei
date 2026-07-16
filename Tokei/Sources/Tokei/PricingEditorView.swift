import SwiftUI

struct PricingEntry: Identifiable {
    let id: String
    let baseIn: Double; let baseOut: Double; let baseCR: Double; let baseCW: Double
    var editIn: String; var editOut: String; var editCR: String; var editCW: String
    var isOverride: Bool

    var effIn: Double { Double(editIn.replacingOccurrences(of: ",", with: ".")) ?? baseIn }
    var effOut: Double { Double(editOut.replacingOccurrences(of: ",", with: ".")) ?? baseOut }
    var effCR: Double { Double(editCR.replacingOccurrences(of: ",", with: ".")) ?? baseCR }
    var effCW: Double { Double(editCW.replacingOccurrences(of: ",", with: ".")) ?? baseCW }

    // 模型 ID 形如 "vendor/model-name",取 "/" 前的部分作为厂商。
    var vendor: String {
        guard let slash = id.firstIndex(of: "/") else { return "其他" }
        return String(id[id.startIndex..<slash])
    }
}

struct PricingEditorView: View {
    // 价格表放在独立窗口里显示(而不是挂在菜单栏 NSPopover 上的 .sheet),
    // 避免 popover 在 sheet 打开时被外部点击关掉、留下悬挂的 modal 会话导致整个 app 卡死。
    var onClose: () -> Void = {}
    @State private var entries: [PricingEntry] = []
    @State private var searchText = ""
    @State private var selectedVendor = "全部"
    @AppStorage("cnyExchangeRate") private var exchangeRate: Double = 7.25
    @State private var rateText: String = ""
    @State private var saving = false
    @State private var saveResult = ""

    private static let allVendors = "全部"
    private var vendors: [String] {
        [Self.allVendors] + Set(entries.map(\.vendor)).sorted()
    }

    private var pricingPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tokei/pricing.json").path
    }
    private var overridesPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tokei/pricing_overrides.json").path
    }

    var filtered: [PricingEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { entry in
            (selectedVendor == Self.allVendors || entry.vendor == selectedVendor)
                && (q.isEmpty || entry.id.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("模型价格表")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(filtered.count == entries.count ? "(\(entries.count) 个模型)" : "(\(filtered.count)/\(entries.count) 个模型)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if !saveResult.isEmpty {
                    Text(saveResult).font(.system(size: 10))
                        .foregroundStyle(saveResult.contains("✓") ? Color.green : Color.red)
                }
                if saving {
                    ProgressView().controlSize(.small)
                }
                Button("保存") { saveOverrides() }
                    .font(.system(size: 11, weight: .medium))
                    .disabled(saving)
                Button("关闭") { onClose() }
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider()

            // Exchange rate + search
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("汇率:").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("", text: $rateText)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 50)
                        .onSubmit { if let v = Double(rateText), v > 0 { exchangeRate = v } }
                        .onAppear { rateText = String(format: "%.2f", exchangeRate) }
                    Text("CNY/USD")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 16)
                Text("数据来源: OpenRouter API")
                    .font(.system(size: 9)).foregroundStyle(.secondary)

                Spacer()

                Picker("", selection: $selectedVendor) {
                    ForEach(vendors, id: \.self) { v in
                        Text(v).tag(v)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .controlSize(.small)

                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    TextField("搜索模型...", text: $searchText)
                        .font(.system(size: 10))
                        .frame(width: 140)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            // Column headers
            HStack(spacing: 0) {
                Text("模型 ID").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 260, alignment: .leading)
                headerCell("输入 $/M", w: 72)
                headerCell("输出 $/M", w: 72)
                headerCell("缓存读 $/M", w: 78)
                headerCell("缓存写 $/M", w: 78)
                headerCell("≈CNY/M", w: 72)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))

            Divider()

            // List
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { entry in
                        PricingRow(entry: binding(for: entry.id), rate: exchangeRate)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(width: 700, height: 520)
        .background(Theme.isDark ? Color(red: 0.12, green: 0.12, blue: 0.14)
                                : Color(red: 0.96, green: 0.96, blue: 0.98))
        .onAppear { loadPrices() }
    }

    private func headerCell(_ t: String, w: CGFloat) -> some View {
        Text(t).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            .frame(width: w, alignment: .trailing)
    }

    private func binding(for id: String) -> Binding<PricingEntry> {
        Binding(
            get: { entries.first(where: { $0.id == id }) ?? PricingEntry(id: "", baseIn: 0, baseOut: 0, baseCR: 0, baseCW: 0, editIn: "", editOut: "", editCR: "", editCW: "", isOverride: false) },
            set: { newVal in
                if let idx = entries.firstIndex(where: { $0.id == id }) {
                    entries[idx] = newVal
                }
            }
        )
    }

    private func loadPrices() {
        guard let baseData = try? Data(contentsOf: URL(fileURLWithPath: pricingPath)),
              let base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any],
              let models = base["models"] as? [String: [String: Double]] else { return }

        var overrides: [String: [String: Double]] = [:]
        if let ovData = try? Data(contentsOf: URL(fileURLWithPath: overridesPath)),
           let ov = try? JSONSerialization.jsonObject(with: ovData) as? [String: Any],
           let ovModels = ov["models"] as? [String: [String: Double]] {
            overrides = ovModels
        }

        entries = models.sorted(by: { $0.key < $1.key }).map { (key, prices) in
            let ov = overrides[key]
            let hasOv = ov != nil
            let pIn = ov?["in"] ?? prices["in"] ?? 0
            let pOut = ov?["out"] ?? prices["out"] ?? 0
            let pCR = ov?["cache_read"] ?? prices["cache_read"] ?? 0
            let pCW = ov?["cache_write"] ?? prices["cache_write"] ?? 0
            return PricingEntry(
                id: key,
                baseIn: prices["in"] ?? 0, baseOut: prices["out"] ?? 0,
                baseCR: prices["cache_read"] ?? 0, baseCW: prices["cache_write"] ?? 0,
                editIn: String(format: "%g", pIn), editOut: String(format: "%g", pOut),
                editCR: String(format: "%g", pCR), editCW: String(format: "%g", pCW),
                isOverride: hasOv
            )
        }
    }

    private func saveOverrides() {
        saving = true
        saveResult = ""
        DispatchQueue.global(qos: .userInitiated).async {
            var overrides: [String: [String: Double]] = [:]
            for e in entries {
                if e.effIn == e.baseIn, e.effOut == e.baseOut,
                   e.effCR == e.baseCR, e.effCW == e.baseCW { continue }
                overrides[e.id] = [
                    "in": e.effIn, "out": e.effOut,
                    "cache_read": e.effCR, "cache_write": e.effCW
                ]
            }

            // Preserve existing aliases
            var root: [String: Any] = ["models": overrides]
            if let ovData = try? Data(contentsOf: URL(fileURLWithPath: overridesPath)),
               let ov = try? JSONSerialization.jsonObject(with: ovData) as? [String: Any],
               let aliases = ov["aliases"] {
                root["aliases"] = aliases
            }

            if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: overridesPath))
                DispatchQueue.main.async {
                    saving = false
                    saveResult = "✓ 已保存"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { saveResult = "" }
                }
            } else {
                DispatchQueue.main.async {
                    saving = false
                    saveResult = "保存失败"
                }
            }
        }
    }
}

struct PricingRow: View {
    @Binding var entry: PricingEntry
    var rate: Double

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if entry.isOverride {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                        .help("已自定义")
                }
                Text(entry.id)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(entry.isOverride ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 260, alignment: .leading)

            priceField($entry.editIn, w: 72)
            priceField($entry.editOut, w: 72)
            priceField($entry.editCR, w: 78)
            priceField($entry.editCW, w: 78)

            // CNY equivalent
            let cny = (entry.effIn + entry.effOut + entry.effCR + entry.effCW) * rate
            Text(String(format: "%.2f", cny))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(entry.isOverride ? Theme.primary.opacity(0.04) : Color.clear)
    }

    private func priceField(_ text: Binding<String>, w: CGFloat) -> some View {
        TextField("", text: text)
            .font(.system(size: 9.5, design: .monospaced))
            .frame(width: w)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.plain)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
    }
}
