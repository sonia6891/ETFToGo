import SwiftUI
import Charts

enum HoldingSort: String, CaseIterable, Identifiable {
    case value = "市值大小", cost = "成本大小", profit = "損益", symbol = "代號"
    var id: String { rawValue }
}
struct HoldingsView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var section = 0
    @State private var add = false
    @State private var editing: Holding?
    @State private var sort = HoldingSort.value
    @State private var searching = false
    @State private var query = ""
    @AppStorage("hideAmounts") private var hidden = false
    private var brokers: [String] { Array(Set(store.data.holdings.map(\.broker))).sorted() }
    private var holdings: [Holding] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let items = store.data.holdings.filter { text.isEmpty || $0.symbol.localizedCaseInsensitiveContains(text) || $0.name.localizedCaseInsensitiveContains(text) || $0.broker.localizedCaseInsensitiveContains(text) }
        switch sort {
        case .value: return items.sorted { (value(of: $0) ?? -1) > (value(of: $1) ?? -1) }
        case .cost: return items.sorted { $0.cost > $1.cost }
        case .profit: return items.sorted { (profit(of: $0) ?? -Double.infinity) > (profit(of: $1) ?? -Double.infinity) }
        case .symbol: return items.sorted { $0.symbol < $1.symbol }
        }
    }
    var body: some View {
        Page {
            SegmentBar(items: ["持有部位", "券商帳戶", "資產配置"], selection: $section)
            if searching {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("搜尋代號、名稱或券商", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never)
                }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            switch section {
            case 1: accounts
            case 2: AllocationContent()
            default: positions
            }
            Text("股數以「股」為單位，成本統一填台幣（可包含實際手續費）。未確認幣別或外幣報價不直接加總為台幣市值。").font(.caption).foregroundStyle(Palette.muted)
        }
        .safeAreaInset(edge: .bottom) {
            Button { add = true } label: { PrimaryButtonLabel(title: "新增持有") }
                .buttonStyle(.plain).accessibilityIdentifier("add-holding")
                .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .navigationTitle("我的持有").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { searching.toggle(); if !searching { query = "" } } label: { Image(systemName: searching ? "xmark" : "magnifyingglass") }.accessibilityLabel(searching ? "關閉搜尋" : "搜尋持有")
            }
        }
        .sheet(isPresented: $add) { HoldingEditor() }
        .sheet(item: $editing) { HoldingEditor(existing: $0) }
    }
    private func value(of holding: Holding) -> Double? {
        guard let quote = store.data.quotes[holding.symbol], quote.isTWD else { return nil }
        return quote.price * holding.shares
    }
    private func profit(of holding: Holding) -> Double? { value(of: holding).map { $0 - holding.cost } }
    @ViewBuilder private var positions: some View {
        hero
        if store.data.holdings.isEmpty {
            Card { ContentUnavailableView("把你的 ETF 放進口袋", systemImage: "bag", description: Text("選擇 ETF，填入股數與成本，之後就能持續追蹤。")) }
        } else {
            HStack {
                Text("持有明細 (\(holdings.count))").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Menu {
                    Picker("排序", selection: $sort) { ForEach(HoldingSort.allCases) { Text($0.rawValue).tag($0) } }
                } label: { HStack(spacing: 3) { Text(sort.rawValue); Image(systemName: "chevron.down") }.font(.caption.weight(.semibold)) }
            }
            Card(padding: 14) {
                ForEach(holdings) { holding in
                    row(holding)
                    if holding.id != holdings.last?.id { Divider() }
                }
            }
            let allocation = AllocationMath.byStrategy(store.data)
            if !allocation.slices.isEmpty {
                Card {
                    HStack { Text("資產配置").font(.headline).foregroundStyle(Palette.ink); Text("（\(allocation.basis)）").font(.caption).foregroundStyle(Palette.muted) }.padding(.bottom, 12)
                    AllocationDonut(slices: allocation.slices)
                }
            }
        }
    }
    private var hero: some View {
        let summary = PortfolioSummary(store.data)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("持有市值").font(.subheadline.weight(.semibold)); Text("(TWD)").font(.caption).opacity(0.8)
                Spacer()
                Button { hidden.toggle() } label: { Image(systemName: hidden ? "eye.slash" : "eye") }.accessibilityLabel(hidden ? "顯示金額" : "隱藏金額")
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(shown(summary.marketValue.map(money) ?? "—", hidden: hidden)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                if let unrealized = summary.unrealized, let percent = summary.unrealizedPercent {
                    Text(shown("\(unrealized >= 0 ? "▲" : "▼") \(signed(unrealized)) (\(percentText(percent)))", hidden: hidden)).font(.caption.bold()).monospacedDigit()
                }
            }
            HStack(spacing: 0) {
                heroCell("成本總額", shown(money(summary.cost), hidden: hidden), tint: Palette.ink)
                Divider().frame(height: 34)
                heroCell("未實現損益", summary.unrealized.map { shown("\(signed($0))", hidden: hidden) } ?? "尚缺報價", tint: summary.unrealized.map(Palette.trend) ?? Palette.muted)
            }
            .padding(.vertical, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(18)
        .foregroundStyle(.white)
        .background(Palette.hero, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Palette.blue.opacity(0.25), radius: 12, y: 5)
    }
    private func heroCell(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(tint).minimumScaleFactor(0.6).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
    }
    private func row(_ holding: Holding) -> some View {
        let marketValue = value(of: holding)
        let gain = profit(of: holding)
        return Button { editing = holding } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(holding.symbol).font(.headline).foregroundStyle(Palette.ink)
                    Text(holding.name).font(.subheadline).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(marketValue.map { shown(money($0), hidden: hidden) } ?? "尚無報價").font(.headline).monospacedDigit().foregroundStyle(marketValue == nil ? Palette.muted : Palette.ink)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(decimal(holding.shares)) 股 | 成本 \(priceText(holding.unitCost))").font(.caption).foregroundStyle(Palette.muted)
                    Text(holding.broker).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1)
                    Spacer(minLength: 6)
                    if let gain, holding.cost > 0 {
                        Text(shown("\(gain >= 0 ? "▲" : "▼") \(signed(gain)) (\(percentText(gain / holding.cost * 100)))", hidden: hidden)).font(.caption.bold()).monospacedDigit().foregroundStyle(Palette.trend(gain))
                    }
                }
            }.padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var accounts: some View {
        if brokers.isEmpty {
            Card { ContentUnavailableView("還沒有券商帳戶", systemImage: "building.columns", description: Text("新增持有時填入券商，或匯入券商庫存 CSV。")) }
        }
        ForEach(brokers, id: \.self) { broker in
            let items = holdings.filter { $0.broker == broker }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(broker, systemImage: "building.columns").font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(items.count) 筆 · 成本 \(shown(money(items.reduce(0) { $0 + $1.cost }), hidden: hidden))").font(.caption).foregroundStyle(Palette.muted)
                }
                Card(padding: 14) {
                    ForEach(items) { holding in
                        row(holding)
                        if holding.id != items.last?.id { Divider() }
                    }
                }
            }
        }
        NavigationLink { BrokerView() } label: { Card(padding: 12) { ToolRow(title: "匯入券商庫存", subtitle: "所有券商 CSV 欄位對應與預覽", icon: "square.and.arrow.down") } }.buttonStyle(.plain)
    }
}
struct AllocationSlice: Identifiable {
    let strategy: Strategy
    let amount: Double
    var id: String { strategy.rawValue }
}
enum AllocationMath {
    static func byStrategy(_ data: Portfolio) -> (slices: [AllocationSlice], basis: String) {
        let useValue = data.marketValue != nil
        var totals: [Strategy: Double] = [:]
        for holding in data.holdings {
            let amount = useValue ? (data.quotes[holding.symbol].map { $0.price * holding.shares } ?? holding.cost) : holding.cost
            totals[holding.strategy, default: 0] += amount
        }
        let slices = Strategy.allCases.compactMap { strategy -> AllocationSlice? in
            guard let amount = totals[strategy], amount > 0 else { return nil }
            return AllocationSlice(strategy: strategy, amount: amount)
        }
        return (slices, useValue ? "依持有市值" : "依投入成本")
    }
}
struct AllocationDonut: View {
    let slices: [AllocationSlice]
    var body: some View {
        let total = max(slices.reduce(0.0) { $0 + $1.amount }, 1)
        HStack(spacing: 20) {
            Chart(slices) { slice in
                SectorMark(angle: .value("金額", slice.amount), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(Palette.strategy(slice.strategy))
                    .cornerRadius(3)
            }
            .chartLegend(.hidden)
            .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        Circle().fill(Palette.strategy(slice.strategy)).frame(width: 9, height: 9)
                        Text(slice.strategy.rawValue).font(.subheadline).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(decimal(slice.amount / total * 100))%").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                    }
                }
            }
        }
    }
}
struct AllocationContent: View {
    @EnvironmentObject var store: PortfolioStore
    var body: some View {
        let allocation = AllocationMath.byStrategy(store.data)
        let symbols = Array(Set(store.data.holdings.map(\.symbol))).sorted()
        let cost = max(store.data.cost, 1)
        VStack(alignment: .leading, spacing: 16) {
            Card {
                HStack { Text("依策略").font(.headline).foregroundStyle(Palette.ink); Text("（\(allocation.basis)）").font(.caption).foregroundStyle(Palette.muted) }.padding(.bottom, 12)
                if allocation.slices.isEmpty { Text("還沒有持有紀錄。").foregroundStyle(Palette.muted) } else { AllocationDonut(slices: allocation.slices) }
            }
            if !symbols.isEmpty {
                SectionHeading(title: "依 ETF 分配", subtitle: "依投入成本計算")
                Card(padding: 14) {
                    ForEach(symbols, id: \.self) { symbol in
                        let holdings = store.data.holdings.filter { $0.symbol == symbol }
                        let amount = holdings.reduce(0.0) { $0 + $1.cost }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(symbol).font(.subheadline.bold()); Text(holdings.first?.name ?? symbol).font(.subheadline).lineLimit(1); Spacer(); Text("\(decimal(amount / cost * 100))%").font(.subheadline.bold()).foregroundStyle(Palette.blue) }.foregroundStyle(Palette.ink)
                            ProgressView(value: min(amount, cost), total: cost).tint(Palette.blue)
                            Text("成本 $\(money(amount))").font(.caption).foregroundStyle(Palette.muted)
                        }.padding(.vertical, 8)
                    }
                }
            }
            NavigationLink { ExposureView() } label: { Card(padding: 12) { ToolRow(title: "持股透視", subtitle: "合併 ETF 背後的股票曝險", icon: "square.stack.3d.up") } }.buttonStyle(.plain)
        }
    }
}
struct HoldingEditor: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) var dismiss
    var existing: Holding?
    var fund: Fund?
    @State private var symbol = ""
    @State private var selectedFund = ""
    @State private var name = ""
    @State private var shares = ""
    @State private var cost = ""
    @State private var broker = ""
    @State private var strategy = Strategy.unclassified
    @State private var error: String?
    @State private var deletePrompt = false
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("1  選擇 ETF").font(.headline).foregroundStyle(Palette.blue)
                    if existing == nil { Picker("快速選擇", selection: $selectedFund) { Text("手動輸入").tag(""); ForEach(store.funds) { Text("\($0.id) \($0.name)").tag($0.id) } }.onChange(of: selectedFund) { _, value in if let item = store.funds.first(where: { $0.id == value }) { symbol = item.id; name = item.name; strategy = item.strategy } } }
                    TextField("ETF 代碼", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("holding-symbol")
                    TextField("ETF 名稱", text: $name).accessibilityIdentifier("holding-name")
                }
                Section { Text("2  填入持有資料").font(.headline).foregroundStyle(Palette.blue)
                    TextField("持有股數（股）", text: $shares).keyboardType(.decimalPad).accessibilityIdentifier("holding-shares")
                    TextField("每股買入成本（元）", text: $cost).keyboardType(.decimalPad).accessibilityIdentifier("holding-cost")
                    TextField("券商名稱", text: $broker).accessibilityIdentifier("holding-broker")
                    Picker("策略分類", selection: $strategy) { ForEach(Strategy.allCases) { Text("\($0.emoji) \($0.rawValue)").tag($0) } }
                } footer: { Text("輸入 1,000 股代表 1 張。策略可以日後調整，不影響持有數量。") }
                if let s = Double(shares), let c = Double(cost), s > 0, c > 0 { Section { LabeledContent("這筆投入成本", value: "$\(money(s * c))") } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if existing != nil { Section { Button("刪除這筆持有", role: .destructive) { deletePrompt = true } } }
            }.navigationTitle(existing == nil ? "新增持有" : "編輯持有").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("儲存") { save() }.fontWeight(.bold).accessibilityIdentifier("save-holding") } }
                .onAppear { if let h = existing { symbol = h.symbol; name = h.name; shares = String(h.shares); cost = String(h.unitCost); broker = h.broker; strategy = h.strategy } else if let fund { symbol = fund.id; selectedFund = fund.id; name = fund.name; strategy = fund.strategy } }
                .confirmationDialog("刪除這筆持有？配息紀錄會保留。", isPresented: $deletePrompt, titleVisibility: .visible) { Button("確認刪除", role: .destructive) { do { if let existing { try store.remove(existing) }; dismiss() } catch { self.error = error.localizedDescription } } }
        }
    }
    func save() {
        let h = Holding(id: existing?.id ?? UUID(), symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), shares: Double(shares.replacingOccurrences(of: ",", with: "")) ?? 0, unitCost: Double(cost.replacingOccurrences(of: ",", with: "")) ?? 0, broker: broker.trimmingCharacters(in: .whitespacesAndNewlines), strategy: strategy, sourceAccount: existing?.sourceAccount)
        do { try store.save(h); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct DividendsView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var section = 0
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var selectedDay: Date?
    @State private var add = false
    @State private var deleting: Dividend?
    private var monthEntries: [Dividend] { store.data.dividends.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }.sorted { $0.date < $1.date } }
    private var listed: [Dividend] {
        guard let selectedDay else { return monthEntries }
        return monthEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
    }
    var body: some View {
        Page {
            SegmentBar(items: ["月曆", "近期公告", "歷史紀錄"], selection: $section, pill: true)
            switch section {
            case 1: upcoming
            case 2: history
            default: calendar
            }
            Text("此頁為你的配息紀錄，非交易所自動公告。長按紀錄可標記入帳或刪除。").font(.caption).foregroundStyle(Palette.muted)
        }
        .safeAreaInset(edge: .bottom) {
            Button { add = true } label: { PrimaryButtonLabel(title: "新增配息紀錄") }.buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .navigationTitle("配息月曆").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $add) { DividendEditor(date: selectedDay ?? Date()) }
        .confirmationDialog("刪除這筆配息紀錄？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("確認刪除", role: .destructive) { do { if let deleting { try store.removeDividend(deleting) } } catch { store.message = error.localizedDescription }; deleting = nil }
        }
    }
    @ViewBuilder private var calendar: some View {
        let paid = monthEntries.filter { $0.status == .paid }.reduce(0.0) { $0 + $1.amount }
        let pending = monthEntries.filter { $0.status != .paid }.reduce(0.0) { $0 + $1.amount }
        HStack(spacing: 10) {
            StatTile(title: "本月已領", value: "$\(money(paid))", icon: "dollarsign.circle.fill", tint: Palette.blue)
            StatTile(title: "待入帳", value: "$\(money(pending))", icon: "clock.fill", tint: Palette.orange)
        }
        Card(padding: 14) {
            HStack {
                Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_Hant_TW")))).font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Button { change(-1) } label: { Image(systemName: "chevron.left").padding(8) }.accessibilityLabel("上一個月")
                Button { change(1) } label: { Image(systemName: "chevron.right").padding(8) }.accessibilityLabel("下一個月")
            }
            MonthCalendar(month: month, dividends: monthEntries, selected: $selectedDay).padding(.top, 6)
            HStack(spacing: 14) {
                ForEach(DividendStatus.allCases, id: \.self) { status in
                    HStack(spacing: 4) { Circle().fill(Palette.status(status)).frame(width: 8, height: 8); Text(status.rawValue).font(.caption2).foregroundStyle(Palette.muted) }
                }
            }.padding(.top, 10)
        }
        HStack {
            SectionHeading(title: selectedDay.map { "\(monthDay($0)) 配息紀錄" } ?? "\(Calendar.current.component(.month, from: month)) 月配息紀錄")
            if selectedDay != nil { Button("顯示全月") { selectedDay = nil }.font(.caption) }
        }
        if listed.isEmpty {
            Card { ContentUnavailableView(selectedDay == nil ? "這個月還沒有紀錄" : "這天沒有紀錄", systemImage: "calendar.badge.plus", description: Text("記下每筆股息，慢慢看見累積。")) }
        } else {
            VStack(spacing: 10) { ForEach(listed) { row($0) } }
        }
    }
    @ViewBuilder private var upcoming: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let items = store.data.dividends.filter { $0.status != .paid && $0.date >= today }.sorted { $0.date < $1.date }
        SectionHeading(title: "即將入帳", subtitle: "已公告與預估的配息，依預計入帳日排序")
        if items.isEmpty {
            Card { ContentUnavailableView("目前沒有待入帳配息", systemImage: "clock", description: Text("新增狀態為「已公告」或「預估」的配息紀錄。")) }
        } else {
            VStack(spacing: 10) { ForEach(items) { row($0) } }
        }
    }
    @ViewBuilder private var history: some View {
        let paid = store.data.dividends.filter { $0.status == .paid }
        let years = Dictionary(grouping: paid) { Calendar.current.component(.year, from: $0.date) }
        if paid.isEmpty {
            Card { ContentUnavailableView("尚無已入帳紀錄", systemImage: "tray", description: Text("入帳後的配息會依年度整理在這裡。")) }
        }
        ForEach(years.keys.sorted(by: >), id: \.self) { year in
            let items = (years[year] ?? []).sorted { $0.date > $1.date }
            HStack {
                SectionHeading(title: "\(String(year)) 年")
                Text("合計 $\(money(items.reduce(0.0) { $0 + $1.amount }))").font(.subheadline.bold()).foregroundStyle(Palette.green)
            }
            VStack(spacing: 10) { ForEach(items) { row($0) } }
        }
    }
    private func row(_ item: Dividend) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.symbol).font(.subheadline.bold())
                    Text(store.name(for: item.symbol)).font(.subheadline).lineLimit(1)
                }.foregroundStyle(Palette.ink)
                Text("金額 $\(money(item.amount))｜\(item.status == .paid ? "已於" : "預計") \(monthDay(item.date)) 入帳").font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 6)
            StatusPill(status: item.status)
        }
        .padding(.vertical, 12).padding(.leading, 16).padding(.trailing, 12)
        .background(alignment: .leading) { Palette.status(item.status).frame(width: 4) }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Palette.blue.opacity(0.05), radius: 6, y: 2)
        .contextMenu {
            if item.status != .paid { Button("標記為已入帳", systemImage: "checkmark.circle") { do { try store.markPaid(item) } catch { store.message = error.localizedDescription } } }
            Button("刪除紀錄", systemImage: "trash", role: .destructive) { deleting = item }
        }
    }
    func change(_ amount: Int) { month = Calendar.current.date(byAdding: .month, value: amount, to: month)!; selectedDay = nil }
}
struct MonthCalendar: View {
    let month: Date
    let dividends: [Dividend]
    @Binding var selected: Date?
    private let calendar = Calendar.current
    var body: some View {
        let days = gridDays()
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { Text($0).font(.caption2.bold()).foregroundStyle(Palette.muted).frame(maxWidth: .infinity) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] { cell(day) } else { Color.clear.frame(height: 42) }
                }
            }
        }
    }
    private func gridDays() -> [Date?] {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        var result: [Date?] = Array(repeating: nil, count: calendar.component(.weekday, from: first) - 1)
        for day in range { result.append(calendar.date(byAdding: .day, value: day - 1, to: first)) }
        return result
    }
    private func cell(_ day: Date) -> some View {
        let items = dividends.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let statuses = DividendStatus.allCases.filter { status in items.contains { $0.status == status } }
        let today = calendar.isDateInToday(day)
        let picked = selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        return Button { selected = picked ? nil : day } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(today || picked ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(today ? Color.white : Palette.ink)
                    .frame(width: 30, height: 30)
                    .background { if today { Circle().fill(Palette.blue) } else if picked { Circle().stroke(Palette.blue, lineWidth: 1.5) } }
                HStack(spacing: 2) { ForEach(statuses, id: \.self) { Circle().fill(Palette.status($0)).frame(width: 5, height: 5) } }.frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(calendar.component(.month, from: day)) 月 \(calendar.component(.day, from: day)) 日\(items.isEmpty ? "" : "，\(items.count) 筆配息")")
    }
}
struct DividendEditor: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.dismiss) var dismiss
    @State private var symbol: String
    @State private var amount = ""
    @State private var date: Date
    @State private var status = DividendStatus.paid
    @State private var error: String?
    init(symbol: String = "", date: Date = Date()) {
        _symbol = State(initialValue: symbol)
        _date = State(initialValue: date)
    }
    var body: some View { NavigationStack { Form {
        Section("配息資料") { TextField("ETF 代碼", text: $symbol).textInputAutocapitalization(.characters); TextField("總金額（元）", text: $amount).keyboardType(.decimalPad); DatePicker("入帳／預計日期", selection: $date, displayedComponents: .date); Picker("狀態", selection: $status) { ForEach(DividendStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }
        Section { Text("請輸入這次收到的總金額，不是每股配息。公告與預估不會計入已入帳股息。").font(.footnote).foregroundStyle(.secondary) }
        if let error { Text(error).foregroundStyle(.red) }
    }.navigationTitle("記錄配息").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("儲存") { guard !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let value = Double(amount), value.isFinite, value > 0 else { error = "請輸入代碼與大於 0 的配息總額。"; return }; do { try store.record(Dividend(symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), date: date, amount: value, status: status)); dismiss() } catch { self.error = error.localizedDescription } } } } } }
}
