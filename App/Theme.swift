import SwiftUI
import Charts

enum Palette {
    static let blue = Color(red: 0.12, green: 0.42, blue: 1.0)
    static let deepBlue = Color(red: 0.07, green: 0.31, blue: 0.88)
    static let ink = Color(red: 0.06, green: 0.12, blue: 0.24)
    static let muted = Color(red: 0.42, green: 0.48, blue: 0.60)
    static let background = Color(red: 0.95, green: 0.97, blue: 1.0)
    static let red = Color(red: 0.90, green: 0.22, blue: 0.27)
    static let green = Color(red: 0.05, green: 0.62, blue: 0.42)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.10)
    static let pink = Color(red: 0.93, green: 0.33, blue: 0.52)
    static let purple = Color(red: 0.49, green: 0.33, blue: 0.96)
    // Taiwan market convention: rising prices are red, falling prices are green.
    static let up = red
    static let down = green
    static func trend(_ value: Double) -> Color { value > 0 ? up : (value < 0 ? down : muted) }
    static func strategy(_ value: Strategy) -> Color { switch value { case .saving: return pink; case .income: return green; case .risk: return purple; case .unclassified: return muted } }
    static func status(_ value: DividendStatus) -> Color { switch value { case .paid: return green; case .announced: return blue; case .estimated: return orange } }
    static let hero = LinearGradient(colors: [Color(red: 0.27, green: 0.58, blue: 1.0), Color(red: 0.08, green: 0.33, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let page = LinearGradient(colors: [Color(red: 0.90, green: 0.94, blue: 1.0), Color(red: 0.97, green: 0.98, blue: 1.0)], startPoint: .top, endPoint: .bottom)
}

func money(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
func decimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
func priceText(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
func signed(_ value: Double, _ format: (Double) -> String = money) -> String { (value > 0 ? "+" : (value < 0 ? "-" : "")) + format(abs(value)) }
func percentText(_ value: Double) -> String { signed(value, decimal) + "%" }
func shown(_ text: String, hidden: Bool) -> String { hidden ? "＊＊＊＊" : text }
func monthDay(_ date: Date) -> String { "\(Calendar.current.component(.month, from: date))/\(Calendar.current.component(.day, from: date))" }

extension Strategy {
    var emoji: String { switch self { case .saving: return "🐷"; case .income: return "🖨️"; case .risk: return "🎰"; case .unclassified: return "🏷️" } }
    var tagline: String { switch self { case .saving: return "長期累積"; case .income: return "配息現金流"; case .risk: return "高風險機會"; case .unclassified: return "尚未分類" } }
    var explanation: String {
        switch self {
        case .saving: return "追蹤大型權值或市值指數，成分股分散，適合長期定期投入累積。仍會隨股市漲跌波動。"
        case .income: return "名稱屬高股息／高息類型，著重配息現金流。配息可能來自收益或本金，配息率不等於報酬率。"
        case .risk: return "槓桿或反向型，每日重設、波動放大，較適合短期且需嚴格控管部位。"
        case .unclassified: return "尚未符合自動分類規則；新增持有時可自行選擇策略。"
        }
    }
    static let basis = "依 ETF 名稱自動整理：含「正2／反1／槓桿／反向」為老虎機；含「高股息／優息／高息」為印鈔機；元大台灣50、富邦台50、元大富櫃50 為存錢筒；其餘待分類。分類是整理策略的方式，不是收益保證。"
}
extension Fund {
    var isActive: Bool { id.hasSuffix("A") || name.contains("主動") || (fundType ?? "").contains("主動") }
    var managementStyle: String { isActive ? "主動式" : "被動式" }
    var marketName: String { market == "TPEx" ? "上櫃" : (market == "TWSE" ? "上市" : "示範") }
    var assetClass: String {
        let type = fundType ?? ""
        if type.contains("債") || name.contains("債") { return "債券" }
        if type.contains("槓桿") || strategy == .risk { return "槓桿／反向" }
        if type.contains("期貨") { return "期貨" }
        if type.contains("國外") { return "海外股票" }
        if type.contains("國內") { return "台股" }
        return "其他"
    }
    static let assetClasses = ["台股", "海外股票", "債券", "槓桿／反向", "期貨", "其他"]
}
extension Quote {
    var changeAmount: Double? {
        if let change { return change }
        guard let percent = changePercent, percent > -100 else { return nil }
        return price * percent / (100 + percent)
    }
}
extension PortfolioStore {
    func name(for symbol: String) -> String {
        funds.first { $0.id == symbol }?.name ?? data.holdings.first { $0.symbol == symbol }?.name ?? symbol
    }
}

struct PortfolioSummary {
    let cost: Double
    let marketValue: Double?
    let paidTotal: Double
    let monthPaid: Double
    let monthPending: Double
    let symbolCount: Int
    init(_ data: Portfolio, month: Date = Date()) {
        let inMonth = data.dividends.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
        cost = data.cost
        marketValue = data.marketValue
        paidTotal = data.dividends.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }
        monthPaid = inMonth.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }
        monthPending = inMonth.filter { $0.status != .paid }.reduce(0) { $0 + $1.amount }
        symbolCount = Set(data.holdings.map(\.symbol)).count
    }
    var unrealized: Double? { marketValue.map { $0 - cost } }
    var unrealizedPercent: Double? {
        guard let unrealized, cost > 0 else { return nil }
        return unrealized / cost * 100
    }
    var totalReturn: Double? { unrealized.map { $0 + paidTotal } }
    var totalReturnPercent: Double? {
        guard let totalReturn, cost > 0 else { return nil }
        return totalReturn / cost * 100
    }
}

struct ValuePoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}
enum ChartRange: String, CaseIterable, Identifiable {
    case week = "1週", month = "1月", quarter = "3月", year = "1年", fiveYears = "5年", all = "全部"
    var id: String { rawValue }
    func start(from end: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -7, to: end)
        case .month: return calendar.date(byAdding: .month, value: -1, to: end)
        case .quarter: return calendar.date(byAdding: .month, value: -3, to: end)
        case .year: return calendar.date(byAdding: .year, value: -1, to: end)
        case .fiveYears: return calendar.date(byAdding: .year, value: -5, to: end)
        case .all: return nil
        }
    }
}
enum TrendMath {
    private static let parser: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Taipei"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    static func points(_ history: PriceHistory) -> [ValuePoint] {
        history.points.compactMap { point in parser.date(from: point.date).map { ValuePoint(date: $0, value: point.close) } }
    }
    /// Current share counts valued at each adjusted close. Only days on which every held ETF has a price are kept,
    /// and nothing is shown unless every holding has a TWD quote and a stored history.
    static func portfolio(_ data: Portfolio) -> [ValuePoint] {
        var shares: [String: Double] = [:]
        for holding in data.holdings { shares[holding.symbol, default: 0] += holding.shares }
        guard !shares.isEmpty else { return [] }
        var totals: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for (symbol, quantity) in shares {
            guard data.quotes[symbol]?.isTWD == true, let history = data.histories?[symbol] else { return [] }
            for point in history.points {
                totals[point.date, default: 0] += quantity * point.close
                counts[point.date, default: 0] += 1
            }
        }
        var result: [ValuePoint] = []
        for (day, value) in totals where counts[day] == shares.count {
            if let date = parser.date(from: day) { result.append(ValuePoint(date: date, value: value)) }
        }
        return result.sorted { $0.date < $1.date }
    }
    static func slice(_ points: [ValuePoint], _ range: ChartRange) -> [ValuePoint] {
        guard let last = points.last, let start = range.start(from: last.date) else { return points }
        return points.filter { $0.date >= start }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Palette.blue.opacity(0.07), radius: 12, y: 4)
    }
}
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { Palette.page.ignoresSafeArea() }
    }
}
struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Capsule().fill(Palette.blue).frame(width: 4, height: 16)
                Text(title).font(.headline).foregroundStyle(Palette.ink)
            }
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Palette.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct StrategyPill: View {
    let strategy: Strategy
    var body: some View {
        Text(strategy.rawValue).font(.caption2.bold()).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(Palette.strategy(strategy))
            .background(Palette.strategy(strategy).opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }
}
struct StatusPill: View {
    let status: DividendStatus
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Palette.status(status)).frame(width: 6, height: 6)
            Text(status.rawValue).font(.caption2.bold())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(Palette.status(status))
        .background(Palette.status(status).opacity(0.12), in: Capsule())
    }
}
/// "▲ +1.20 (+0.65%)" in Taiwan market colours; nothing is invented when the quote has no change data.
struct QuoteChange: View {
    let quote: Quote?
    var font: Font = .caption
    var body: some View {
        if let quote, let percent = quote.changePercent {
            let arrow = percent > 0 ? "▲" : (percent < 0 ? "▼" : "－")
            let amount = quote.changeAmount.map { signed($0, priceText) } ?? ""
            Text("\(arrow) \(amount) (\(percentText(percent)))")
                .font(font.weight(.semibold)).monospacedDigit().lineLimit(1)
                .foregroundStyle(Palette.trend(percent))
        } else {
            Text(quote == nil ? "未取得報價" : "無漲跌資料").font(font).foregroundStyle(Palette.muted)
        }
    }
}
struct SegmentBar: View {
    let items: [String]
    @Binding var selection: Int
    var pill = false
    var body: some View {
        HStack(spacing: pill ? 4 : 0) {
            ForEach(items.indices, id: \.self) { index in
                Button { withAnimation(.snappy) { selection = index } } label: { label(index) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(pill ? 4 : 0)
        .background(pill ? Palette.blue.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
    }
    @ViewBuilder private func label(_ index: Int) -> some View {
        let active = selection == index
        if pill {
            Text(items[index]).font(.subheadline.weight(active ? .bold : .medium))
                .foregroundStyle(active ? Palette.blue : Palette.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(active ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
        } else {
            VStack(spacing: 7) {
                Text(items[index]).font(.subheadline.weight(active ? .bold : .medium))
                    .foregroundStyle(active ? Palette.blue : Palette.muted)
                Capsule().fill(active ? Palette.blue : Color.clear).frame(width: 26, height: 3)
            }
            .frame(maxWidth: .infinity).padding(.top, 4)
            .contentShape(Rectangle())
        }
    }
}
struct RangeChips: View {
    let options: [ChartRange]
    @Binding var selection: ChartRange
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button { selection = option } label: {
                    Text(option.rawValue).font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .foregroundStyle(selection == option ? .white : Palette.muted)
                        .background(selection == option ? Palette.blue : Color.clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
    }
}
struct ValueChart: View {
    let points: [ValuePoint]
    var showAxes = false
    var height: CGFloat = 150
    var body: some View {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.12, abs(high) * 0.002, 0.01)
        let base = low - pad
        Chart(points) { point in
            AreaMark(x: .value("日期", point.date), yStart: .value("基準", base), yEnd: .value("數值", point.value))
                .foregroundStyle(LinearGradient(colors: [Palette.blue.opacity(0.26), Palette.blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("日期", point.date), y: .value("數值", point.value))
                .foregroundStyle(Palette.blue)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: base...(high + pad))
        .chartXAxis(showAxes ? .automatic : .hidden)
        .chartYAxis(showAxes ? .automatic : .hidden)
        .frame(height: height)
    }
}
struct StatTile: View {
    let title: String
    let value: String
    var icon: String? = nil
    var tint: Color = Palette.blue
    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon).font(.headline).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(tint.gradient, in: Circle())
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(Palette.muted)
                Text(value).font(.title3.bold()).monospacedDigit().foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Palette.blue.opacity(0.06), radius: 10, y: 3)
    }
}
struct ToolRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.title3).foregroundStyle(Palette.blue)
                .frame(width: 42, height: 42).background(Palette.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(subtitle).font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
        }.padding(.vertical, 8)
    }
}
struct PrimaryButtonLabel: View {
    let title: String
    var icon = "plus"
    var body: some View {
        Label(title, systemImage: icon).font(.headline)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(Palette.hero, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Palette.blue.opacity(0.3), radius: 10, y: 4)
    }
}
