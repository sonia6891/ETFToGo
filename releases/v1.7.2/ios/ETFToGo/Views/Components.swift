import SwiftUI

func money(_ value: Decimal?) -> String {
    guard let value else { return "—" }
    let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "TWD"; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
    return f.string(from: NSDecimalNumber(decimal: value)) ?? "—"
}
func decimalInput(_ raw: String) -> Decimal? {
    let value = raw.trimmingCharacters(in: .whitespaces)
    guard value.range(of: "^[0-9]+(?:\\.[0-9]{1,8})?$", options: .regularExpression) != nil else { return nil }
    return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
}
extension InvestmentRole {
    var color: Color { switch self { case .piggyBank: return .teal; case .printer: return .blue; case .slotMachine: return .orange } }
}
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(alignment: .leading, spacing: 14) { content }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(.blue.opacity(0.1))) }
}
struct RoleBadge: View {
    let result: Classification
    var body: some View {
        Label(result.role?.title ?? "待核驗", systemImage: result.role?.symbol ?? "questionmark.circle")
            .font(.caption.bold()).foregroundStyle(result.role?.color ?? .secondary).padding(.horizontal, 9).padding(.vertical, 6).background((result.role?.color ?? .gray).opacity(0.1), in: Capsule())
    }
}
struct ETFRow: View {
    let etf: ETF
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(etf.code).font(.subheadline.monospaced().bold()).foregroundStyle(.blue)
                Text(etf.name).font(.headline)
                Text(etf.market == "TWSE" ? "上市" : "上櫃").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            RoleBadge(result: RoleClassifier.classify(etf))
        }.padding(.vertical, 6)
    }
}
struct InlineError: View {
    let text: String?
    var body: some View { if let text { Text(text).font(.footnote).foregroundStyle(.red).accessibilityLabel("錯誤：\(text)") } }
}
struct RootView: View {
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(tab: $tab) }.tabItem { Label("首頁", systemImage: "house") }.tag(0)
            NavigationStack { ExploreView() }.tabItem { Label("找 ETF", systemImage: "magnifyingglass") }.tag(1)
            NavigationStack { PortfolioView() }.tabItem { Label("持有", systemImage: "wallet.pass") }.tag(2)
            NavigationStack { DividendsView() }.tabItem { Label("配息", systemImage: "calendar") }.tag(3)
            NavigationStack { SettingsView() }.tabItem { Label("更多", systemImage: "ellipsis") }.tag(4)
        }
    }
}
