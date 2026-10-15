import Foundation
import Security
import SwiftUI

enum Strategy: String, Codable, CaseIterable, Identifiable {
    case saving = "存錢筒", income = "印鈔機", risk = "老虎機", unclassified = "待分類"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .saving: return "leaf"; case .income: return "banknote"; case .risk: return "bolt"; case .unclassified: return "tag" }
    }
    var subtitle: String {
        switch self { case .saving: return "長期累積"; case .income: return "關注配息"; case .risk: return "高波動策略"; case .unclassified: return "自行選擇策略" }
    }
}
struct Fund: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var strategy: Strategy
    var market: String? = nil
    var fullName: String? = nil
    var fundType: String? = nil
    var listingDate: String? = nil
    // Demo-only catalogue; the normal app uses the validated TWSE + TPEx catalogue.
    static let starters: [Fund] = [
        .init(id: "0050", name: "元大台灣50", strategy: .saving),
        .init(id: "006208", name: "富邦台50", strategy: .saving),
        .init(id: "0056", name: "元大高股息", strategy: .income),
        .init(id: "00878", name: "國泰永續高股息", strategy: .income),
        .init(id: "00919", name: "群益台灣精選高息", strategy: .income),
        .init(id: "00631L", name: "元大台灣50正2", strategy: .risk)
    ]
}
struct Holding: Identifiable, Codable {
    var id = UUID()
    var symbol: String
    var name: String
    var shares: Double
    var unitCost: Double
    var broker: String
    var strategy: Strategy
    var sourceAccount: String? = nil
    var cost: Double { shares * unitCost }
    func validate() throws {
        guard !symbol.isEmpty, !name.isEmpty, shares.isFinite, shares > 0,
              shares <= 1e10, unitCost.isFinite, unitCost >= 0, unitCost <= 1e9,
              cost.isFinite, !broker.isEmpty, broker.count <= 120, symbol.count <= 20, name.count <= 120 else { throw StoreError.invalidHolding }
    }
}
enum TradeAction: String, Codable, CaseIterable { case buy = "買進", adjust = "調整", remove = "移除", brokerImport = "匯入" }
/// A change the user made to a holding in this app; not a broker fill report.
struct Trade: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var action: TradeAction
    var symbol: String
    var name: String
    var shares: Double
    var unitCost: Double
    var broker: String
    var isValid: Bool {
        !symbol.isEmpty && symbol.count <= 20 && name.count <= 120 && broker.count <= 120
            && shares.isFinite && shares >= 0 && shares <= 1e10 && unitCost.isFinite && unitCost >= 0 && unitCost <= 1e9
    }
    init(id: UUID = UUID(), date: Date = Date(), action: TradeAction, holding: Holding) {
        self.id = id; self.date = date; self.action = action
        symbol = holding.symbol; name = holding.name; shares = holding.shares; unitCost = holding.unitCost; broker = holding.broker
    }
}
enum DividendStatus: String, Codable, CaseIterable { case paid = "已入帳", announced = "已公告", estimated = "預估" }
struct Dividend: Identifiable, Codable {
    var id = UUID()
    var symbol: String
    var date: Date
    var amount: Double
    var status: DividendStatus
}
struct Quote: Codable {
    var symbol: String
    var price: Double
    var changePercent: Double?
    var date: String
    var fetchedAt: Date
    var currency: String? = nil
    var change: Double? = nil
    var open: Double? = nil
    var high: Double? = nil
    var low: Double? = nil
    /// Trading volume in lots (張), as reported by Fugle intraday quotes.
    var volume: Double? = nil
    var isTWD: Bool { currency == "TWD" || (currency == nil && Fund.starters.contains { $0.id == symbol }) }
    var isValid: Bool {
        price.isFinite && price > 0 && [change, changePercent].allSatisfy { $0?.isFinite ?? true }
            && [open, high, low, volume].allSatisfy { value in value.map { $0.isFinite && $0 >= 0 } ?? true }
    }
}
struct Portfolio: Codable {
    var schema = 1
    var holdings: [Holding] = []
    var dividends: [Dividend] = []
    var favorites: Set<String> = []
    var quotes: [String: Quote] = [:]
    var comparison: [String]? = nil
    var legacyPlan: LegacyPlan? = nil
    var legacyPrices: [String: LegacyPrice]? = nil
    var legacyDividends: [String: BackupImport.OldDividend]? = nil
    var components: [String: ComponentSnapshot]? = nil
    var histories: [String: PriceHistory]? = nil
    var fees: [String: FeeRecord]? = nil
    /// Absent in files written before the trade log existed.
    var trades: [Trade]? = nil
    var cost: Double { holdings.reduce(0) { $0 + $1.cost } }
    /// Appends to the trade log, keeping the most recent 5,000 entries.
    mutating func log(_ action: TradeAction, _ holding: Holding) {
        var list = trades ?? []
        list.append(Trade(action: action, holding: holding))
        if list.count > 5000 { list.removeFirst(list.count - 5000) }
        trades = list
    }
    var marketValue: Double? {
        guard !holdings.isEmpty, holdings.allSatisfy({ quotes[$0.symbol]?.isTWD == true }) else { return nil }
        return holdings.reduce(0) { $0 + $1.shares * quotes[$1.symbol]!.price }
    }
    static func decodeBackup(_ data: Data) throws -> Portfolio {
        guard data.count <= 5_000_000 else { throw StoreError.unsupportedBackup }
        let value = try JSONDecoder().decode(Portfolio.self, from: data)
        guard value.schema == 1, value.holdings.count <= 10000, value.dividends.count <= 50000, value.favorites.count <= 2000 else { throw StoreError.unsupportedBackup }
        for holding in value.holdings { try holding.validate() }
        guard Set(value.holdings.map(\.id)).count == value.holdings.count,
              Set(value.dividends.map(\.id)).count == value.dividends.count,
              value.dividends.allSatisfy({ !$0.symbol.isEmpty && $0.amount.isFinite && $0.amount >= 0 }),
              value.quotes.allSatisfy({ $0.key == $0.value.symbol && $0.value.isValid }),
              (value.trades?.count ?? 0) <= 50000,
              Set((value.trades ?? []).map(\.id)).count == (value.trades?.count ?? 0),
              (value.trades ?? []).allSatisfy(\.isValid)
        else { throw StoreError.unsupportedBackup }
        try value.legacyPlan?.validate()
        for d in (value.legacyDividends ?? [:]).values { try d.validate() }
        for (code, snapshot) in value.components ?? [:] { guard code == snapshot.symbol else { throw StoreError.unsupportedBackup }; try snapshot.validate() }
        for (code, history) in value.histories ?? [:] { guard code == history.symbol else { throw StoreError.unsupportedBackup }; try history.validate() }
        for (code, fee) in value.fees ?? [:] { guard code == fee.symbol else { throw StoreError.unsupportedBackup }; try fee.validate() }
        guard (value.comparison?.count ?? 0) <= 3, (value.comparison ?? []).allSatisfy(DataChecks.code),
              (value.legacyPrices ?? [:]).values.allSatisfy({ DataChecks.code($0.symbol) && $0.price.isFinite && $0.price >= 0 && DataChecks.date($0.date) != nil }) else { throw StoreError.unsupportedBackup }
        return value
    }
    static var demo: Portfolio {
        var value = Portfolio()
        value.holdings = [
            .init(symbol: "0050", name: "元大台灣50", shares: 2000, unitCost: 50, broker: "富邦證券", strategy: .saving),
            .init(symbol: "00878", name: "國泰永續高股息", shares: 6000, unitCost: 20, broker: "富邦證券", strategy: .income),
            .init(symbol: "00919", name: "群益台灣精選高息", shares: 5000, unitCost: 22, broker: "國泰證券", strategy: .income)
        ]
        let prices: [String: Double] = ["0050": 55, "00878": 21, "00919": 22.5]
        for (symbol, price) in prices { value.quotes[symbol] = Quote(symbol: symbol, price: price, changePercent: 0.42, date: "示範資料", fetchedAt: Date()) }
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        value.dividends = [
            Dividend(symbol: "00878", date: Calendar.current.date(byAdding: .day, value: 7, to: start)!, amount: 2400, status: .paid),
            Dividend(symbol: "00919", date: Calendar.current.date(byAdding: .day, value: 19, to: start)!, amount: 3600, status: .announced)
        ]
        value.favorites = ["0050", "00878", "00919"]
        return value
    }
    /// Explicit `--demo` interface preview only; never written to the user's file.
    static var demoPreview: Portfolio {
        var value = Portfolio.demo
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        func day(_ offset: Int, months: Int = 0) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.date(byAdding: .month, value: months, to: start)!)! }
        value.dividends += [
            Dividend(symbol: "0050", date: day(21), amount: 2000, status: .estimated),
            Dividend(symbol: "00878", date: day(15, months: -3), amount: 2280, status: .paid),
            Dividend(symbol: "00919", date: day(18, months: -3), amount: 3450, status: .paid),
            Dividend(symbol: "0050", date: day(20, months: -4), amount: 1900, status: .paid)
        ]
        let moves: [String: (Double, Double)] = ["0050": (0.65, 186), "00878": (0.54, 12458), "00919": (-0.22, 8730)]
        for (symbol, move) in moves {
            guard var quote = value.quotes[symbol] else { continue }
            quote.changePercent = move.0
            quote.open = quote.price * 0.995; quote.high = quote.price * 1.004; quote.low = quote.price * 0.992; quote.volume = move.1
            value.quotes[symbol] = quote
        }
        var histories: [String: PriceHistory] = [:]
        for (index, holding) in value.holdings.enumerated() {
            guard let price = value.quotes[holding.symbol]?.price else { continue }
            var points: [PricePoint] = []
            var cursor = calendar.date(byAdding: .day, value: -400, to: Date())!
            var step = 0
            while cursor <= Date() {
                if !calendar.isDateInWeekend(cursor) {
                    let wave = sin(Double(step) / (9 + Double(index) * 3)) * 0.018
                    points.append(PricePoint(date: DataChecks.day(cursor), close: price * (0.9 + 0.1 * Double(step) / 280 + wave)))
                    step += 1
                }
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            }
            var unique: [PricePoint] = []
            for point in points where unique.last?.date != point.date { unique.append(point) }
            histories[holding.symbol] = PriceHistory(symbol: holding.symbol, adjusted: true, points: unique, fetchedDay: DataChecks.day(), source: "示範資料")
        }
        value.histories = histories
        value.trades = value.holdings.enumerated().map { index, holding in
            Trade(date: day(3 + index * 4, months: -6 + index), action: .buy, holding: holding)
        }
        if var top = value.holdings.first {
            top.shares += 1000
            value.trades?.append(Trade(date: day(10, months: -1), action: .adjust, holding: top))
        }
        return value
    }
}
enum StoreError: LocalizedError {
    case invalidHolding, unsupportedBackup, missingKey, invalidQuote, keychain(OSStatus), http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidHolding: return "請填寫代碼、名稱與券商，股數須大於 0，每股成本不可為負數。"
        case .unsupportedBackup: return "備份格式不支援或資料不完整；現有資料未變更。"
        case .missingKey: return "請先在行情連線儲存你的富果 API Key。"
        case .invalidQuote: return "行情沒有有效成交價，請稍後再試。"
        case .keychain: return "無法安全儲存金鑰，請重試。"
        case .http(let code):
            if code == 401 { return "金鑰無效或已失效，請重新確認行情金鑰。" }
            if code == 403 { return "目前方案沒有這項資料權限；成分股需要富果開發者或進階方案。已有報價會保留。" }
            if code == 429 { return "已達資料請求額度，請稍後重試；已有資料會保留。" }
            return "資料服務暫時無法使用（\(code)），保留上次成功資料。"
        }
    }
}
@MainActor final class PortfolioStore: ObservableObject {
    @Published private(set) var data = Portfolio()
    @Published var message: String?
    @Published var refreshing = false
    @Published private(set) var catalog = CatalogSnapshot.bundled()
    @Published var catalogMessage: String?
    @Published var catalogRefreshing = false
    var funds: [Fund] { isDemo ? Fund.starters : (catalog?.funds ?? []) }
    let isDemo: Bool
    private let url: URL
    init(url: URL? = nil, demo: Bool = false, reset: Bool = false) {
        isDemo = demo
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = url ?? base.appendingPathComponent("ETFToGo/portfolio.json")
        if let bytes = try? Data(contentsOf: self.url.appendingPathExtension("catalog")), let cached = try? JSONDecoder().decode(CatalogSnapshot.self, from: bytes), (try? cached.validate()) != nil { catalog = cached }
        if demo { data = .demoPreview; return }
        if reset { try? FileManager.default.removeItem(at: self.url) }
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { data = try Portfolio.decodeBackup(Data(contentsOf: self.url)) }
            catch { message = "無法讀取既有資料，原始檔已保留。請先匯出或檢查備份。"; readFailure = true }
        }
    }
    private var readFailure = false
    func commit(_ next: Portfolio) throws {
        guard !readFailure else { throw StoreError.unsupportedBackup }
        let encoded = try JSONEncoder().encode(next)
        _ = try Portfolio.decodeBackup(encoded)
        if !isDemo {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: url, options: [.atomic, .completeFileProtection])
        }
        data = next
    }
    func save(_ holding: Holding) throws {
        try holding.validate()
        var next = data
        if let i = next.holdings.firstIndex(where: { $0.id == holding.id }) {
            let old = next.holdings[i]
            next.holdings[i] = holding
            if old.symbol != holding.symbol || old.shares != holding.shares || old.unitCost != holding.unitCost || old.broker != holding.broker { next.log(.adjust, holding) }
        } else {
            next.holdings.append(holding)
            next.log(.buy, holding)
        }
        try commit(next)
    }
    func remove(_ holding: Holding) throws {
        var next = data
        guard let stored = next.holdings.first(where: { $0.id == holding.id }) else { return }
        next.holdings.removeAll { $0.id == holding.id }
        next.log(.remove, stored)
        try commit(next)
    }
    func favorite(_ symbol: String) {
        var next = data
        if next.favorites.contains(symbol) { next.favorites.remove(symbol) } else { next.favorites.insert(symbol) }
        do { try commit(next) } catch { message = error.localizedDescription }
    }
    func record(_ dividend: Dividend) throws { var next = data; next.dividends.append(dividend); try commit(next) }
    func markPaid(_ dividend: Dividend) throws {
        var next = data
        guard let i = next.dividends.firstIndex(where: { $0.id == dividend.id }) else { return }
        next.dividends[i].status = .paid
        try commit(next)
    }
    func addToComparison(_ symbol: String) {
        var list = data.comparison ?? []
        if list.contains(symbol) { message = "\(symbol) 已在比較清單，可到「工具 › 三檔比較」查看。"; return }
        if list.count >= 3 { list.removeFirst() }
        list.append(symbol)
        var next = data; next.comparison = list
        do { try commit(next); message = "已加入比較：\(list.joined(separator: "、"))。可到「工具 › 三檔比較」查看。" } catch { message = error.localizedDescription }
    }
    func removeDividend(_ dividend: Dividend) throws { var next = data; next.dividends.removeAll { $0.id == dividend.id }; try commit(next) }
    func export() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ETFToGo-backup-\(UUID().uuidString.prefix(8)).json")
        // Preserve recoverable bytes when decoding failed; never export an empty replacement.
        let bytes = readFailure ? try Data(contentsOf: url) : try JSONEncoder().encode(data)
        try bytes.write(to: file, options: .atomic)
        return file
    }
    func importBackup(_ bytes: Data) throws {
        let incoming = try BackupImport.decode(bytes)
        // Merge by stable IDs; incoming records update matches, existing unmatched records are retained.
        var next = data
        for item in incoming.holdings {
            if let i = next.holdings.firstIndex(where: { $0.id == item.id }) { next.holdings[i] = item } else { next.holdings.append(item) }
        }
        for item in incoming.dividends {
            if let i = next.dividends.firstIndex(where: { $0.id == item.id }) { next.dividends[i] = item } else { next.dividends.append(item) }
        }
        for item in incoming.trades ?? [] {
            if next.trades == nil { next.trades = [] }
            if let i = next.trades?.firstIndex(where: { $0.id == item.id }) { next.trades?[i] = item } else { next.trades?.append(item) }
        }
        next.favorites.formUnion(incoming.favorites)
        next.comparison = incoming.comparison ?? next.comparison
        next.legacyPlan = incoming.legacyPlan ?? next.legacyPlan
        next.legacyPrices = (next.legacyPrices ?? [:]).merging(incoming.legacyPrices ?? [:]) { _, new in new }
        next.legacyDividends = (next.legacyDividends ?? [:]).merging(incoming.legacyDividends ?? [:]) { _, new in new }
        next.components = (next.components ?? [:]).merging(incoming.components ?? [:]) { _, new in new }
        next.histories = (next.histories ?? [:]).merging(incoming.histories ?? [:]) { _, new in new }
        next.fees = (next.fees ?? [:]).merging(incoming.fees ?? [:]) { _, new in new }
        // Restore missing cached quotes; retain quotes already on this device.
        for (symbol, quote) in incoming.quotes where next.quotes[symbol] == nil { next.quotes[symbol] = quote }
        try saveRecovery()
        try commit(next)
    }
    func saveRecovery() throws {
        guard !readFailure else { throw StoreError.unsupportedBackup }
        if !isDemo, FileManager.default.fileExists(atPath: url.path) {
            let directory = url.deletingLastPathComponent().appendingPathComponent("Recovery")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(contentsOf: url).write(to: directory.appendingPathComponent("before-import-\(UUID().uuidString).json"), options: [.atomic, .completeFileProtection])
        }
    }
    func refreshCatalog() async {
        guard !isDemo, !catalogRefreshing else { return }
        catalogRefreshing = true; defer { catalogRefreshing = false }
        do {
            let next = try await CatalogAPI.fetch()
            if let old = catalog {
                guard next.listedDate >= old.listedDate else { throw AppDataError("來源日期比目前資料舊，未覆寫。") }
                for market in ["TWSE", "TPEx"] {
                    guard Double(next.funds.filter { $0.market == market }.count) >= Double(old.funds.filter { $0.market == market }.count) * 0.8 else { throw AppDataError("名單數量異常減少，保留原有清單。") }
                }
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url.appendingPathExtension("catalog"), options: .atomic)
            catalog = next; catalogMessage = "已更新上市與上櫃 ETF 名單。"
        } catch { catalogMessage = error.localizedDescription }
    }
    func saveComponents(_ value: ComponentSnapshot) throws { try value.validate(); var next = data; if next.components == nil { next.components = [:] }; next.components?[value.symbol] = value; try commit(next) }
    func saveHistory(_ value: PriceHistory) throws { try value.validate(); var next = data; if next.histories == nil { next.histories = [:] }; next.histories?[value.symbol] = value; try commit(next) }
    func saveFee(_ value: FeeRecord) throws { try value.validate(); var next = data; if next.fees == nil { next.fees = [:] }; next.fees?[value.symbol] = value; try commit(next) }
    func refresh(symbols: [String]? = nil) async {
        if isDemo { message = "這是介面示範資料，沒有連線取得市場價格。"; return }
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        message = nil
        do {
            let key = try SecureKey.read()
            guard !key.isEmpty else { throw StoreError.missingKey }
            let targets = Array(Set(symbols ?? data.holdings.map(\.symbol))).sorted()
            guard !targets.isEmpty else { message = "請先新增持有，或到單檔 ETF 頁面更新報價。"; return }
            var fetched: [String: Quote] = [:]
            for symbol in targets {
                let quote = try await Fugle.quote(symbol: symbol, key: key)
                fetched[symbol] = quote
                if symbol != targets.last { try await Task.sleep(nanoseconds: 2_100_000_000) }
            }
            // The user may have edited holdings while the requests were running.
            var next = data
            next.quotes.merge(fetched) { _, refreshed in refreshed }
            try commit(next)
        } catch { message = error.localizedDescription }
    }
}
enum SecureKey {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ETFToGo.Fugle", kSecAttrAccount as String: "personal-api-key"]
    static func save(_ key: String) throws {
        let bytes = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        if bytes.isEmpty { try remove(); return }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = bytes; add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(add as CFDictionary, nil); guard result == errSecSuccess else { throw StoreError.keychain(result) }
        } else if status != errSecSuccess { throw StoreError.keychain(status) }
    }
    static func read() throws -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let bytes = item as? Data else { throw StoreError.keychain(status) }
        return String(data: bytes, encoding: .utf8) ?? ""
    }
    static func remove() throws { let result = SecItemDelete(query as CFDictionary); guard result == errSecSuccess || result == errSecItemNotFound else { throw StoreError.keychain(result) } }
}
enum Fugle {
    struct Total: Decodable { let tradeVolume: Double? }
    struct Response: Decodable { let symbol: String; let date: String; let closePrice: Double?; let lastPrice: Double?; let changePercent: Double?; let change: Double?; let openPrice: Double?; let highPrice: Double?; let lowPrice: Double?; let total: Total? }
    static func quote(symbol: String, key: String) async throws -> Quote {
        guard symbol.range(of: "^[0-9A-Z]{4,8}$", options: .regularExpression) != nil else { throw StoreError.invalidQuote }
        let url = URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/intraday/quote/\(symbol)")!
        let bytes = try await PublicHTTP.get(url, key: key)
        struct Ticker: Decodable { let symbol: String; let tradingCurrency: String? }
        let ticker = try JSONDecoder().decode(Ticker.self, from: await PublicHTTP.get(URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/intraday/ticker/\(symbol)")!, key: key))
        guard ticker.symbol == symbol else { throw StoreError.invalidQuote }
        var quote = try decode(bytes, expectedSymbol: symbol)
        quote.currency = ticker.tradingCurrency ?? "UNKNOWN"
        return quote
    }
    static func decode(_ bytes: Data, expectedSymbol: String) throws -> Quote {
        let value = try JSONDecoder().decode(Response.self, from: bytes)
        guard value.symbol == expectedSymbol, let price = value.closePrice ?? value.lastPrice, price.isFinite, price > 0 else { throw StoreError.invalidQuote }
        let quote = Quote(symbol: value.symbol, price: price, changePercent: value.changePercent, date: value.date, fetchedAt: Date(), change: value.change, open: value.openPrice, high: value.highPrice, low: value.lowPrice, volume: value.total?.tradeVolume)
        guard quote.isValid else { throw StoreError.invalidQuote }
        return quote
    }
}
enum Projection {
    static func value(initial: Double, monthly: Double, years: Int, annualPercent: Double) -> Double {
        let rate = annualPercent / 100 / 12
        var total = initial
        for _ in 0..<(max(years, 0) * 12) { total = total * (1 + rate) + monthly }
        return total
    }
}
