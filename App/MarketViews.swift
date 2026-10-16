import SwiftUI
import Charts

/* ---------- shared pieces for stocks and ETFs ---------- */
/// Rounded square with the company's first two characters (stocks) or the code (ETFs).
struct SymbolAvatar: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    var size: CGFloat = 42
    private static let colors: [Color] = [Palette.blue, Palette.pink, Palette.teal, Palette.orange, Palette.purple, Palette.green, Palette.red, Color(red: 0.23, green: 0.48, blue: 0.84)]
    var body: some View {
        let stock = store.isStock(symbol)
        let label = stock ? String(store.name(for: symbol).prefix(2)) : symbol
        let hash = symbol.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 997 }
        let color = stock ? Self.colors[hash % Self.colors.count] : Palette.blue
        Text(label)
            .font(.system(size: stock ? size * 0.33 : (symbol.count > 5 ? size * 0.24 : size * 0.29), weight: .heavy, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}
/// 上市 / 上櫃 for stocks, ETF for funds.
struct MarketBadge: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    var body: some View {
        if store.isStock(symbol) {
            let tpex = store.stock(symbol)?.market == "TPEx"
            TintPill(title: tpex ? "上櫃" : "上市", color: tpex ? Palette.teal : Palette.blue)
        } else {
            TintPill(title: "ETF", color: Palette.orange)
        }
    }
}
/// Opens the stock page for company shares and the ETF page for funds.
struct SymbolLink<Label: View>: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    @ViewBuilder var label: Label
    var body: some View {
        if store.isStock(symbol) {
            NavigationLink(value: AppRoute.stock(symbol)) { label }.buttonStyle(.plain)
        } else {
            NavigationLink(value: store.funds.first { $0.id == symbol } ?? Fund(id: symbol, name: store.name(for: symbol), strategy: .unclassified)) { label }.buttonStyle(.plain)
        }
    }
}
/// Avatar, code and name, market badge, price and change, watchlist star.
struct SymbolRow: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    var subtitle: String? = nil
    var body: some View {
        let quote = store.quote(symbol), on = store.data.favorites.contains(symbol)
        HStack(spacing: 6) {
            SymbolLink(symbol: symbol) {
                HStack(spacing: 10) {
                    SymbolAvatar(symbol: symbol)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) { Text(symbol).font(.subheadline.bold()).monospacedDigit(); Text(store.name(for: symbol)).font(.subheadline.bold()).lineLimit(1) }.foregroundStyle(Palette.ink)
                        HStack(spacing: 6) { MarketBadge(symbol: symbol); if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1) } }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(quote.map { priceText($0.price) } ?? "—").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink)
                            .contentTransition(.numericText(value: quote?.price ?? 0)).animation(.snappy, value: quote?.price)
                        QuoteChange(quote: quote, font: .caption2)
                    }
                }.contentShape(Rectangle())
            }
            Button { store.favorite(symbol) } label: {
                Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? Palette.orange : Palette.muted.opacity(0.5)).frame(width: 32, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(on ? "取消自選 \(symbol)" : "加入自選 \(symbol)")
        }
        .padding(.vertical, 6)
    }
}

/* ---------- home: 大盤 / 個股 / ETF and watchlist ---------- */
struct MarketSection: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var tab = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SegmentBar(items: ["大盤", "個股", "ETF"], selection: $tab, pill: true, filled: true)
            if tab == 0 {
                HStack(spacing: 10) {
                    IndexCard(key: "taiex", title: "加權指數", tint: Palette.blue)
                    IndexCard(key: "tpex", title: "櫃買指數", tint: Palette.purple)
                }
            } else {
                let pool = tab == 1 ? (store.stockSnapshot?.stocks.map(\.id) ?? []) : store.funds.map(\.id)
                let symbols = store.stockSnapshot?.mostTraded(pool, count: 5) ?? []
                Card(padding: 12) {
                    if symbols.isEmpty { Text("尚無收盤資料。").font(.subheadline).foregroundStyle(Palette.muted) }
                    ForEach(symbols, id: \.self) { symbol in
                        SymbolRow(symbol: symbol)
                        if symbol != symbols.last { Divider() }
                    }
                }
                if let day = store.stockSnapshot?.closeDate["twse"] { Text("依 \(day.replacingOccurrences(of: "-", with: "/")) 成交值排序的\(tab == 1 ? "熱門個股" : "熱門 ETF")。").font(.caption).foregroundStyle(Palette.muted) }
            }
            SourceCard()
        }
    }
}
struct IndexCard: View {
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
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "chart.bar.fill").font(.subheadline.bold()).foregroundStyle(Palette.ink).labelStyle(TintedIconLabel(tint: tint))
            Text(value.map(priceText) ?? "—").font(.system(size: 21, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1).padding(.top, 6)
                .contentTransition(.numericText(value: value ?? 0)).animation(.snappy, value: value)
            if let change {
                Text(changeLine(change, percent)).font(.caption.bold()).monospacedDigit().foregroundStyle(Palette.trend(change)).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("— (—)").font(.caption).foregroundStyle(Palette.muted)
            }
            if days.count >= 2 { ValueChart(points: Array(days), height: 56, tint: tint).padding(.top, 6) } else { Color.clear.frame(height: 56) }
            Text(caption(live: live, snapshot: snapshot)).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [tint.opacity(0.1), Palette.card], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: Palette.blue.opacity(0.07), radius: 10, y: 3)
        .accessibilityElement(children: .combine)
    }
    private func changeLine(_ change: Double, _ percent: Double?) -> String {
        let arrow = change > 0 ? "▲" : (change < 0 ? "▼" : "－")
        let tail = percent.map { " (" + percentText($0) + ")" } ?? ""
        return arrow + " " + priceText(abs(change)) + tail
    }
    private func caption(live: Quote?, snapshot: StockSnapshot.MarketIndex?) -> String {
        if let live { return "即時・" + live.fetchedAt.formatted(date: .omitted, time: .shortened) }
        guard let snapshot else { return "走勢待取得" }
        let day = String(snapshot.date.suffix(5)).replacingOccurrences(of: "-", with: "/")
        return "近 \(min(snapshot.history.count, 22)) 個交易日・\(day) 收盤"
    }
}
struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.foregroundStyle(tint); configuration.title }
    }
}
/// How fresh the prices are and a refresh button; where they come from is not shown.
struct SourceCard: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var hasKey = false
    @State private var busy = false
    var body: some View {
        let day: String? = store.stockSnapshot?.closeDate["twse"]?.replacingOccurrences(of: "-", with: "/")
        let status = store.liveStatus
        let connected = hasKey || store.indices["taiex"] != nil || status.running
        let closeDay = store.indices["taiex"]?.date.replacingOccurrences(of: "-", with: "/") ?? day
        let closed: String = closeDay.map { "最新收盤 \($0)" } ?? "尚未取得報價"
        let headline: String = status.running ? liveLine(status) : closed
        let stamp = status.lastUpdate ?? store.indices["taiex"]?.fetchedAt
        let updated: String = stamp.map { $0.formatted(date: .omitted, time: .standard) } ?? "—"
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if status.running { Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(Palette.green).symbolEffect(.pulse) }
                    Text(headline).fixedSize(horizontal: false, vertical: true)
                }
                Text("更新時間：\(updated)")
                if !status.note.isEmpty { Text(status.note).fixedSize(horizontal: false, vertical: true) }
            }.font(.caption).foregroundStyle(Palette.muted)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 5) { Circle().fill(connected ? Palette.green : Palette.pink).frame(width: 8, height: 8); Text(connected ? "已連線" : "未連線").font(.caption.bold()) }.foregroundStyle(connected ? Palette.green : Palette.pink)
                Button(busy ? "更新中…" : "即時更新") { Task { busy = true; await store.refreshIndices(); await store.refresh(symbols: Array(store.data.favorites) + store.data.holdings.map(\.symbol)); busy = false } }.font(.caption.bold()).disabled(busy)
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Palette.blue.opacity(0.06), radius: 10, y: 3)
        .onAppear { hasKey = ((try? SecureKey.read()) ?? "").isEmpty == false }
    }
    private func liveLine(_ status: LiveStatus) -> String {
        if status.exchange { return "盤中即時更新・每 10 秒" }
        var parts: [String] = []
        if !status.subscribed.isEmpty { parts.append("即時串流 \(status.subscribed.count) 檔") }
        else if status.connecting { parts.append("正在連線即時串流") }
        else if status.reconnecting { parts.append("串流中斷，稍後自動重連") }
        if status.paidPlan { parts.append("全市場每 5 秒") }
        else if status.pollSeconds > 0 { parts.append("其餘約每 \(status.pollSeconds) 秒") }
        parts.append("指數每 15 秒")
        return parts.joined(separator: "・")
    }
}
struct WatchSection: View {
    @EnvironmentObject var store: PortfolioStore
    var body: some View {
        let favorites = Array(store.data.favorites.sorted { store.isStock($0) && !store.isStock($1) }.prefix(5))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "star.fill").foregroundStyle(Palette.orange)
                Text("我的自選").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                NavigationLink(value: AppRoute.watchlist) { HStack(spacing: 2) { Text("查看全部"); Image(systemName: "chevron.right") }.font(.caption.bold()) }
            }
            Card(padding: 12) {
                if favorites.isEmpty { Text("在探索或詳情頁按星號，就能把股票與 ETF 加入自選。").font(.subheadline).foregroundStyle(Palette.muted) }
                ForEach(favorites, id: \.self) { symbol in
                    SymbolRow(symbol: symbol)
                    if symbol != favorites.last { Divider() }
                }
            }
        }
    }
}

/* ---------- stock detail ---------- */
struct StockDetailView: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    @State private var section = 0
    @State private var range = ChartRange.year
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        let info = store.stock(symbol), quote = store.quote(symbol)
        Page {
            Card(padding: 14) {
                HStack(spacing: 12) {
                    SymbolAvatar(symbol: symbol, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) { Text(symbol).font(.title2.bold()).monospacedDigit(); Text(store.name(for: symbol)).font(.title3.bold()).lineLimit(1); MarketBadge(symbol: symbol) }.foregroundStyle(Palette.ink)
                        Text(info?.fullName ?? info?.industry ?? "").font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Card(padding: 14) {
                    Text(quote.map { priceText($0.price) } ?? "—").font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText(value: quote?.price ?? 0)).animation(.snappy, value: quote?.price)
                    QuoteChange(quote: quote, font: .subheadline).padding(.top, 4)
                }
                Card(padding: 12) { sourceInfo(quote) }
            }
            SegmentBar(items: ["總覽", "走勢", "財務", "股利"], selection: $section, pill: true, filled: true)
            switch section {
            case 1: HistoryContent(symbol: symbol)
            case 2: finance
            case 3: dividends(quote)
            default: overview(info, quote)
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .task { await store.refreshLive([symbol]) }
        .onAppear { store.liveFocus = symbol; store.live.syncSoon() }
        .onDisappear { if store.liveFocus == symbol { store.liveFocus = nil; store.live.syncSoon() } }
        .navigationTitle("個股詳情").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { store.favorite(symbol) } label: { Image(systemName: store.data.favorites.contains(symbol) ? "star.fill" : "star").foregroundStyle(Palette.orange) }.accessibilityLabel("切換自選")
                ShareLink(item: "\(symbol) \(store.name(for: symbol))｜投資袋著走") { Image(systemName: "square.and.arrow.up") }
            }
        }
    }
    private func sourceInfo(_ quote: Quote?) -> some View {
        var live = false
        if let quote, let own = store.liveQuotes[symbol] ?? store.data.quotes[symbol], own.fetchedAt == quote.fetchedAt { live = quote.fetchedAt.timeIntervalSinceNow > -86400 }
        let updated: String = quote.map { $0.date.replacingOccurrences(of: "-", with: "/") + (live ? " " + $0.fetchedAt.formatted(date: .omitted, time: .shortened) : "") } ?? "—"
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) { Circle().fill(live ? Palette.green : Palette.pink).frame(width: 8, height: 8); Text(live ? "已連線" : "未連線").font(.caption.bold()) }.foregroundStyle(live ? Palette.green : Palette.pink)
            Text("更新時間：\(updated)").font(.caption2)
        }.foregroundStyle(Palette.muted)
    }
    private func overview(_ info: StockInfo?, _ quote: Quote?) -> some View {
        let points = store.data.histories?[symbol].map(TrendMath.points) ?? []
        let visible = TrendMath.slice(points, range)
        return VStack(alignment: .leading, spacing: 16) {
            Card(padding: 14) {
                Label("股價走勢", systemImage: "chart.bar.fill").font(.headline).foregroundStyle(Palette.ink)
                RangeChips(options: [.week, .month, .quarter, .year, .all], selection: $range).padding(.vertical, 10)
                if visible.count >= 2 {
                    ValueChart(points: visible, showAxes: true, height: 170)
                } else {
                    Text("尚無歷史走勢").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                    Text("使用你的富果金鑰取得近 5 年還原日收盤價，約需 10 秒；不以試算資料代替。").font(.caption).foregroundStyle(Palette.muted).padding(.vertical, 6)
                    Button(busy ? "取得中…" : "取得歷史走勢") { Task { busy = true; error = nil; defer { busy = false }; do { try store.saveHistory(await Fugle.history(symbol: symbol, years: 5)) } catch { self.error = error.localizedDescription } } }.buttonStyle(.borderedProminent).disabled(busy)
                    if let error { Text(error).font(.caption).foregroundStyle(Palette.red).padding(.top, 6) }
                }
            }
            Card(padding: 12) {
                HStack(spacing: 0) {
                    stat("成交量", quote?.volume.map { "\(money($0)) 張" })
                    Divider().frame(height: 34)
                    stat("開盤", quote?.open.map(priceText))
                    Divider().frame(height: 34)
                    stat("最高", quote?.high.map(priceText))
                    Divider().frame(height: 34)
                    stat("最低", quote?.low.map(priceText))
                }
            }
            if let info {
                Card(padding: 14) {
                    Text("公司資料").font(.headline).foregroundStyle(Palette.ink).padding(.bottom, 6)
                    LabeledContent("產業", value: info.industry); Divider().padding(.vertical, 6)
                    LabeledContent("市場", value: info.marketName); Divider().padding(.vertical, 6)
                    LabeledContent("上市櫃日期", value: info.listingDate.replacingOccurrences(of: "-", with: "/")); Divider().padding(.vertical, 6)
                    LabeledContent("公司全名", value: info.fullName)
                }.font(.subheadline)
            }
            if let quote, store.data.quotes[symbol] == nil, store.liveQuotes[symbol] == nil { Text("收盤價・資料日 \(quote.date.replacingOccurrences(of: "-", with: "/"))（非即時）").font(.caption).foregroundStyle(Palette.muted) }
            Button(store.refreshing ? "更新中…" : "更新報價") { Task { await store.refresh(symbols: [symbol]) } }.font(.caption.bold()).disabled(store.refreshing)
        }
    }
    private func stat(_ title: String, _ value: String?) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(Palette.muted)
            Text(value ?? "—").font(.subheadline.bold()).monospacedDigit().foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity)
    }
    private var finance: some View {
        let revenue = store.stockSnapshot?.revenue[symbol], eps = store.stockSnapshot?.earnings[symbol]
        return VStack(alignment: .leading, spacing: 16) {
            Card(padding: 14) {
                Label("月營收", systemImage: "chart.bar.xaxis").font(.headline).foregroundStyle(Palette.ink)
                if let revenue {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(amountText(revenue.amount)).font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
                        Text("\(revenue.month.prefix(4)) 年 \(Int(revenue.month.suffix(2)) ?? 0) 月").font(.caption).foregroundStyle(Palette.muted)
                    }.padding(.vertical, 8)
                    HStack { Text("月增率").foregroundStyle(Palette.muted); Spacer(); changeText(revenue.monthChange) }; Divider().padding(.vertical, 6)
                    HStack { Text("年增率").foregroundStyle(Palette.muted); Spacer(); changeText(revenue.yearChange) }; Divider().padding(.vertical, 6)
                    HStack { Text("今年累計營收").foregroundStyle(Palette.muted); Spacer(); Text(amountText(revenue.cumulative)).font(.subheadline.bold()).monospacedDigit() }; Divider().padding(.vertical, 6)
                    HStack { Text("累計年增率").foregroundStyle(Palette.muted); Spacer(); changeText(revenue.cumulativeChange) }
                } else { Text("尚未收錄這家公司的月營收。").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 8) }
            }.font(.subheadline)
            Card(padding: 14) {
                Label("基本每股盈餘（EPS）", systemImage: "dollarsign.circle").font(.headline).foregroundStyle(Palette.ink)
                if let eps {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(decimal(eps.value)) 元").font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink)
                        Text(eps.quarter == 4 ? "\(String(eps.year)) 年全年" : "\(String(eps.year)) 年前 \(eps.quarter) 季累計").font(.caption).foregroundStyle(Palette.muted)
                    }.padding(.top, 8)
                } else { Text("尚未收錄這家公司的財報每股盈餘。").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 8) }
            }
            Text("資料取得日 \(store.stockSnapshot?.fetchedDay ?? "—")。月營收為公司自結數，原始單位千元。").font(.caption).foregroundStyle(Palette.muted)
        }
    }
    /// Revenue is reported in thousand NT$.
    private func amountText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value >= 100_000 ? "\(decimal(value / 100_000)) 億元" : "\(decimal(value / 10)) 萬元"
    }
    private func changeText(_ value: Double?) -> some View {
        Text(value.map(percentText) ?? "—").font(.subheadline.bold()).monospacedDigit().foregroundStyle(value.map(Palette.trend) ?? Palette.muted)
    }
    private func policyTitle(_ item: StockSnapshot.Policy) -> String {
        let year = (Int(item.year) ?? 0) + 1911
        return item.period == "年度" ? "\(year) 年度" : "\(year) 年 \(item.period)"
    }
    private func dividends(_ quote: Quote?) -> some View {
        let snapshot = store.stockSnapshot
        let cash = snapshot?.trailingCash(symbol) ?? 0
        let price: Double = quote?.price ?? 0
        let yield: Double = cash > 0 && price > 0 ? cash / price * 100 : 0
        let history = snapshot?.exHistory[symbol] ?? [], upcoming = snapshot?.exUpcoming[symbol] ?? [], policies = snapshot?.policies[symbol] ?? []
        let tpex = store.stock(symbol)?.market == "TPEx"
        return VStack(alignment: .leading, spacing: 16) {
            Card(padding: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text("近一年現金股利（除息）").font(.caption).foregroundStyle(Palette.muted); Text(cash > 0 ? "\(decimal(cash)) 元" : "—").font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.ink) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) { Text("現金殖利率").font(.caption).foregroundStyle(Palette.muted); Text(yield > 0 ? "\(decimal(yield))%" : "—").font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.ink) }
                }
                Text(yield > 0 ? "依現價計算；除權息同時進行的不計入。" : (tpex ? "上櫃公司目前只收錄近期除權息預告。" : "近一年沒有純除息紀錄。")).font(.caption).foregroundStyle(Palette.muted).padding(.top, 6)
            }
            if !policies.isEmpty {
                Card(padding: 14) {
                    SectionHeading(title: "最新股利政策")
                    ForEach(policies.prefix(4)) { item in
                        Divider().padding(.vertical, 6)
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(policyTitle(item)).font(.subheadline.bold())
                                TintPill(title: item.progress, color: item.progress.contains("股東會") ? Palette.green : Palette.blue)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("現金 \(decimal(item.cash)) 元／股").font(.subheadline)
                                if item.stock > 0 { Text("股票 \(decimal(item.stock)) 元／股").font(.subheadline) }
                            }
                        }.foregroundStyle(Palette.ink)
                    }
                }
            }
            if !upcoming.isEmpty {
                Card(padding: 14) {
                    SectionHeading(title: "近期除權息")
                    ForEach(upcoming) { item in HStack { Text("\(item.date.replacingOccurrences(of: "-", with: "/"))（\(item.kind)）"); Spacer(); Text(item.value.map { "\(decimal($0)) 元" } ?? "—").bold() }.font(.subheadline).padding(.top, 8) }
                }
            }
            Card(padding: 12) {
                if history.isEmpty {
                    Text(tpex ? "上櫃公司的除權息歷史尚未收錄。" : "近兩年沒有除權息紀錄。").font(.subheadline).foregroundStyle(Palette.muted)
                } else {
                    HStack { Text("除權息日"); Spacer(); Text("類型").frame(width: 60); Text("權值＋息值").frame(width: 90, alignment: .trailing) }.font(.caption.bold()).foregroundStyle(Palette.muted)
                    ForEach(history.prefix(12)) { item in
                        Divider().padding(.vertical, 6)
                        HStack { Text(item.date.replacingOccurrences(of: "-", with: "/")).monospacedDigit(); Spacer(); Text(item.kind).frame(width: 60); Text(item.value.map { "\(decimal($0)) 元" } ?? "—").bold().monospacedDigit().frame(width: 90, alignment: .trailing) }.font(.subheadline).foregroundStyle(Palette.ink)
                    }
                }
            }
            NavigationLink(value: AppRoute.dividendForm(id: nil, symbol: symbol, officialEx: nil)) { PrimaryButtonLabel(title: "記錄這檔配息") }.buttonStyle(.plain)
        }
    }
    private var actionBar: some View {
        let favorite = store.data.favorites.contains(symbol)
        return HStack(spacing: 12) {
            Button { store.favorite(symbol) } label: {
                Label(favorite ? "已加入自選" : "加入自選", systemImage: favorite ? "star.fill" : "star").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(Palette.blue).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.blue, lineWidth: 1.2))
            }
            // A route, not a presented destination: screens pushed from there must stack above it.
            NavigationLink(value: AppRoute.comboAdding(symbol)) {
                Label("加入試算", systemImage: "function").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white).background(Palette.hero, in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityIdentifier("stock-add-combo")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/* ---------- Explore: stocks ---------- */
struct StockDiscoverContent: View {
    @EnvironmentObject var store: PortfolioStore
    @Binding var query: String
    @State private var market = ""
    @State private var industry = ""
    @State private var showAll = false
    var body: some View {
        let text = query.trimmingCharacters(in: .whitespaces)
        let all = store.stockSnapshot?.stocks ?? []
        let items = all.filter { (market.isEmpty || $0.market == market) && (industry.isEmpty || $0.industry == industry) && (text.isEmpty || $0.id.localizedCaseInsensitiveContains(text) || $0.name.localizedCaseInsensitiveContains(text)) }
        let visible = showAll ? items : Array(items.prefix(60))
        VStack(alignment: .leading, spacing: 14) {
            Card(padding: 14) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) { Capsule().fill(Palette.orange).frame(width: 3, height: 14); Text("市場").font(.subheadline.bold()).foregroundStyle(Palette.ink) }.frame(width: 64, alignment: .leading)
                    OptionChip(title: "全部", on: market.isEmpty) { market = "" }
                    OptionChip(title: "上市", on: market == "TWSE") { market = "TWSE" }
                    OptionChip(title: "上櫃", on: market == "TPEx") { market = "TPEx" }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    HStack(spacing: 6) { Capsule().fill(Palette.orange).frame(width: 3, height: 14); Text("產業").font(.subheadline.bold()).foregroundStyle(Palette.ink) }.frame(width: 64, alignment: .leading)
                    Menu {
                        Button("全部產業") { industry = "" }
                        ForEach((store.stockSnapshot?.industries ?? []).sorted(), id: \.self) { name in Button(name) { industry = name } }
                    } label: { HStack(spacing: 4) { Text(industry.isEmpty ? "全部產業" : industry); Image(systemName: "chevron.down") }.font(.subheadline.bold()) }
                    Spacer(minLength: 0)
                }.padding(.top, 12)
            }
            HStack {
                Text("\(text.isEmpty && market.isEmpty && industry.isEmpty ? "全部個股" : "符合條件") (\(items.count))").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                NavigationLink(value: AppRoute.watchlist) { Label("我的自選 \(store.data.favorites.count)", systemImage: "star.fill").font(.caption.bold()) }
            }
            Card(padding: 12) {
                if items.isEmpty { Text(all.isEmpty ? "個股名單載入失敗。" : "找不到符合的股票，換個代號、名稱或產業試試。").font(.subheadline).foregroundStyle(Palette.muted) }
                LazyVStack(spacing: 0) {
                    ForEach(visible) { stock in
                        SymbolRow(symbol: stock.id, subtitle: stock.industry)
                        if stock.id != visible.last?.id { Divider() }
                    }
                }
                if items.count > visible.count { Button("顯示全部 \(items.count) 檔") { showAll = true }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.top, 10) }
            }
            if let snapshot = store.stockSnapshot {
                Text("上市 \(all.filter { $0.market == "TWSE" }.count) · 上櫃 \(all.filter { $0.market == "TPEx" }.count) 家公司（資料日 \(snapshot.fetchedDay)）。持有、自選與看過的個股會即時更新，其餘顯示 \(snapshot.closeDate["twse"] ?? "") 收盤價。").font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }
}
