import SwiftUI

@main struct ETFToGoApp: App {
    @StateObject private var store: PortfolioStore
    init() {
        let args = ProcessInfo.processInfo.arguments
        let testURL = args.contains("--ui-testing") ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ETFToGo/ui-test.json") : nil
        _store = StateObject(wrappedValue: PortfolioStore(url: testURL, demo: args.contains("--demo"), reset: args.contains("--reset")))
    }
    var body: some Scene { WindowGroup { RootView().environmentObject(store).preferredColorScheme(.light) } }
}
struct RootView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(tab: $tab) }.tabItem { Label("首頁", systemImage: "house.fill") }.tag(0)
            NavigationStack { DiscoverView() }.tabItem { Label("探索", systemImage: "magnifyingglass") }.tag(1)
            NavigationStack { HoldingsView() }.tabItem { Label("持有", systemImage: "bag") }.tag(2)
            NavigationStack { DividendsView() }.tabItem { Label("配息", systemImage: "bell") }.tag(3)
            NavigationStack { ToolsView() }.tabItem { Label("工具", systemImage: "line.3.horizontal") }.tag(4)
        }
        .tint(Palette.blue)
        .task { if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { await store.refreshCatalog() } }
        .task(id: store.data.dividends.map(\.id)) { await DividendReminders.syncIfEnabled(store.data.dividends) }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--tab"), args.indices.contains(i + 1), let value = Int(args[i + 1]) { tab = value }
        }
        .alert("ETF 袋著走", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("知道了", role: .cancel) { store.message = nil } } message: { Text(store.message ?? "") }
    }
}
enum HomeRoute: Hashable { case settings, reminders }

struct HomeView: View {
    @EnvironmentObject var store: PortfolioStore
    @Binding var tab: Int
    @State private var add = false
    @State private var range = ChartRange.month
    @AppStorage("hideAmounts") private var hidden = false
    private var summary: PortfolioSummary { PortfolioSummary(store.data) }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 11 ? "早安！" : (hour < 18 ? "午安！" : "晚安！")
    }
    private var upcoming: [Dividend] {
        let today = Calendar.current.startOfDay(for: Date())
        let future = store.data.dividends.filter { $0.date >= today }.sorted { $0.date < $1.date }
        if !future.isEmpty { return Array(future.prefix(3)) }
        return Array(store.data.dividends.sorted { $0.date > $1.date }.prefix(3))
    }
    var body: some View {
        Page {
            header
            if store.isDemo { Label("介面預覽・金額及報價均為示範", systemImage: "info.circle").font(.caption).foregroundStyle(Palette.blue) }
            hero
            HStack(spacing: 10) {
                StatTile(title: "本月已領", value: shown(money(summary.monthPaid), hidden: hidden))
                StatTile(title: "待入帳", value: shown(money(summary.monthPending), hidden: hidden))
                StatTile(title: "持有檔數", value: "\(summary.symbolCount)")
            }
            trend
            quickActions
            if store.data.holdings.isEmpty {
                Button { add = true } label: { PrimaryButtonLabel(title: "新增第一筆持有") }.buttonStyle(.plain).accessibilityIdentifier("home-add-holding")
            }
            reminders
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refresh() }
        .sheet(isPresented: $add) { HoldingEditor() }
        .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .settings: SettingsView()
            case .reminders: ReminderCenterView()
            }
        }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.title2.bold()).foregroundStyle(Palette.ink)
                Text("今天也是存股的好日子 😊").font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink.opacity(0.8))
            }
            Spacer()
            NavigationLink(value: HomeRoute.reminders) { headerIcon("bell") }.accessibilityLabel("提醒中心")
            NavigationLink(value: HomeRoute.settings) { headerIcon("gearshape") }.accessibilityLabel("設定")
        }.padding(.top, 6)
    }
    private func headerIcon(_ name: String) -> some View {
        Image(systemName: name).font(.title3).foregroundStyle(Palette.ink).frame(width: 40, height: 40)
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
                .font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("portfolio-value")
            if let total = s.totalReturn, let percent = s.totalReturnPercent {
                HStack(spacing: 6) {
                    Image(systemName: total >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.caption2)
                    Text(shown("\(signed(total)) (\(percentText(percent)))", hidden: hidden)).font(.subheadline.bold()).monospacedDigit()
                    Text("含息報酬").font(.caption).opacity(0.8)
                }
            } else {
                Text(store.data.holdings.isEmpty ? "新增持有後，這裡會整理你的資產" : "取得全部持有的台幣報價後，即可估算市值").font(.subheadline).opacity(0.85)
            }
            HStack(spacing: 10) {
                heroTile("未實現損益", icon: "chart.line.uptrend.xyaxis", value: s.unrealized.map { shown(signed($0), hidden: hidden) } ?? "—", detail: s.unrealizedPercent.map { "(\(percentText($0)))" }, tint: s.unrealized.map(Palette.trend) ?? Palette.ink)
                heroTile("累計領息", icon: "banknote", value: shown(money(s.paidTotal), hidden: hidden), detail: nil, tint: Palette.ink)
            }
            if !store.data.quotes.isEmpty { Text(store.isDemo ? "示範報價，非即時市場資訊" : "依已取得報價估算・不含交易費用・下拉可更新報價").font(.caption2).opacity(0.75) }
        }
        .padding(18)
        .foregroundStyle(.white)
        .background(Palette.hero, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: Palette.blue.opacity(0.28), radius: 14, y: 6)
    }
    private func heroTile(_ title: String, icon: String, value: String, detail: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(tint).minimumScaleFactor(0.6).lineLimit(1)
            if let detail { Text(detail).font(.caption2.weight(.semibold)).foregroundStyle(tint) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
    private var trend: some View {
        let points = TrendMath.slice(TrendMath.portfolio(store.data), range)
        return Card(padding: 14) {
            if points.count >= 2 {
                ValueChart(points: points, height: 110)
                RangeChips(options: [.week, .month, .quarter, .year, .all], selection: $range).padding(.top, 10)
                Text("以目前股數 × 還原收盤價估算，不是帳戶實際歷史。").font(.caption2).foregroundStyle(Palette.muted).padding(.top, 8)
            } else {
                Label("資產走勢", systemImage: "chart.xyaxis.line").font(.subheadline.bold()).foregroundStyle(Palette.ink)
                Text("每檔持有都取得報價與歷史走勢後（ETF 詳情 › 走勢），這裡會顯示目前持股的市值變化。").font(.caption).foregroundStyle(Palette.muted).padding(.top, 6)
            }
        }
    }
    private var quickActions: some View {
        HStack(spacing: 0) {
            quick("ETF 探索", icon: "magnifyingglass", color: Palette.green) { tab = 1 }
            quick("我的持有", icon: "star.fill", color: Palette.orange) { tab = 2 }
            quick("配息月曆", icon: "calendar", color: Palette.pink) { tab = 3 }
            quick("試算工具", icon: "square.grid.2x2.fill", color: Palette.blue) { tab = 4 }
        }
    }
    private func quick(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(color.gradient, in: Circle())
                    .shadow(color: color.opacity(0.35), radius: 6, y: 3)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }
    private var reminders: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeading(title: "近期配息提醒")
                Button { tab = 3 } label: { HStack(spacing: 2) { Text("查看全部"); Image(systemName: "chevron.right") }.font(.caption) }
            }
            Card(padding: 14) {
                if upcoming.isEmpty {
                    Text("記錄已公告或預估的配息，就能在這裡提前看到入帳日。").font(.subheadline).foregroundStyle(Palette.muted)
                } else {
                    ForEach(upcoming) { item in
                        HStack(spacing: 10) {
                            Circle().fill(Palette.status(item.status).opacity(0.15)).frame(width: 26, height: 26)
                                .overlay(Circle().fill(Palette.status(item.status)).frame(width: 9, height: 9))
                            Text(item.symbol).font(.subheadline.bold()).foregroundStyle(Palette.ink)
                            Text(store.name(for: item.symbol)).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(monthDay(item.date)).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink)
                            StatusPill(status: item.status)
                        }.padding(.vertical, 6)
                    }
                }
            }
        }
    }
}
