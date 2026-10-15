import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var tab: Int
    @State private var addHolding = false
    @AppStorage("hideAmounts") private var hideAmounts = false
    private var summary: (cost: Decimal, pricedCost: Decimal, value: Decimal?, count: Int) { Finance.summary(store.data.planning.holdings) }
    private var received: Decimal {
        let month = String(Validation.day().prefix(7))
        return store.data.planning.dividends.filter { $0.status == .received && $0.paymentDate.hasPrefix(month) }.reduce(0) { $0 + $1.amount }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("你的 ETF，都在這裡。").font(.title2.bold())
                    Text("把持有、配息與投資角色，都袋著走。").font(.subheadline).foregroundStyle(.secondary)
                }
                Card {
                    HStack {
                        Text("我的資產總覽").font(.headline).foregroundStyle(.blue)
                        Spacer()
                        Button { hideAmounts.toggle() } label: { Image(systemName: hideAmounts ? "eye.slash" : "eye") }.accessibilityLabel(hideAmounts ? "顯示金額" : "隱藏金額")
                    }
                    Text("已填台幣參考價的部位市值").font(.caption).foregroundStyle(.secondary)
                    Text(hideAmounts ? "••••••" : money(summary.value)).font(.largeTitle.bold()).minimumScaleFactor(0.5)
                    HStack(alignment: .top) {
                        metric("總投入成本", hideAmounts ? "••••" : money(summary.cost))
                        Spacer()
                        metric("本月實收股息", hideAmounts ? "••••" : money(received))
                    }
                    Text("已填價格 \(summary.count)／\(store.data.planning.holdings.count) 筆。參考價不是即時行情，股息另列。").font(.caption).foregroundStyle(.secondary)
                    Button("查看我的持有") { tab = 2 }.buttonStyle(.bordered)
                }
                HStack(alignment: .top, spacing: 8) {
                    shortcut("找 ETF", "magnifyingglass", .teal) { tab = 1 }
                    shortcut("我的持有", "wallet.pass", .orange) { tab = 2 }
                    shortcut("股息月曆", "calendar", .pink) { tab = 3 }
                    NavigationLink { PlanningView() } label: { VStack(spacing: 8) { Image(systemName: "function").font(.title2).frame(width: 50, height: 50).background(.blue.opacity(0.12), in: Circle()); Text("試算工具").font(.caption.bold()) }.frame(maxWidth: .infinity) }
                }.foregroundStyle(.primary)
                Card {
                    Text("這檔 ETF，扮演什麼角色？").font(.headline)
                    ForEach(InvestmentRole.allCases) { role in
                        NavigationLink { ExploreView(initialRole: role.rawValue) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: role.symbol).foregroundStyle(role.color).frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) { Text(role.title).font(.headline); Text(role.subtitle).font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }.foregroundStyle(.primary)
                    }
                    Text("依策略初判；印鈔機候選尚未證實獲利穩定性。").font(.caption).foregroundStyle(.secondary)
                }
                if store.data.planning.holdings.isEmpty {
                    Card {
                        Text("從你的第一檔 ETF 開始").font(.headline)
                        Text("記下股數、總成本與券商，離線也能查看。").font(.subheadline).foregroundStyle(.secondary)
                        Button { addHolding = true } label: { Label("新增持有", systemImage: "plus") }.buttonStyle(.borderedProminent)
                    }
                }
                Text("\(store.catalog?.records.count ?? 0) 個 ETF 證券代碼 · \(store.catalogStatus)").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("ETF 袋著走").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $addHolding) { HoldingEditor() }
    }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).minimumScaleFactor(0.6) } }
    private func shortcut(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 8) { Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 50, height: 50).background(color.opacity(0.12), in: Circle()); Text(title).font(.caption.bold()) }.frame(maxWidth: .infinity) }
    }
}

struct ExploreView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var role: String
    @State private var favoritesOnly = false
    @State private var strategy = "全部策略"
    init(initialRole: String = "all") { _role = State(initialValue: initialRole) }
    private var records: [ETF] {
        (store.catalog?.records ?? []).filter { e in
            let result = RoleClassifier.classify(e)
            return (query.isEmpty || e.code.localizedCaseInsensitiveContains(query) || e.name.localizedCaseInsensitiveContains(query)) && (role == "all" || (role == "pending" ? result.role == nil : result.role?.rawValue == role)) && (!favoritesOnly || store.data.favorites.contains(e.code)) && (strategy == "全部策略" || e.strategy == strategy)
        }
    }
    var body: some View {
        List {
            Section {
                Picker("投資角色", selection: $role) {
                    Text("全部").tag("all")
                    ForEach(InvestmentRole.allCases) { Text($0.title).tag($0.rawValue) }
                    Text("待核驗").tag("pending")
                }
                Picker("基金策略", selection: $strategy) {
                    Text("全部策略").tag("全部策略")
                    ForEach(Array(Set((store.catalog?.records ?? []).map(\.strategy))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Toggle("只看收藏", isOn: $favoritesOnly)
                if let selected = InvestmentRole(rawValue: role) { Text(selected.explanation).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                if records.isEmpty { ContentUnavailableView("沒有符合的 ETF", systemImage: "magnifyingglass", description: Text("調整搜尋條件，或下拉更新名單。")) }
                ForEach(records) { e in NavigationLink { ETFDetailView(etf: e) } label: { ETFRow(etf: e) } }
            } header: { Text("\(records.count) 個代碼") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.catalog?.coverage ?? "名單尚未載入")
                    Text(store.catalogStatus)
                }
            }
        }.searchable(text: $query, prompt: "搜尋代碼或名稱")
            .navigationTitle("找 ETF").refreshable { await store.refreshCatalog() }
            .toolbar { NavigationLink { ComparisonView() } label: { Image(systemName: "rectangle.split.3x1") }.accessibilityLabel("比較 ETF") }
    }
}

struct ETFDetailView: View {
    @EnvironmentObject private var store: AppStore
    let etf: ETF
    @State private var addHolding = false
    @State private var quote: Quote?
    @State private var quoteError: String?
    @State private var loading = false
    private var classification: Classification { RoleClassifier.classify(etf) }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) { Text(etf.name).font(.title2.bold()); RoleBadge(result: classification); Text(classification.status).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 8)
                Button { addHolding = true } label: { Label("加入我的持有", systemImage: "plus.circle.fill") }
                Button { store.toggleFavorite(etf.code) } label: { Label(store.data.favorites.contains(etf.code) ? "移除收藏" : "加入收藏", systemImage: store.data.favorites.contains(etf.code) ? "star.fill" : "star") }
                Button { store.toggleCompare(etf.code) } label: { Label(store.data.comparison.contains(etf.code) ? "移出比較" : "加入比較（最多三檔）", systemImage: "rectangle.split.3x1") }
            }
            Section("為什麼這樣分類") {
                Text(classification.reason)
                LabeledContent("風險判讀", value: classification.risk)
                Text("穩定性尚未核驗：還需要含息總報酬、最大回撤、波動與跨年度表現。這是 App 的投資角色初判，不是官方風險評級。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("行情查詢") {
                if let q = quote {
                    LabeledContent("最後成交價", value: q.closePrice.map { $0.formatted(.number.precision(.fractionLength(2...4))) } ?? "尚無成交價")
                    LabeledContent("交易日期", value: q.date)
                    Text("富果行情 · 依商品原始交易幣別顯示；不自動改寫台幣持有紀錄。").font(.caption).foregroundStyle(.secondary)
                }
                Button { Task { loading = true; quoteError = nil; defer { loading = false }; do { quote = try await MarketAPI.quote(etf.code) } catch { quoteError = error.localizedDescription } } } label: { HStack { Text("\(quote == nil ? "查詢" : "更新")行情"); if loading { ProgressView() } } }.disabled(loading)
                InlineError(text: quoteError)
            }
            Section { NavigationLink("成分股與權重") { ComponentsView(code: etf.code) } }
            Section("基金資料") {
                LabeledContent("市場", value: etf.market == "TWSE" ? "證交所上市" : "櫃買中心上櫃")
                LabeledContent("類型", value: etf.fundType)
                LabeledContent("策略初判", value: etf.strategy)
                LabeledContent("追蹤指數", value: etf.indexName.isEmpty ? "來源未提供" : etf.indexName)
                LabeledContent(etf.dateLabel ?? "出表日", value: etf.sourceDate)
                if let date = etf.listingDate { LabeledContent("掛牌日", value: date) }
                if let url = URL(string: etf.sourceURL) { Link("查看官方資料來源", destination: url) }
            }
        }.navigationTitle(etf.code).navigationBarTitleDisplayMode(.inline).sheet(isPresented: $addHolding) { HoldingEditor(etf: etf) }
    }
}
struct ComparisonView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            if store.data.comparison.isEmpty { ContentUnavailableView("尚未加入比較", systemImage: "rectangle.split.3x1", description: Text("到 ETF 詳情加入最多三檔。")) }
            ForEach(store.data.comparison, id: \.self) { code in
                Section(code) {
                    if let e = store.etf(code) { ETFRow(etf: e); Text(RoleClassifier.classify(e).reason).font(.footnote); Text(RoleClassifier.classify(e).risk).font(.footnote).foregroundStyle(.secondary) }
                    else { Text("目前名單沒有此代碼，已保留你的比較選擇。") }
                    Button("移出比較", role: .destructive) { store.toggleCompare(code) }
                }
            }
        }.navigationTitle("ETF 比較")
    }
}
