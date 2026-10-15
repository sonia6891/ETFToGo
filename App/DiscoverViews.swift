import SwiftUI

enum FilterChip: Hashable, Identifiable {
    case strategy(Strategy), management(String), market(String), asset(String)
    var id: FilterChip { self }
    var label: String {
        switch self {
        case .strategy(let value): return value.rawValue
        case .management(let value), .market(let value), .asset(let value): return value
        }
    }
}
struct FundFilter: Equatable {
    var strategies: Set<Strategy> = []
    var management: String? = nil
    var markets: Set<String> = []
    var assets: Set<String> = []
    var isEmpty: Bool { strategies.isEmpty && management == nil && markets.isEmpty && assets.isEmpty }
    func matches(_ fund: Fund) -> Bool {
        if !strategies.isEmpty && !strategies.contains(fund.strategy) { return false }
        if let management, management != fund.managementStyle { return false }
        if !markets.isEmpty && !markets.contains(fund.marketName) { return false }
        if !assets.isEmpty && !assets.contains(fund.assetClass) { return false }
        return true
    }
    var chips: [FilterChip] {
        var result: [FilterChip] = Strategy.allCases.filter { strategies.contains($0) }.map { FilterChip.strategy($0) }
        if let management { result.append(.management(management)) }
        result += markets.sorted().map { FilterChip.market($0) }
        result += assets.sorted().map { FilterChip.asset($0) }
        return result
    }
    mutating func remove(_ chip: FilterChip) {
        switch chip {
        case .strategy(let value): strategies.remove(value)
        case .management: management = nil
        case .market(let value): markets.remove(value)
        case .asset(let value): assets.remove(value)
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var query = ""
    @State private var scope = 0
    @State private var filter = FundFilter()
    @State private var showFilter = false
    @FocusState private var searchFocused: Bool
    private var funds: [Fund] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return store.funds.filter { fund in
            guard filter.matches(fund) else { return false }
            if scope == 1 && !store.data.favorites.contains(fund.id) { return false }
            return text.isEmpty || fund.id.localizedCaseInsensitiveContains(text) || fund.name.localizedCaseInsensitiveContains(text)
        }
    }
    var body: some View {
        Page {
            searchField
            categories
            HStack(alignment: .bottom) {
                SegmentBar(items: ["全部 ETF", "我的自選"], selection: $scope).frame(maxWidth: 220)
                Spacer()
                Button { showFilter = true } label: {
                    Label(filter.isEmpty ? "篩選" : "篩選 \(filter.chips.count)", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(Palette.blue).background(Palette.blue.opacity(0.08), in: Capsule())
                }.buttonStyle(.plain)
            }
            if !filter.isEmpty { chipRow }
            list
            footer
        }
        .navigationTitle("探索 ETF").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Fund.self) { FundDetail(fund: $0) }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成搜尋") { searchFocused = false } } }
        .sheet(isPresented: $showFilter) { FilterSheet(filter: $filter, funds: store.funds) }
    }
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
            TextField("搜尋代號或名稱（例：0050）", text: $query)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                .accessibilityIdentifier("fund-search")
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }.accessibilityLabel("清除搜尋") }
        }
        .padding(13)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Palette.blue.opacity(0.05), radius: 8, y: 2)
    }
    private var categories: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("系統自動分類").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Text("依名稱規則整理，點選即可篩選").font(.caption2).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 10) { ForEach([Strategy.saving, .income, .risk]) { categoryCard($0) } }
        }
    }
    private func categoryCard(_ strategy: Strategy) -> some View {
        let selected = filter.strategies == [strategy]
        let count = store.funds.filter { $0.strategy == strategy }.count
        let color = Palette.strategy(strategy)
        return Button { filter.strategies = selected ? [] : [strategy] } label: {
            VStack(spacing: 4) {
                StrategyArt(strategy: strategy, size: 64)
                Text(strategy.rawValue).font(.headline).foregroundStyle(Palette.ink).padding(.top, 2)
                Text(strategy.tagline).font(.caption).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(LinearGradient(colors: [color.opacity(selected ? 0.22 : 0.13), color.opacity(selected ? 0.12 : 0.04)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(strategy.rawValue)，\(strategy.tagline)，\(count) 檔")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filter.chips) { chip in
                    Button { filter.remove(chip) } label: {
                        HStack(spacing: 4) { Text(chip.label); Image(systemName: "xmark").font(.caption2.bold()) }
                            .font(.caption.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 7)
                            .foregroundStyle(Palette.blue).background(Palette.blue.opacity(0.1), in: Capsule())
                    }.buttonStyle(.plain).accessibilityLabel("移除篩選 \(chip.label)")
                }
            }
        }
    }
    private var list: some View {
        let items = funds
        return Card(padding: 6) {
            if items.isEmpty {
                if scope == 1 && store.data.favorites.isEmpty {
                    ContentUnavailableView("還沒有自選 ETF", systemImage: "star", description: Text("點清單右側的星號，即可加入自選。"))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
            LazyVStack(spacing: 0) {
                ForEach(items) { fund in
                    HStack(spacing: 6) {
                        NavigationLink(value: fund) { FundRow(fund: fund) }.buttonStyle(.plain)
                        favoriteButton(fund.id)
                    }.padding(.horizontal, 10)
                    if fund.id != items.last?.id { Divider().padding(.leading, 10) }
                }
            }
        }
    }
    private func favoriteButton(_ symbol: String) -> some View {
        let on = store.data.favorites.contains(symbol)
        return Button { store.favorite(symbol) } label: {
            Image(systemName: on ? "star.fill" : "star").font(.body).foregroundStyle(on ? Palette.orange : Palette.muted.opacity(0.5)).frame(width: 32, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(on ? "取消自選 \(symbol)" : "加入自選 \(symbol)")
    }
    @ViewBuilder private var footer: some View {
        Text(store.isDemo ? "示範清單；正式模式使用上市與上櫃名單。" : "上市 \(store.funds.filter { $0.market == "TWSE" }.count) · 上櫃 \(store.funds.filter { $0.market == "TPEx" }.count) 個代碼。外幣級別分開計數，代碼數不等於獨立基金數。").font(.caption).foregroundStyle(Palette.muted)
        if let catalog = store.catalog, !store.isDemo { Text("上市資料日 \(catalog.listedDate) · 上櫃取得日 \(catalog.fetchedDay)").font(.caption).foregroundStyle(Palette.muted) }
        if let message = store.catalogMessage { Text(message).font(.caption).foregroundStyle(Palette.muted) }
        Button(store.catalogRefreshing ? "更新中…" : "更新上市櫃名單") { Task { await store.refreshCatalog() } }.font(.subheadline).disabled(store.catalogRefreshing || store.isDemo)
    }
}
struct FundRow: View {
    @EnvironmentObject var store: PortfolioStore
    let fund: Fund
    var body: some View {
        let quote = store.data.quotes[fund.id]
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fund.id).font(.headline).foregroundStyle(Palette.ink)
                Text(fund.name).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(quote.map { priceText($0.price) } ?? "—").font(.headline).monospacedDigit().foregroundStyle(Palette.ink)
                QuoteChange(quote: quote, font: .caption2)
            }
            StrategyPill(strategy: fund.strategy).frame(width: 56)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
struct FilterSheet: View {
    @Binding var filter: FundFilter
    let funds: [Fund]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    group("管理方式", options: ["被動式", "主動式"], selected: Set([filter.management].compactMap { $0 }), count: { value in funds.filter { $0.managementStyle == value }.count }) { value in
                        filter.management = filter.management == value ? nil : value
                    }
                    group("策略", options: Strategy.allCases.map(\.rawValue), selected: Set(filter.strategies.map(\.rawValue)), count: { value in funds.filter { $0.strategy.rawValue == value }.count }) { value in
                        guard let strategy = Strategy(rawValue: value) else { return }
                        if filter.strategies.contains(strategy) { filter.strategies.remove(strategy) } else { filter.strategies.insert(strategy) }
                    }
                    group("市場", options: ["上市", "上櫃"], selected: filter.markets, count: { value in funds.filter { $0.marketName == value }.count }) { value in
                        if filter.markets.contains(value) { filter.markets.remove(value) } else { filter.markets.insert(value) }
                    }
                    group("資產類型", options: Fund.assetClasses, selected: filter.assets, count: { value in funds.filter { $0.assetClass == value }.count }) { value in
                        if filter.assets.contains(value) { filter.assets.remove(value) } else { filter.assets.insert(value) }
                    }
                    Text("管理方式與資產類型依官方名單的基金類型及名稱整理；配息頻率與產業尚無可靠資料來源，暫不提供篩選。").font(.caption).foregroundStyle(Palette.muted)
                }.padding(20)
            }
            .background { Palette.page.ignoresSafeArea() }
            .navigationTitle("篩選 ETF").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("清除") { filter = FundFilter() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.fontWeight(.bold) }
            }
        }
        .presentationDetents([.medium, .large])
    }
    private func group(_ title: String, options: [String], selected: Set<String>, count: @escaping (String) -> Int, toggle: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold()).foregroundStyle(Palette.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let on = selected.contains(option)
                    Button { toggle(option) } label: {
                        VStack(spacing: 2) {
                            Text(option).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            Text("\(count(option)) 檔").font(.caption2).opacity(0.8)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(on ? .white : Palette.ink)
                        .background(on ? Palette.blue : Color.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

struct FundDetail: View {
    @EnvironmentObject var store: PortfolioStore
    let fund: Fund
    @State private var section = 0
    @State private var add = false
    @State private var range = ChartRange.quarter
    @State private var busy = false
    @State private var error: String?
    @State private var basis = false
    private var quote: Quote? { store.data.quotes[fund.id] }
    private var stats: PerformanceStats? {
        guard let history = store.data.histories?[fund.id] else { return nil }
        return try? PerformanceStats(history)
    }
    var body: some View {
        Page {
            SegmentBar(items: ["總覽", "走勢", "持股", "配息", "資訊"], selection: $section)
            switch section {
            case 1: HistoryContent(symbol: fund.id)
            case 2: ComponentsContent(symbol: fund.id)
            case 3: FundDividends(symbol: fund.id)
            case 4: FundInfo(fund: fund)
            default: overview
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .navigationTitle(fund.id).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(fund.id)  \(fund.name)").font(.headline).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { store.favorite(fund.id) } label: {
                    Image(systemName: store.data.favorites.contains(fund.id) ? "star.fill" : "star").foregroundStyle(Palette.orange)
                }.accessibilityLabel("切換收藏")
                ShareLink(item: "\(fund.id) \(fund.name)｜ETF 袋著走") { Image(systemName: "square.and.arrow.up") }
            }
        }
        .sheet(isPresented: $add) { HoldingEditor(fund: fund) }
        .alert("分類依據", isPresented: $basis) { Button("知道了", role: .cancel) {} } message: { Text(Strategy.basis) }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            priceBlock
            chartCard
            classification
            quoteStats
            Button { add = true } label: { Label("新增到我的持有", systemImage: "plus").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12) }
                .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 14))
            Text("策略分類是整理持有的方式，不是收益保證。配息可能來自收益或本金；槓桿策略需注意每日重設及波動風險。").font(.caption).foregroundStyle(Palette.muted)
        }
    }
    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(quote.map { priceText($0.price) } ?? "—").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink)
                QuoteChange(quote: quote, font: .subheadline)
                Spacer(minLength: 0)
                Text(fund.market == nil ? "示範" : "台灣\(fund.marketName)").font(.caption2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(Palette.blue, in: Capsule())
            }
            Text(updatedText).font(.caption).foregroundStyle(Palette.muted)
            Button(store.refreshing ? "更新中…" : "更新這檔報價") { Task { await store.refresh(symbols: [fund.id]) } }
                .font(.caption.bold()).disabled(store.refreshing)
        }
    }
    private var updatedText: String {
        guard let quote else { return "尚未取得報價，連接富果行情後即可更新。" }
        if store.isDemo { return "示範報價，非即時市場資訊" }
        return "報價日期 \(quote.date) · 取得於 \(quote.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
    }
    private var chartCard: some View {
        let points = store.data.histories?[fund.id].map(TrendMath.points) ?? []
        let visible = TrendMath.slice(points, range)
        return Card(padding: 14) {
            if visible.count >= 2 {
                RangeChips(options: [.week, .month, .quarter, .year, .fiveYears], selection: $range).padding(.bottom, 10)
                ValueChart(points: visible, showAxes: true, height: 170)
                Text("還原日收盤價 · 資料至 \(store.data.histories?[fund.id]?.points.last?.date ?? "")").font(.caption2).foregroundStyle(Palette.muted).padding(.top, 8)
            } else {
                Label("尚無歷史走勢", systemImage: "chart.xyaxis.line").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                Text("使用你的富果金鑰取得近 5 年還原日收盤價，約需 10 秒；不以試算資料代替。").font(.caption).foregroundStyle(Palette.muted).padding(.vertical, 6)
                Button(busy ? "取得中…" : "取得歷史走勢") { Task { await loadHistory() } }
                    .buttonStyle(.borderedProminent).disabled(busy || store.isDemo)
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red).padding(.top, 6) }
            }
        }
    }
    private func loadHistory() async {
        busy = true; error = nil
        defer { busy = false }
        do { try store.saveHistory(await Fugle.history(symbol: fund.id, years: 5)) } catch { self.error = error.localizedDescription }
    }
    private var classification: some View {
        let strategy = fund.strategy
        let color = Palette.strategy(strategy)
        return Card {
            HStack(alignment: .top, spacing: 12) {
                StrategyArt(strategy: strategy, size: 54).frame(width: 64, height: 64).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 0) {
                        Text("系統分類：").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                        Text(strategy.rawValue).font(.subheadline.bold()).foregroundStyle(color)
                        Spacer(minLength: 4)
                        Button("為什麼這樣分類？") { basis = true }.font(.caption2)
                    }
                    HStack {
                        Text("\(strategy.tagline)・\(fund.managementStyle)").font(.caption).foregroundStyle(Palette.muted)
                        Spacer(minLength: 4)
                        Text("風險：\(fund.riskLevel)").font(.caption2.bold()).foregroundStyle(Palette.orange)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Palette.orange.opacity(0.12), in: Capsule())
                    }
                }
            }
            Text(explanation).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.85)).padding(.top, 12)
            Button { basis = true } label: { HStack(spacing: 2) { Text("查看分類依據"); Image(systemName: "chevron.right") }.font(.caption.bold()) }.padding(.top, 8)
        }
    }
    private var explanation: String {
        var text = fund.strategy.explanation
        if fund.strategy != .unclassified { text += fund.riskSentence }
        if let volatility = stats?.volatility { text += "近期年化波動 \(decimal(volatility * 100))%。" }
        return text
    }
    private var quoteStats: some View {
        Card {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow { stat("開盤", quote?.open.map(priceText)); stat("最高", quote?.high.map(priceText)) }
                GridRow { stat("最低", quote?.low.map(priceText)); stat("成交量", quote?.volume.map { "\(money($0)) 張" }) }
            }
            if quote != nil && quote?.open == nil { Text("重新更新報價後顯示開盤、最高、最低與成交量。").font(.caption2).foregroundStyle(Palette.muted).padding(.top, 10) }
        }
    }
    private func stat(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Palette.muted)
            Spacer(minLength: 4)
            Text(value ?? "—").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink)
        }.frame(maxWidth: .infinity)
    }
    private var actionBar: some View {
        let favorite = store.data.favorites.contains(fund.id)
        let compared = (store.data.comparison ?? []).contains(fund.id)
        return HStack(spacing: 12) {
            Button { store.favorite(fund.id) } label: {
                Text(favorite ? "已加入自選" : "加入自選").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(Palette.blue)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.blue, lineWidth: 1.2))
            }
            Button { store.addToComparison(fund.id) } label: {
                Text(compared ? "已在比較清單" : "加入比較").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(Palette.hero, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
struct FundDividends: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    @State private var add = false
    private var items: [Dividend] { store.data.dividends.filter { $0.symbol == symbol }.sorted { $0.date > $1.date } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                Text("你記錄的 \(symbol) 配息").font(.subheadline).foregroundStyle(Palette.muted)
                Text("$\(money(items.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }))").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink).padding(.vertical, 6)
                Text("累計已入帳 · 共 \(items.count) 筆紀錄").font(.caption).foregroundStyle(Palette.muted)
            }
            Button { add = true } label: { PrimaryButtonLabel(title: "記錄這檔配息") }.buttonStyle(.plain)
            if items.isEmpty {
                Card { ContentUnavailableView("尚無配息紀錄", systemImage: "calendar.badge.plus", description: Text("配息由你記錄，不是交易所自動公告。")) }
            } else {
                Card(padding: 12) {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.bold()).foregroundStyle(Palette.ink)
                                Text("$\(money(item.amount))").font(.caption).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            StatusPill(status: item.status)
                        }.padding(.vertical, 8)
                    }
                }
            }
        }
        .sheet(isPresented: $add) { DividendEditor(symbol: symbol) }
    }
}
struct FundInfo: View {
    let fund: Fund
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                Text("基本資料").font(.headline).foregroundStyle(Palette.ink).padding(.bottom, 6)
                row("代號", fund.id); row("名稱", fund.name)
                if let full = fund.fullName { row("基金全名", full) }
                if let type = fund.fundType { row("基金類型", type) }
                row("管理方式", fund.managementStyle); row("資產類型", fund.assetClass)
                row("市場", fund.marketName)
                if let listing = fund.listingDate { row("掛牌日期", listing) }
            }
            FeesContent(fund: fund)
        }
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.subheadline).foregroundStyle(Palette.muted)
            Spacer(minLength: 12)
            Text(value).font(.subheadline).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing)
        }.padding(.vertical, 6)
    }
}
