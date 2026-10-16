import Foundation

/// Live prices without a key, from the exchange's market-watch service (基本市況報導, mis.twse.com.tw):
/// listed and OTC shares, ETFs and both indices, about five seconds behind the market.
/// It is the service behind the exchange's own quote pages, not a documented API, so anything
/// unexpected counts as no quote and the last good one is kept.
enum ExchangeLive {
    static let source = "證交所"
    /// Codes per request; the service has answered 150 in one.
    private static let batch = 100

    /// Quotes for shares and ETFs, keyed by code. `markets` maps codes to "TWSE" or "TPEx";
    /// a code missing from it is asked of both exchanges.
    static func quotes(_ symbols: [String], markets: [String: String]) async throws -> [String: Quote] {
        let codes = Set(symbols.filter(DataChecks.code))
        let channels = codes.sorted().flatMap { code -> [String] in
            switch markets[code] {
            case "TWSE": return ["tse_\(code).tw"]
            case "TPEx": return ["otc_\(code).tw"]
            default: return ["tse_\(code).tw", "otc_\(code).tw"]
            }
        }
        var result: [String: Quote] = [:]
        for start in stride(from: 0, to: channels.count, by: batch) {
            if start > 0 { try await Task.sleep(nanoseconds: 1_000_000_000) }
            let got = try await fetch(Array(channels[start..<min(start + batch, channels.count)]))
            result.merge(got) { _, new in new }
        }
        return result.filter { codes.contains($0.key) }
    }
    /// 加權指數 (t00) and 櫃買指數 (o00), keyed "taiex" and "tpex".
    static func indices() async throws -> [String: Quote] {
        let got = try await fetch(["tse_t00.tw", "otc_o00.tw"])
        return ["taiex": got["t00"], "tpex": got["o00"]].compactMapValues { $0 }
    }
    private static func fetch(_ channels: [String]) async throws -> [String: Quote] {
        var parts = URLComponents(string: "https://mis.twse.com.tw/stock/api/getStockInfo.jsp")!
        parts.queryItems = [URLQueryItem(name: "ex_ch", value: channels.joined(separator: "|")), URLQueryItem(name: "json", value: "1"), URLQueryItem(name: "delay", value: "0")]
        return try decode(await PublicHTTP.get(parts.url!))
    }

    /// The last trade (`z`, else the latest entry in `trade` while the current tick has none) against
    /// yesterday's close (`y`). Codes without a trade today are left out. Volume `v` is in lots (張).
    static func decode(_ bytes: Data, fetchedAt: Date = Date()) throws -> [String: Quote] {
        guard let root = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any], root["rtcode"] as? String == "0000",
              let items = root["msgArray"] as? [[String: Any]] else { throw StoreError.invalidQuote }
        var result: [String: Quote] = [:]
        for item in items {
            guard let code = item["c"] as? String, !code.isEmpty, let raw = item["d"] as? String, raw.count == 8 else { continue }
            let day = "\(raw.prefix(4))-\(raw.dropFirst(4).prefix(2))-\(raw.suffix(2))"
            guard DataChecks.date(day) != nil, let price = number(item["z"]) ?? number((item["trade"] as? [String: Any])?["z"]), price > 0 else { continue }
            let previous = number(item["y"]).flatMap { $0 > 0 ? $0 : nil }
            let change = previous.map { ((price - $0) * 10000).rounded() / 10000 }
            let percent = previous.map { ((price - $0) / $0 * 10000).rounded() / 100 }
            // K codes trade in a foreign currency, which the service does not state.
            var quote = Quote(symbol: code, price: price, changePercent: percent, date: day, fetchedAt: fetchedAt, currency: code.hasSuffix("K") ? "UNKNOWN" : "TWD",
                              change: change, open: number(item["o"]), high: number(item["h"]), low: number(item["l"]), volume: number(item["v"]), source: source)
            if !quote.isValid { quote.open = nil; quote.high = nil; quote.low = nil; quote.volume = nil }
            if quote.isValid { result[code] = quote }
        }
        return result
    }
    private static func number(_ value: Any?) -> Double? {
        guard let text = (value as? String) ?? (value as? NSNumber)?.stringValue, let value = Double(text.replacingOccurrences(of: ",", with: "")), value.isFinite else { return nil }
        return value
    }
}

extension PortfolioStore {
    /// "TWSE" or "TPEx" for each code, from the bundled company list or the ETF catalogue.
    func markets(_ symbols: [String]) -> [String: String] {
        let funds = Dictionary((catalog?.funds ?? []).map { ($0.id, $0.market ?? "") }) { first, _ in first }
        var result: [String: String] = [:]
        for symbol in symbols { if let market = stock(symbol)?.market ?? funds[symbol], !market.isEmpty { result[symbol] = market } }
        return result
    }
    var hasFugleKey: Bool { !((try? SecureKey.read()) ?? "").isEmpty }

    /// Exchange prices for these codes when no Fugle key is saved. Quiet: on failure the last good quotes stay.
    func refreshLive(_ symbols: [String]) async {
        guard !isDemo, !hasFugleKey, !symbols.isEmpty,
              let fetched = try? await ExchangeLive.quotes(symbols, markets: markets(symbols)), !fetched.isEmpty else { return }
        var next = data
        next.quotes.merge(fetched) { _, refreshed in refreshed }
        try? commit(next)
    }
    /// What follows the market without a key: holdings, the watchlist, the home page's most traded and
    /// anything priced live before, most recent first, up to three requests.
    var liveSymbols: [String] {
        let hot = (stockSnapshot?.mostTraded(stockSnapshot?.stocks.map(\.id) ?? [], count: 5) ?? []) + (stockSnapshot?.mostTraded(funds.map(\.id), count: 5) ?? [])
        let seen = data.quotes.values.sorted { $0.fetchedAt > $1.fetchedAt }.map(\.symbol)
        var list: [String] = [], added = Set<String>()
        for symbol in data.holdings.map(\.symbol) + data.favorites.sorted() + hot + seen where added.insert(symbol).inserted { list.append(symbol) }
        return Array(list.prefix(300))
    }
    /// Weekdays 08:55–13:40 Taipei time, the trading session with a margin either side.
    static func marketOpen(_ now: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return (2...6).contains(parts.weekday ?? 1) && minutes >= 8 * 60 + 55 && minutes <= 13 * 60 + 40
    }
    /// While the app is in front: indices and prices once, then every minute during trading hours when no
    /// Fugle key is saved (with a key, quotes stay on the viewer's own Fugle requests).
    func followMarket() async {
        guard !isDemo else { return }
        var first = true
        while !Task.isCancelled {
            let keyless = !hasFugleKey
            if first || (keyless && Self.marketOpen()) {
                await refreshIndices()
                if keyless { await refreshLive(liveSymbols) }
            }
            first = false
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }
}
