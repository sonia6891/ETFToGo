import SwiftUI

/* ---------- home: assets, market, watchlist, dividends and the combined simulation ---------- */
/// Opens 探索 on a segment, optionally with the search field focused (sent by the home page).
struct DiscoverRequest: Equatable {
    var stocks: Bool
    var search: Bool
    let id = UUID()
}

struct HomeView: View {
    @EnvironmentObject var store: PortfolioStore
    @Binding var tab: Int
    /// 總覽, 個股 or ETF: which part of the portfolio the asset card and the market card show.
    @State private var scope = 0
    @State private var watchKind = 0
    @State private var overview = false
    @AppStorage("hideAmounts") private var hidden = false
    @AppStorage("readNotices") private var readNotices = ""

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 14) {
                header
                searchBar
                ScopeTabs(items: ["總覽", "個股", "ETF"], selection: $scope)
                assetCard
                marketCard
                watchCard
                dividendsAndGoals
                linksRow
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await store.refreshIndices()
            if !store.data.holdings.isEmpty { await store.refresh() }
            else if !store.data.favorites.isEmpty { await store.refresh(symbols: Array(store.data.favorites)) }
        }
        .navigationDestination(isPresented: $overview) { OverviewView().tabBarSpace() }
        .onChange(of: scope) { _, value in if value > 0 { watchKind = value == 1 ? 0 : 1 } }
    }

    /* ---------- header and search ---------- */
    private var header: some View {
        let unread = AppNotice.all(store).filter { !readNotices.split(separator: ",").map(String.init).contains($0.id) }.count
        return HStack(spacing: 10) {
            Image("Pocket").resizable().interpolation(.high).scaledToFit().frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 11)).accessibilityHidden(true)
            Text("投資袋著走").font(.system(size: 24, weight: .heavy)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            NavigationLink(value: AppRoute.notices) {
                Image(systemName: "bell").font(.title3).foregroundStyle(Palette.ink).frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) { if unread > 0 { Circle().fill(Palette.red).frame(width: 9, height: 9).offset(x: -8, y: 8) } }
            }.accessibilityLabel(unread > 0 ? "通知中心，\(unread) 則未讀" : "通知中心")
            NavigationLink(value: AppRoute.settings) { Image(systemName: "gearshape").font(.title3).foregroundStyle(Palette.ink).frame(width: 40, height: 40) }.accessibilityLabel("設定")
        }.padding(.top, 4)
    }
    private var searchBar: some View {
        Button { openDiscover(stocks: scope == 1, search: true) } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.headline).foregroundStyle(Palette.ink)
                Text("搜尋股票、ETF").foregroundStyle(Palette.muted)
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 46)
            .background(Palette.card, in: Capsule())
            .shadow(color: Palette.blue.opacity(0.07), radius: 10, y: 3)
        }
        .buttonStyle(.plain).accessibilityIdentifier("home-search").accessibilityLabel("搜尋股票、ETF")
    }
    private func openDiscover(stocks: Bool, search: Bool) {
        store.discoverRequest = DiscoverRequest(stocks: stocks, search: search)
        tab = 1
    }

    /* ---------- assets ---------- */
    private struct Totals { var value: Double?; var cost: Double; var paid: Double; var count: Int }
    private func totals(_ scope: Int) -> Totals {
        let holdings = store.data.holdings.filter { scope == 0 || store.isStock($0.symbol) == (scope == 1) }
        let paid = store.data.dividends.filter { $0.status == .paid && (scope == 0 || store.isStock($0.symbol) == (scope == 1)) }.reduce(0) { $0 + $1.amount }
        let cost = holdings.reduce(0) { $0 + $1.cost }
        var value: Double?
        if scope == 0 { value = store.summary.marketValue }
        else if !holdings.isEmpty {
            let values = holdings.map { store.marketValue(of: $0) }
            value = values.contains { $0 == nil } ? nil : values.reduce(0) { $0 + ($1 ?? 0) }
        }
        return Totals(value: holdings.isEmpty ? nil : value, cost: cost, paid: paid, count: holdings.count)
    }
    private var assetCard: some View {
        let t = totals(scope)
        let unrealized = t.value.map { $0 - t.cost }
        let percent: Double? = unrealized.flatMap { t.cost > 0 ? $0 / t.cost * 100 : nil }
        let title = ["我的總資產", "我的個股資產", "我的 ETF 資產"][scope]
        var gainText = unrealized.map { shown(signed($0), hidden: hidden) } ?? "—"
        if let percent, !hidden { gainText += " (\(percentText(percent)))" }
        let gainTint: Color = unrealized.map { $0 > 0 ? Palette.heroUp : ($0 < 0 ? Palette.heroDown : Color.white) } ?? Color.white
        let costText = t.count == 0 ? "—" : shown(money(t.cost), hidden: hidden)
        let paidText = t.paid > 0 ? shown(money(t.paid), hidden: hidden) : "—"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title).font(.title3.bold())
                Text("(TWD)").font(.subheadline).opacity(0.85)
                Button { hidden.toggle() } label: { Image(systemName: hidden ? "eye.slash" : "eye").font(.headline) }
                    .buttonStyle(.plain).accessibilityLabel(hidden ? "顯示金額" : "隱藏金額")
                Spacer(minLength: 4)
                NavigationLink(value: AppRoute.holdingForm(id: nil, symbol: nil)) {
                    Label("新增持有", systemImage: "plus.circle.fill").font(.subheadline.bold()).lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1.2))
                }.buttonStyle(.plain).accessibilityIdentifier("home-add-holding")
            }
            Text(shown(t.value.map(money) ?? "—", hidden: hidden))
                .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
                .contentTransition(.numericText(value: t.value ?? 0)).animation(.snappy, value: t.value)
                .accessibilityIdentifier("portfolio-value")
            HStack(alignment: .bottom, spacing: 0) {
                heroStat("投入成本", costText, tint: .white)
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 34)
                heroStat("未實現損益", gainText, tint: gainTint)
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 34)
                heroStat("累積配息", paidText, tint: .white)
                Spacer(minLength: 104)
            }
        }
        .padding(18)
        .foregroundStyle(.white)
        .background(alignment: .bottomTrailing) { GlassBars().padding(.trailing, 14).padding(.bottom, 12) }
        .background { HeroWave().fill(Color.white.opacity(0.12)).padding(.top, 70) }
        .background(Palette.hero, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: Palette.blue.opacity(0.28), radius: 14, y: 6)
        .contentShape(Rectangle())
        .onTapGesture { overview = true }
        .accessibilityAction(named: "看資產總覽") { overview = true }
    }
    private func heroStat(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).opacity(0.9).lineLimit(1)
            Text(value).font(.subheadline.bold()).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.55)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
    }

    /* ---------- Taiwan market ---------- */
    private var marketCard: some View {
        let status = store.liveStatus
        let connected = status.running || store.indices["taiex"] != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill").foregroundStyle(Palette.blue)
                Text("台灣市場").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                NavigationLink(value: AppRoute.sources) {
                    HStack(spacing: 5) {
                        Circle().fill(connected ? Palette.green : Palette.pink).frame(width: 9, height: 9)
                            .overlay(Circle().stroke((connected ? Palette.green : Palette.pink).opacity(0.25), lineWidth: 4))
                        Text(status.running ? "盤中即時" : (connected ? "已連線" : "未連線")).font(.caption.bold())
                    }
                    .foregroundStyle(connected ? Palette.green : Palette.pink)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((connected ? Palette.green : Palette.pink).opacity(0.1), in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel(connected ? "行情已連線" : "行情未連線")
            }
            if scope == 0 {
                HStack(spacing: 10) {
                    HomeIndexTile(key: "taiex", title: "加權指數", tint: Palette.blue)
                    HomeIndexTile(key: "tpex", title: "櫃買指數", tint: Palette.purple)
                }
            } else {
                let pool = scope == 1 ? (store.stockSnapshot?.stocks.map(\.id) ?? []) : store.funds.map(\.id)
                let symbols = store.stockSnapshot?.mostTraded(pool, count: 5) ?? []
                Text(scope == 1 ? "熱門個股（依成交值）" : "熱門 ETF（依成交值）").font(.caption).foregroundStyle(Palette.muted)
                if symbols.isEmpty { Text("尚無收盤資料。").font(.subheadline).foregroundStyle(Palette.muted) }
                ForEach(symbols, id: \.self) { symbol in
                    SymbolRow(symbol: symbol)
                    if symbol != symbols.last { Divider() }
                }
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Palette.blue.opacity(0.06), radius: 10, y: 3)
    }

    /* ---------- watchlist ---------- */
    private var watchCard: some View {
        let favorites = store.data.favorites.filter { store.isStock($0) == (watchKind == 0) }.sorted()
        let shownSymbols = Array(favorites.prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill").font(.title3).foregroundStyle(Palette.orange)
                Text("我的自選").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                NavigationLink(value: AppRoute.watchlist) { HStack(spacing: 3) { Text("管理"); Image(systemName: "chevron.right") }.font(.subheadline.bold()) }
                    .accessibilityIdentifier("home-watchlist")
            }
            SegmentBar(items: ["股票", "ETF"], selection: $watchKind, pill: true, filled: true)
            if shownSymbols.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "star.fill").font(.system(size: 38))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.35), Palette.orange], startPoint: .top, endPoint: .bottom))
                        .shadow(color: Palette.orange.opacity(0.3), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("尚未加入自選").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                        Text("追蹤你關注的股票或 ETF，掌握即時動態。").font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button { openDiscover(stocks: watchKind == 0, search: false) } label: {
                        HStack(spacing: 3) { Text("新增自選"); Image(systemName: "chevron.right") }.font(.subheadline.bold()).foregroundStyle(Palette.blue)
                    }.buttonStyle(.plain).accessibilityIdentifier("home-add-favorite")
                }
                .padding(14)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.blue.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            } else {
                VStack(spacing: 0) {
                    ForEach(shownSymbols, id: \.self) { symbol in
                        SymbolRow(symbol: symbol)
                        if symbol != shownSymbols.last { Divider() }
                    }
                }
                if favorites.count > shownSymbols.count {
                    NavigationLink(value: AppRoute.watchlist) { Text("查看全部 \(favorites.count) 檔").font(.caption.bold()).frame(maxWidth: .infinity) }
                }
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Palette.blue.opacity(0.06), radius: 10, y: 3)
    }

    /* ---------- dividends and the combined simulation ---------- */
    private var monthAmount: Double { store.summary.monthPaid + store.summary.monthPending }
    /// The next dividend still to arrive: the user's own records first, else an official announcement for a holding.
    private var nextPayment: String {
        let today = Calendar.current.startOfDay(for: Date())
        if let record = store.data.dividends.filter({ $0.status != .paid && $0.date >= today }).min(by: { $0.date < $1.date }) {
            let parts = Calendar.current.dateComponents([.month, .day], from: record.date)
            return String(format: "%02d/%02d", parts.month ?? 0, parts.day ?? 0) + "・\(shown(money(record.amount), hidden: hidden)) 元"
        }
        let todayText = DataChecks.day()
        if let entry = store.officialForHoldings().filter({ !$0.event.pay.isEmpty && $0.event.pay >= todayText }).min(by: { $0.event.pay < $1.event.pay }) {
            let day = entry.event.pay.suffix(5).replacingOccurrences(of: "-", with: "/")
            return entry.event.amount.map { "\(day)・\(shown(money($0 * entry.shares), hidden: hidden)) 元" } ?? "\(day)・金額待公布"
        }
        return "—"
    }
    private var dividendsAndGoals: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: AppRoute.goal) {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill").font(.title3)
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.3), Palette.orange], startPoint: .top, endPoint: .bottom))
                    Text("配息與目標").font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("home-goal")
            HStack(alignment: .top, spacing: 10) {
                NavigationLink(value: AppRoute.monthDividends(next: false)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 3) { Text("本月配息").font(.subheadline.bold()); Text("(TWD)").font(.caption2) }.foregroundStyle(Palette.ink)
                                Text(monthAmount > 0 ? shown(money(monthAmount), hidden: hidden) : "—").font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            Spacer(minLength: 0)
                            Artwork(name: "div-coins", size: 50)
                        }
                        Divider()
                        HStack(spacing: 6) {
                            Text("下次入帳").font(.caption).foregroundStyle(Palette.muted)
                            Text(nextPayment).font(.caption.bold()).monospacedDigit().foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
                    .background(LinearGradient(colors: [Palette.orange.opacity(0.16), Palette.orange.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).accessibilityIdentifier("home-month-dividends")
                ComboTeaser()
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Palette.blue.opacity(0.06), radius: 10, y: 3)
    }
    private var linksRow: some View {
        NavigationLink(value: AppRoute.sources) {
            HStack(spacing: 10) {
                Image(systemName: "link").font(.headline).foregroundStyle(Palette.blue)
                Text("資料更新與券商連結").font(.subheadline).foregroundStyle(Palette.ink)
                Spacer()
                Text("尚未連結券商").font(.caption).foregroundStyle(Palette.muted)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Palette.cardSoft, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("home-sources")
    }
}

/// 總覽 / 個股 / ETF as underlined text tabs.
struct ScopeTabs: View {
    let items: [String]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 26) {
            ForEach(items.indices, id: \.self) { index in
                let active = selection == index
                Button { withAnimation(.snappy) { selection = index } } label: {
                    VStack(spacing: 6) {
                        Text(items[index]).font(.headline.weight(active ? .heavy : .semibold)).foregroundStyle(active ? Palette.blue : Palette.ink.opacity(0.75))
                        Capsule().fill(active ? Palette.blue : Color.clear).frame(width: 44, height: 3)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(items[index])
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            Spacer()
        }.padding(.leading, 12)
    }
}

/// An index with its last month as a sparkline and when it was updated.
struct HomeIndexTile: View {
    @EnvironmentObject var store: PortfolioStore
    let key: String
    let title: String
    let tint: Color
    var body: some View {
        let snapshot = store.stockSnapshot?.indices[key]
        let live = store.indices[key]
        let value = live?.price ?? snapshot?.close
        let change = live?.change ?? snapshot?.change
        let percent = live?.changePercent ?? snapshot?.percent
        let days = (snapshot?.history ?? []).suffix(22).compactMap { day in DataChecks.date(day.date).map { ValuePoint(date: $0, value: day.close) } }
        let updated: String = live.map { "更新時間：" + $0.fetchedAt.formatted(date: .omitted, time: .shortened) }
            ?? snapshot.map { "更新時間：\(String($0.date.suffix(5)).replacingOccurrences(of: "-", with: "/")) 收盤" } ?? "更新時間：—"
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                Text(title).font(.subheadline.bold()).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: 2)
                if days.count >= 2 { ValueChart(points: Array(days), height: 30, tint: tint).frame(width: 74) }
            }
            Text(value.map(priceText) ?? "—").font(.system(size: 19, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: value ?? 0)).animation(.snappy, value: value)
            if let change {
                let arrow = change > 0 ? "▲" : (change < 0 ? "▼" : "－")
                Text("\(arrow) \(priceText(abs(change)))\(percent.map { " (\(percentText($0)))" } ?? "")").font(.caption2.bold()).monospacedDigit().foregroundStyle(Palette.trend(change)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(updated).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [tint.opacity(0.1), tint.opacity(0.03)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// 組合試算: pick 3, 5 or 10 years and open the result; the card opens the simulation.
struct ComboTeaser: View {
    @EnvironmentObject var store: PortfolioStore
    var body: some View {
        let c = store.combo, starts = store.comboStarts(c)
        let ready = starts.stock + starts.etf > 0
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: AppRoute.combo) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("組合試算").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                        Text("個股 + ETF").font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                    Artwork(name: "tool-compound", size: 46)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("home-combo")
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach([3, 5, 10], id: \.self) { years in
                    let on = c.years == years
                    Button { var next = store.combo; next.years = years; store.saveCombo(next) } label: {
                        Text("\(years)年").font(.caption.bold()).foregroundStyle(on ? Color.white : Palette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(on ? Palette.blue : Color.clear, in: Capsule())
                    }.buttonStyle(.plain).accessibilityLabel("試算 \(years) 年").accessibilityAddTraits(on ? .isSelected : [])
                }
                NavigationLink(value: ready ? AppRoute.comboResult : AppRoute.combo) {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Palette.blue)
                        .frame(width: 28, height: 28).background(Palette.card, in: Circle())
                        .overlay(Circle().stroke(Palette.blue.opacity(0.25), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("看試算結果").accessibilityIdentifier("home-combo-result")
            }
            .padding(3)
            .background(Palette.card.opacity(0.7), in: Capsule())
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(LinearGradient(colors: [Palette.purple.opacity(0.14), Palette.blue.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Glassy rising bars with an arrow, the asset card's illustration.
struct GlassBars: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array([0.36, 0.55, 0.76, 1.0].enumerated()), id: \.offset) { index, height in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.9), Color(red: 0.62, green: 0.78, blue: 1).opacity(0.55 + Double(index) * 0.08)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.95), lineWidth: 1))
                        .frame(width: 20, height: 78 * height)
                        .shadow(color: Color(red: 0.1, green: 0.2, blue: 0.7).opacity(0.25), radius: 5, y: 3)
                }
            }
            RisingArrow().stroke(LinearGradient(colors: [Color.white.opacity(0.4), .white], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 92, height: 70).offset(x: -4, y: -46)
        }
        .frame(width: 104, height: 112, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
struct RisingArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.maxY * 0.92), end = CGPoint(x: rect.maxX * 0.95, y: rect.minY + rect.height * 0.08)
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: rect.width * 0.55, y: rect.height * 0.75))
        path.move(to: CGPoint(x: end.x - 13, y: end.y - 1))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - 3, y: end.y + 12))
        return path
    }
}
/// A soft wave across the lower half of the asset card.
struct HeroWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.45))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2),
                      control1: CGPoint(x: rect.width * 0.35, y: rect.minY + rect.height * 0.05),
                      control2: CGPoint(x: rect.width * 0.62, y: rect.minY + rect.height * 0.7))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
