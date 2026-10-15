import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ToolsView: View {
    @EnvironmentObject var store: PortfolioStore
    var body: some View {
        Page {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tile("股息複利", "試算長期複利效果", art: "tool-compound") { PlanView() }
                tile("領息目標", "設定並追蹤目標", art: "tool-goal") { GoalView() }
                tile("定期定額", "試算投入成果", art: "tool-dca") { CalculatorView() }
                tile("三檔比較", "快速比較多檔 ETF", art: "tool-compare") { ComparisonView() }
                tile("持股透視", "合併成分股曝險", art: "tool-exposure") { ExposureView() }
                tile("提醒中心", "配息入帳提醒", art: "tool-alerts") { ReminderCenterView() }
            }
            ComparisonPreview()
            SectionHeading(title: "連線與資料")
            DataLinks()
            PrivacyNote()
        }
        .navigationTitle("工具").navigationBarTitleDisplayMode(.inline)
    }
    private func tile<Destination: View>(_ title: String, _ subtitle: String, art: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink { destination() } label: {
            VStack(spacing: 8) {
                Artwork(name: art, size: 52)
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(subtitle).font(.caption).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18).padding(.horizontal, 8)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Palette.blue.opacity(0.07), radius: 10, y: 4)
        }.buttonStyle(.plain)
    }
}
struct DataLinks: View {
    var body: some View {
        Card(padding: 12) {
            NavigationLink { ConnectionView() } label: { ToolRow(title: "富果行情連線", subtitle: "使用你自己的 API Key", icon: "waveform.path") }
            Divider()
            NavigationLink { BrokerView() } label: { ToolRow(title: "券商持有資料", subtitle: "所有券商 CSV 欄位對應與預覽", icon: "building.columns") }
            Divider()
            NavigationLink { BackupView() } label: { ToolRow(title: "資料備份", subtitle: "匯出與匯入，保留你的每筆紀錄", icon: "externaldrive") }
        }.buttonStyle(.plain)
    }
}
struct PrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) { Image(systemName: "lock.shield").foregroundStyle(Palette.blue); VStack(alignment: .leading, spacing: 6) { Text("你的紀錄，留在你的手機").font(.subheadline.bold()).foregroundStyle(Palette.ink); Text("持有與配息儲存在本機，行情金鑰使用 iOS Keychain 保存，不包含在備份內。").font(.caption).foregroundStyle(Palette.muted) } }.padding(.horizontal, 4)
        Text("ETF 袋著走 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · 原生 iPhone App").font(.caption2).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.top, 10)
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: PortfolioStore
    var body: some View {
        Page {
            DataLinks()
            Card {
                Text("ETF 名單").font(.headline).foregroundStyle(Palette.ink)
                if let catalog = store.catalog, !store.isDemo { Text("上市資料日 \(catalog.listedDate) · 上櫃取得日 \(catalog.fetchedDay) · 共 \(catalog.funds.count) 個代碼").font(.caption).foregroundStyle(Palette.muted).padding(.top, 6) }
                if let message = store.catalogMessage { Text(message).font(.caption).foregroundStyle(Palette.muted).padding(.top, 6) }
                Button(store.catalogRefreshing ? "更新中…" : "更新上市櫃名單") { Task { await store.refreshCatalog() } }.buttonStyle(.bordered).disabled(store.catalogRefreshing || store.isDemo).padding(.top, 10)
            }
            PrivacyNote()
        }.navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
    }
}
enum ComparisonDefaults {
    static func symbols(_ saved: [String]?) -> [String] {
        var result: [String] = []
        for code in (saved ?? []) where result.count < 3 && !result.contains(code) { result.append(code) }
        for code in ["0050", "00878", "00919", "0056", "006208"] where result.count < 3 && !result.contains(code) { result.append(code) }
        return result
    }
}
struct ComparisonTable: View {
    @EnvironmentObject var store: PortfolioStore
    let symbols: [String]
    var detailed = false
    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 10) {
            GridRow {
                Text("項目").gridColumnAlignment(.leading)
                ForEach(symbols, id: \.self) { Text($0).font(.caption.bold()).foregroundStyle(Palette.blue) }
            }
            Divider()
            if detailed {
                line("名稱") { Text(store.name(for: $0)).lineLimit(2).multilineTextAlignment(.trailing) }
                line("策略") { symbol in StrategyPill(strategy: store.funds.first { $0.id == symbol }?.strategy ?? .unclassified) }
            }
            line("最新價") { symbol in Text(store.data.quotes[symbol].map { priceText($0.price) } ?? "—") }
            line("漲跌幅") { symbol in
                let percent = store.data.quotes[symbol]?.changePercent
                Text(percent.map(percentText) ?? "—").foregroundStyle(percent.map(Palette.trend) ?? Palette.muted)
            }
            line("年度總費用率") { symbol in Text(AnnualFeeCatalog.bundled?.records[symbol].map { "\(decimal($0.total))%" } ?? "未收錄") }
            if detailed {
                line("報價日期") { symbol in Text(store.data.quotes[symbol]?.date ?? "—") }
                line("已揭露成分") { symbol in Text(store.data.components?[symbol].map { "\($0.components.count) 檔" } ?? "—") }
                line("年化波動") { symbol in Text(volatility(symbol).map { "\(decimal($0 * 100))%" } ?? "—") }
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.ink)
    }
    private func line<Cell: View>(_ title: String, @ViewBuilder cell: @escaping (String) -> Cell) -> some View {
        GridRow {
            Text(title).foregroundStyle(Palette.muted).gridColumnAlignment(.leading)
            ForEach(symbols, id: \.self) { symbol in cell(symbol).monospacedDigit() }
        }
    }
    private func volatility(_ symbol: String) -> Double? {
        guard let history = store.data.histories?[symbol] else { return nil }
        return (try? PerformanceStats(history))?.volatility
    }
}
struct ComparisonPreview: View {
    @EnvironmentObject var store: PortfolioStore
    var body: some View {
        NavigationLink { ComparisonView() } label: {
            Card {
                HStack {
                    Artwork(name: "tool-compare", size: 24)
                    Text("三檔 ETF 比較").font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    HStack(spacing: 2) { Text("完整比較"); Image(systemName: "chevron.right") }.font(.caption).foregroundStyle(Palette.blue)
                }.padding(.bottom, 12)
                ComparisonTable(symbols: ComparisonDefaults.symbols(store.data.comparison))
                Text("在 ETF 詳情按「加入比較」即可更換；未取得報價或未收錄的欄位不顯示估計值。").font(.caption2).foregroundStyle(Palette.muted).padding(.top, 10)
            }
        }.buttonStyle(.plain)
    }
}
struct ComparisonView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var symbols = ComparisonDefaults.symbols(nil)
    @State private var pair = 0
    private var pairs: [(String, String)] { [(symbols[0], symbols[1]), (symbols[0], symbols[2]), (symbols[1], symbols[2])] }
    var body: some View { Page {
        HStack(spacing: 8) { ForEach(0..<3, id: \.self) { fundPicker($0) } }
        Card { ComparisonTable(symbols: symbols, detailed: true) }
        Picker("重疊比較", selection: $pair) { ForEach(0..<3, id: \.self) { i in Text("\(pairs[i].0) × \(pairs[i].1)").tag(i) } }.pickerStyle(.segmented)
        OverlapPanel(left: pairs[pair].0, right: pairs[pair].1)
        Text("策略分類為初步標籤，資料日期與範圍須一起比較。殖利率需要完整配息資料，未收錄前不顯示。").font(.caption).foregroundStyle(Palette.muted)
    }.navigationTitle("三檔比較").navigationBarTitleDisplayMode(.inline)
        .onAppear { symbols = ComparisonDefaults.symbols(store.data.comparison) }
    }
    private func save() { var next = store.data; next.comparison = symbols; do { try store.commit(next) } catch { store.message = error.localizedDescription } }
    private func fundPicker(_ index: Int) -> some View {
        Picker("第 \(index + 1) 檔", selection: Binding(get: { symbols[index] }, set: { symbols[index] = $0; save() })) { ForEach(store.funds) { Text($0.id).tag($0.id) } }
            .pickerStyle(.menu).frame(maxWidth: .infinity).padding(8).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}
struct CalculatorView: View {
    @State private var initial = "100000"
    @State private var monthly = "5000"
    @State private var years = 10
    @State private var rate = 4.0
    var valid: Bool { guard let a = Double(initial), let b = Double(monthly) else { return false }; return a.isFinite && b.isFinite && a >= 0 && b >= 0 && a <= 1e12 && b <= 1e9 }
    var total: Double { Projection.value(initial: Double(initial) ?? 0, monthly: Double(monthly) ?? 0, years: years, annualPercent: rate) }
    var principal: Double { (Double(initial) ?? 0) + (Double(monthly) ?? 0) * Double(years * 12) }
    var body: some View { Form {
        Section("投入計畫") { TextField("起始本金（元）", text: $initial).keyboardType(.decimalPad); TextField("每月底投入（元）", text: $monthly).keyboardType(.decimalPad); Stepper("累積 \(years) 年", value: $years, in: 1...40); VStack(alignment: .leading) { Text("假設年報酬率 \(decimal(rate))%"); Slider(value: $rate, in: -10...15, step: 0.5) } }
        Section("試算結果") { if valid { LabeledContent("累計投入", value: "$\(money(principal))"); LabeledContent("期末試算金額", value: "$\(money(total))").foregroundStyle(Palette.blue); LabeledContent("試算損益", value: "$\(money(total - principal))") } else { Text("請輸入有效且非負的本金及每月投入金額。").foregroundStyle(.red) } }
        Section { Text("假設報酬按月平均複利、每月底投入，不含稅費與通膨。這是情境試算，不是預測或保證。負報酬情境下可能虧損本金。").font(.footnote).foregroundStyle(.secondary) }
    }.navigationTitle("定期定額試算").navigationBarTitleDisplayMode(.inline) }
}
struct GoalView: View {
    @EnvironmentObject var store: PortfolioStore
    @AppStorage("goalMonthlyIncome") private var target = 10000.0
    @AppStorage("goalAssumedYield") private var assumedYield = 5.0
    private var lastYearPaid: Double {
        let start = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
        return store.data.dividends.filter { $0.status == .paid && $0.date >= start && $0.date <= Date() }.reduce(0.0) { $0 + $1.amount }
    }
    var body: some View {
        let monthly = lastYearPaid / 12
        let goal = max(target, 0)
        let progress = goal > 0 ? min(monthly / goal, 1) : 0
        let needed = goal * 12 / (assumedYield / 100)
        Form {
            Section("我的目標") {
                HStack { Text("每月領息目標"); TextField("元", value: $target, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section("目前進度（近 12 個月已入帳）") {
                LabeledContent("平均每月已領", value: "$\(money(monthly))")
                ProgressView(value: progress) { Text("已達成 \(decimal(progress * 100))%") }.tint(Palette.purple)
                LabeledContent("近 12 個月合計", value: "$\(money(lastYearPaid))")
            }
            Section("需要多少本金？（情境試算）") {
                VStack(alignment: .leading) { Text("假設年殖利率 \(decimal(assumedYield))%"); Slider(value: $assumedYield, in: 1...12, step: 0.5) }
                LabeledContent("約需投入本金", value: "$\(money(needed))")
                LabeledContent("與目前投入成本差距", value: "$\(money(max(0, needed - store.data.cost)))")
            }
            Section { Text("進度只計算你記錄為「已入帳」的配息，不含已公告與預估。所需本金以固定殖利率估算；配息率不等於報酬率，配息也可能來自本金。這是情境試算，不是保證收益。").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("領息目標").navigationBarTitleDisplayMode(.inline)
    }
}
enum DividendReminders {
    static let key = "dividendReminders"
    private static let prefix = "dividend-"
    static func syncIfEnabled(_ dividends: [Dividend]) async {
        guard UserDefaults.standard.bool(forKey: key) else { return }
        await sync(dividends)
    }
    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    /// Schedules a 09:00 reminder on the expected payment day of each announced or estimated dividend.
    @discardableResult static func sync(_ dividends: [Dividend]) async -> Int {
        await clear()
        let center = UNUserNotificationCenter.current()
        let now = Date()
        var scheduled = 0
        for item in dividends.filter({ $0.status != .paid }).sorted(by: { $0.date < $1.date }) where scheduled < 60 {
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: item.date)
            parts.hour = 9
            guard let fire = Calendar.current.date(from: parts), fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "配息提醒：\(item.symbol)"
            content.body = "\(item.status.rawValue)配息 $\(money(item.amount)) 預計今天入帳。確認入帳後，可在配息月曆長按紀錄標記為已入帳。"
            content.sound = .default
            let request = UNNotificationRequest(identifier: prefix + item.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            do { try await center.add(request); scheduled += 1 } catch { continue }
        }
        return scheduled
    }
    static func clear() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }
}
struct ReminderCenterView: View {
    @EnvironmentObject var store: PortfolioStore
    @AppStorage(DividendReminders.key) private var enabled = false
    @State private var working = false
    @State private var note: String?
    private var upcoming: [Dividend] {
        let today = Calendar.current.startOfDay(for: Date())
        return store.data.dividends.filter { $0.status != .paid && $0.date >= today }.sorted { $0.date < $1.date }
    }
    var body: some View {
        Page {
            Card {
                Toggle(isOn: Binding(get: { enabled }, set: { value in Task { await setEnabled(value) } })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("配息入帳提醒").font(.headline).foregroundStyle(Palette.ink)
                        Text("在已公告／預估配息的預計入帳日早上 9 點通知").font(.caption).foregroundStyle(Palette.muted)
                    }
                }.tint(Palette.blue).disabled(working || store.isDemo)
                if let note { Text(note).font(.caption).foregroundStyle(Palette.muted).padding(.top, 10) }
            }
            SectionHeading(title: "即將入帳", subtitle: "依你的配息紀錄")
            if upcoming.isEmpty {
                Card { ContentUnavailableView("目前沒有待入帳配息", systemImage: "bell.slash", description: Text("在配息月曆新增「已公告」或「預估」的紀錄。")) }
            } else {
                Card(padding: 14) {
                    ForEach(upcoming) { item in
                        HStack(spacing: 10) {
                            Text(monthDay(item.date)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.blue).frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(item.symbol) \(store.name(for: item.symbol))").font(.subheadline).foregroundStyle(Palette.ink).lineLimit(1)
                                Text("$\(money(item.amount))").font(.caption).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            StatusPill(status: item.status)
                        }.padding(.vertical, 6)
                    }
                }
            }
            Card {
                Label("價格與折溢價提醒", systemImage: "chart.line.uptrend.xyaxis").font(.headline).foregroundStyle(Palette.ink)
                Text("需要背景行情服務，目前尚未提供；不會以過期報價觸發通知。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 6)
            }
        }.navigationTitle("提醒中心").navigationBarTitleDisplayMode(.inline)
    }
    private func setEnabled(_ value: Bool) async {
        working = true
        defer { working = false }
        if value {
            guard await DividendReminders.requestAccess() else { enabled = false; note = "未取得通知權限，可到 iPhone 設定 › 通知 開啟。"; return }
            enabled = true
            let count = await DividendReminders.sync(store.data.dividends)
            note = "已排程 \(count) 則提醒。新增或刪除配息紀錄時會自動更新。"
        } else {
            enabled = false
            await DividendReminders.clear()
            note = "已關閉並清除排程提醒。"
        }
    }
}
struct ConnectionView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var key = ""
    @State private var hasKey = false
    @State private var message = ""
    var body: some View { Form {
        Section { Label(hasKey ? "已儲存金鑰" : "尚未設定金鑰", systemImage: hasKey ? "key.fill" : "key").foregroundStyle(hasKey ? Palette.green : .secondary); SecureField("貼上富果 API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled(); Button("安全儲存金鑰") { do { guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { message = "請先輸入金鑰。"; return }; try SecureKey.save(key); key = ""; hasKey = true; message = "已存入這台 iPhone 的 Keychain；尚未驗證行情權限。" } catch { message = error.localizedDescription } }.disabled(store.isDemo) }
        Section { Button(store.refreshing ? "連線中…" : "驗證連線並取得 0050 報價") { Task { await store.refresh(symbols: ["0050"]); if store.message == nil, let quote = store.data.quotes["0050"] { message = "已取得 \(quote.date) 報價：\(decimal(quote.price)) 元。" } } }.disabled(!hasKey || store.refreshing || store.isDemo); if hasKey { Button("移除金鑰", role: .destructive) { do { try SecureKey.remove(); hasKey = false; message = "已移除金鑰。" } catch { message = error.localizedDescription } }.disabled(store.isDemo) } }
        if !message.isEmpty { Section { Text(message).font(.subheadline) } }
        Section { Link("申請或管理富果行情金鑰", destination: URL(string: "https://developer.fugle.tw/docs/key/")!); Text("金鑰只傳送給富果官方 API，且不寫入備份。是否即時、可用商品與請求額度依你的富果方案而定。").font(.footnote).foregroundStyle(.secondary); Link("查看富果行情 API 說明", destination: URL(string: "https://developer.fugle.tw/docs/data/http-api/getting-started/")!) }
    }.navigationTitle("行情連線").navigationBarTitleDisplayMode(.inline).onAppear { do { hasKey = !(try SecureKey.read()).isEmpty } catch { message = error.localizedDescription } } }
}
struct BackupView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var pending: Data?
    @State private var preview: Portfolio?
    @State private var confirmation = false
    @State private var message = ""
    var body: some View { Form {
        Section("匯出") { Text("包含持有、配息、收藏與已取得報價，不包含行情金鑰。").font(.subheadline).foregroundStyle(.secondary); Button("建立備份檔") { do { exportURL = try store.export() } catch { message = error.localizedDescription } }; if let exportURL { ShareLink("儲存或分享備份", item: exportURL) } }
        Section("匯入") { Button("選擇備份檔") { importing = true }; Text("匯入會合併紀錄；相同識別碼更新，其他現有紀錄保留。支援目前原生版、舊原生版與 PWA 備份。匯入前顯示筆數並保留復原副本；舊版手填參考價保留在備份中，不當成即時報價。").font(.footnote).foregroundStyle(.secondary) }
        if let preview { Section("預覽") { LabeledContent("持有", value: "\(preview.holdings.count) 筆"); LabeledContent("配息", value: "\(preview.dividends.count) 筆"); LabeledContent("收藏", value: "\(preview.favorites.count) 檔"); LabeledContent("投入成本", value: "$\(money(preview.cost))"); if preview.legacyPlan != nil { Text("包含舊版試算設定，會可在「股息複利」繼續使用。") }; Button("確認合併匯入") { confirmation = true } } }
        if !message.isEmpty { Section { Text(message) } }
    }.navigationTitle("資料備份").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            pending = nil; preview = nil; message = ""
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let bytes = try DataChecks.readFile(url); preview = try BackupImport.decode(bytes); pending = bytes } catch { message = error.localizedDescription }
        }.confirmationDialog("合併這份備份？", isPresented: $confirmation, titleVisibility: .visible) { Button("合併匯入") { do { if let pending { try store.importBackup(pending); message = "匯入完成，匯入前資料已保存於復原副本。"; preview = nil; self.pending = nil } } catch { message = error.localizedDescription } }; Button("取消", role: .cancel) { } }
    }
}
