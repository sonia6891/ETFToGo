import SwiftUI

@main struct ETFToGoApp: App {
    @StateObject private var store: PortfolioStore
    @AppStorage("appearance") private var appearance = "light"
    init() {
        let args = ProcessInfo.processInfo.arguments
        let testURL = args.contains("--ui-testing") ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ETFToGo/ui-test.json") : nil
        _store = StateObject(wrappedValue: PortfolioStore(url: testURL, demo: args.contains("--demo"), reset: args.contains("--reset")))
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(appearance == "light" ? .light : (appearance == "dark" ? .dark : nil))
        }
    }
}
struct RootView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var tab = 0
    /// Re-selecting a tab returns it to its first screen.
    @State private var resets = [0, 0, 0, 0, 0]
    @State private var minimized = false
    var body: some View {
        TabView(selection: $tab) {
            stack(0) { HomeView(tab: $tab) }
            stack(1) { DiscoverView() }
            stack(2) { HoldingsView() }
            stack(3) { DividendsView() }
            stack(4) { ToolsView() }
        }
        .tint(Palette.blue)
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $tab, minimized: minimized, reselect: { resets[$0] += 1 }, expand: { minimized = false }).ignoresSafeArea(.keyboard)
        }
        .environment(\.tabBarMinimize) { value in if minimized != value { minimized = value } }
        .onChange(of: tab) { _, _ in minimized = false }
        .task { if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { await store.refreshCatalog() } }
        .task(id: store.data.dividends.map(\.id)) { await DividendReminders.syncIfEnabled(store.data.dividends) }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--tab"), args.indices.contains(i + 1), let value = Int(args[i + 1]) { tab = value }
        }
        .alert("ETF 袋著走", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("知道了", role: .cancel) { store.message = nil } } message: { Text(store.message ?? "") }
    }
    private func stack<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack { content().appRoutes() }
            .id(resets[index])
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) }
            .toolbar(.hidden, for: .tabBar)
            .tag(index)
    }
}

struct HomeView: View {
    @EnvironmentObject var store: PortfolioStore
    @Binding var tab: Int
    @State private var range = ChartRange.year
    @State private var overview = false
    @AppStorage("hideAmounts") private var hidden = false
    @AppStorage("readNotices") private var readNotices = ""
    private var summary: PortfolioSummary { PortfolioSummary(store.data) }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 11 ? "早安！" : (hour < 18 ? "午安！" : "晚安！")
    }
    private var nextMonthAmount: Double {
        guard let next = Calendar.current.date(byAdding: .month, value: 1, to: Date()) else { return 0 }
        return store.data.dividends.filter { $0.status != .paid && Calendar.current.isDate($0.date, equalTo: next, toGranularity: .month) }.reduce(0) { $0 + $1.amount }
    }
    var body: some View {
        Page {
            header
            DemoBar()
            hero
            HStack(spacing: 10) {
                NavigationLink(value: AppRoute.monthDividends(next: false)) { iconTile("本月已領配息", value: summary.monthPaid, icon: "dollarsign", colors: [Color(red: 1, green: 0.78, blue: 0.3), Color(red: 0.96, green: 0.64, blue: 0.06)]) }
                NavigationLink(value: AppRoute.monthDividends(next: true)) { iconTile("下月預估配息", value: nextMonthAmount, icon: "calendar", colors: [Color(red: 0.37, green: 0.64, blue: 1), Palette.blue]) }
            }.buttonStyle(.plain)
            trend
            if store.data.holdings.isEmpty {
                NavigationLink(value: AppRoute.holdingForm(id: nil, symbol: nil)) { PrimaryButtonLabel(title: "新增第一筆持有") }.buttonStyle(.plain).accessibilityIdentifier("home-add-holding")
            }
            reminders
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refresh() }
        .navigationDestination(isPresented: $overview) { OverviewView() }
    }
    private var header: some View {
        let unread = AppNotice.all(store).filter { !readNotices.split(separator: ",").map(String.init).contains($0.id) }.count
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.title2.bold()).foregroundStyle(Palette.ink)
                Text("今天也是存股的好日子 😊").font(.headline).foregroundStyle(Palette.ink)
            }
            Spacer()
            NavigationLink(value: AppRoute.notices) {
                Image(systemName: "bell").font(.title3).foregroundStyle(Palette.ink).frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) { if unread > 0 { Circle().fill(Palette.red).frame(width: 9, height: 9).offset(x: -8, y: 8) } }
            }.accessibilityLabel(unread > 0 ? "通知中心，\(unread) 則未讀" : "通知中心")
            NavigationLink(value: AppRoute.settings) { Image(systemName: "gearshape").font(.title3).foregroundStyle(Palette.ink).frame(width: 40, height: 40) }.accessibilityLabel("設定")
        }.padding(.top, 6)
    }
    private var hero: some View {
        let s = summary
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我的資產總覽").font(.subheadline.weight(.semibold))
                Text("(TWD)").font(.caption).opacity(0.8)
                Spacer()
                Button { hidden.toggle() } label: { Image(systemName: hidden ? "eye.slash" : "eye") }.accessibilityLabel(hidden ? "顯示金額" : "隱藏金額")
            }
            Text(shown(s.marketValue.map(money) ?? "—", hidden: hidden))
                .font(.system(size: 38, weight: .heavy, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("portfolio-value")
            if let unrealized = s.unrealized, let percent = s.unrealizedPercent {
                Text(shown("\(unrealized >= 0 ? "▲" : "▼") \(signed(unrealized)) (\(percentText(percent)))", hidden: hidden)).font(.headline).monospacedDigit()
                    .foregroundStyle(unrealized > 0 ? Palette.heroUp : (unrealized < 0 ? Palette.heroDown : Color.white))
            } else {
                Text(store.data.holdings.isEmpty ? "新增持有後，這裡會整理你的資產" : "取得全部持有的台幣報價後，即可估算市值").font(.subheadline).opacity(0.9)
            }
            HStack(spacing: 0) {
                heroCell("總成本", shown(money(s.cost), hidden: hidden), detail: nil, tint: Palette.ink)
                Divider().frame(height: 34)
                heroCell("未實現損益", s.unrealized.map { shown(signed($0), hidden: hidden) } ?? "—", detail: s.unrealizedPercent.map { shown("(\(percentText($0)))", hidden: hidden) }, tint: s.unrealized.map(Palette.trend) ?? Palette.ink)
                Divider().frame(height: 34)
                heroCell("累計配息", shown(money(s.paidTotal), hidden: hidden), detail: nil, tint: Palette.ink)
            }
            .padding(.vertical, 10)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(18)
        .foregroundStyle(.white)
        .background(alignment: .topTrailing) { HeroDeco().padding(.top, 54).padding(.trailing, 16) }
        .background(Palette.hero, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: Palette.blue.opacity(0.28), radius: 14, y: 6)
        .contentShape(Rectangle())
        .onTapGesture { overview = true }
        .accessibilityAction(named: "看資產總覽") { overview = true }
    }
    private func heroCell(_ title: String, _ value: String, detail: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(tint).minimumScaleFactor(0.6).lineLimit(1)
            if let detail { Text(detail).font(.caption2.weight(.semibold)).foregroundStyle(tint) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
    }
    private func iconTile(_ title: String, value: Double, icon: String, colors: [Color]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.headline.bold()).foregroundStyle(.white).frame(width: 38, height: 38)
                .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(Palette.muted)
                Text(shown(money(value), hidden: hidden)).font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Palette.blue.opacity(0.06), radius: 10, y: 3)
    }
    private var trend: some View {
        let points = TrendMath.slice(TrendMath.portfolio(store.data), range)
        let change = points.count >= 2 ? (points.last!.value / max(points.first!.value, 0.000001) - 1) * 100 : nil
        return Card(padding: 14) {
            HStack {
                Text("資產走勢").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                if let change { Text(range == .all ? "全部期間" : "近\(range.rawValue)").font(.caption).foregroundStyle(Palette.muted); Text(percentText(change)).font(.caption.bold()).monospacedDigit().foregroundStyle(Palette.trend(change)) }
            }
            RangeChips(options: [.week, .month, .quarter, .year, .all], selection: $range).padding(.vertical, 10)
            if points.count >= 2 {
                ValueChart(points: points, showAxes: true, height: 130)
            } else {
                Text("每檔持有都取得報價與歷史走勢後（ETF 詳情 › 走勢），這裡會顯示目前持股的市值變化。").font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }
    private var reminders: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let records = store.data.dividends.filter { $0.status != .paid && $0.date >= today }.sorted { $0.date < $1.date }.prefix(3)
        let official = store.officialForHoldings().filter { $0.event.ex >= DataChecks.day() }.prefix(max(0, 3 - records.count))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeading(title: "近期配息提醒")
                NavigationLink(value: AppRoute.recentDividends) { HStack(spacing: 2) { Text("查看全部"); Image(systemName: "chevron.right") }.font(.caption.bold()) }
            }
            Card(padding: 12) {
                if records.isEmpty && official.isEmpty {
                    Text("記錄已公告或預估的配息，或持有有官方配息公告的 ETF，就能在這裡提前看到。").font(.subheadline).foregroundStyle(Palette.muted).padding(4)
                }
                ForEach(Array(records)) { item in
                    NavigationLink(value: AppRoute.dividendDetail(item.id)) {
                        reminderRow(date: item.date, symbol: item.symbol, subtitle: item.status == .estimated ? "預估配息" : "已公告配息", amount: item.amount)
                    }.buttonStyle(.plain)
                }
                ForEach(Array(official.enumerated()), id: \.offset) { _, entry in
                    NavigationLink(value: AppRoute.dividendForm(id: nil, symbol: entry.symbol, officialEx: entry.event.ex)) {
                        reminderRow(date: DataChecks.date(entry.event.pay.isEmpty ? entry.event.ex : entry.event.pay) ?? Date(), symbol: entry.symbol, subtitle: "官方公告・\(entry.event.ex.suffix(5).replacingOccurrences(of: "-", with: "/")) 除息", amount: entry.event.amount.map { $0 * entry.shares })
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func reminderRow(date: Date, symbol: String, subtitle: String, amount: Double?) -> some View {
        HStack(spacing: 10) {
            DateBox(date: date)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) { Text(symbol).font(.subheadline.bold()); Text(store.name(for: symbol)).font(.subheadline).lineLimit(1) }.foregroundStyle(Palette.ink)
                Text(subtitle).font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 6)
            Text(amount.map { shown(money($0), hidden: hidden) } ?? "待公布").font(amount == nil ? .caption : .subheadline.bold()).monospacedDigit().foregroundStyle(amount == nil ? Palette.muted : Palette.ink)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
