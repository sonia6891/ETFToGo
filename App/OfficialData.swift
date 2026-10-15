import Foundation

/// One official ETF distribution: ex-dividend date, payment date ("" when not announced) and amount per unit (nil until set).
struct OfficialDistribution: Codable, Hashable {
    var ex: String
    var pay: String
    var amount: Double?
}
/// Official distributions from TWSE "ETF 收益分配" (listed ETFs, about two years) and the TPEx ex-dividend notice
/// (OTC ETFs, upcoming only). Bundled as official-dividends.json and refreshable on the device.
struct OfficialDividends: Codable {
    var sources: [String: String] = [:]
    var events: [String: [OfficialDistribution]] = [:]
    var freq: [String: String] = [:]

    static func bundled() -> OfficialDividends {
        guard let url = Bundle.main.url(forResource: "official-dividends", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(OfficialDividends.self, from: bytes) else { return OfficialDividends() }
        return value
    }
    func isNewer(than other: OfficialDividends) -> Bool { (sources["twse"] ?? "") > (other.sources["twse"] ?? "") || ((sources["twse"] ?? "") == (other.sources["twse"] ?? "") && (sources["tpex"] ?? "") > (other.sources["tpex"] ?? "")) }
    func list(_ symbol: String) -> [OfficialDistribution] { events[symbol] ?? [] }
    func frequency(_ symbol: String) -> String? { freq[symbol] }
    /// Sum of announced amounts per unit with an ex-dividend date in the past year.
    func trailingAmount(_ symbol: String) -> Double? {
        let from = DataChecks.day(Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()), today = DataChecks.day()
        let items = list(symbol).filter { $0.ex > from && $0.ex <= today && ($0.amount ?? 0) > 0 }
        return items.isEmpty ? nil : items.reduce(0) { $0 + ($1.amount ?? 0) }
    }
    /// Distribution frequency from the number of ex-dividend dates in the past year.
    static func frequency(of list: [OfficialDistribution]) -> String? {
        let from = DataChecks.day(Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()), today = DataChecks.day()
        let n = list.filter { $0.ex > from && $0.ex <= today }.count
        switch n {
        case 9...: return "月配"
        case 5...8: return "雙月配"
        case 3...4: return "季配"
        case 2: return "半年配"
        case 1: return "年配"
        default: return nil
        }
    }
    /// "115年10月22日" or "1151016" → "2026-10-22".
    static func rocDay(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespaces)
        let parts: [Int]
        if value.contains("年") {
            parts = value.replacingOccurrences(of: "年", with: "-").replacingOccurrences(of: "月", with: "-").replacingOccurrences(of: "日", with: "").split(separator: "-").compactMap { Int($0) }
        } else if value.count == 7, value.allSatisfy(\.isNumber) {
            parts = [Int(value.prefix(3)), Int(value.dropFirst(3).prefix(2)), Int(value.suffix(2))].compactMap { $0 }
        } else { return nil }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return String(format: "%04d-%02d-%02d", parts[0] + 1911, parts[1], parts[2])
    }
    /// Fetches both official sources; a source that fails keeps the previous data.
    static func fetch(merging old: OfficialDividends, markets: [String: String]) async throws -> OfficialDividends {
        var next = old
        var events: [String: [OfficialDistribution]] = [:]
        var errors: [String] = []
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(byAdding: .day, value: -400, to: Date()) ?? Date()
        let startText = DataChecks.day(start).replacingOccurrences(of: "-", with: "")
        let year = calendar.component(.year, from: Date()) + 1
        do {
            let bytes = try await PublicHTTP.get(URL(string: "https://www.twse.com.tw/rwd/zh/ETF/etfDiv?stkNo=&startDate=\(startText)&endDate=\(year)1231&response=json")!)
            guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], root["status"] as? String == "ok",
                  let fields = root["fields"] as? [String], fields.count > 5, fields[2] == "除息交易日", let rows = root["data"] as? [[Any]] else { throw AppDataError("證交所回傳格式不符。") }
            for row in rows where row.count > 5 {
                guard let symbol = (row[0] as? String)?.trimmingCharacters(in: .whitespaces), markets[symbol] != nil, let ex = rocDay(row[2] as? String ?? "") else { continue }
                let amount = Double((row[5] as? String ?? "").replacingOccurrences(of: ",", with: "")).flatMap { $0 > 0 ? $0 : nil }
                events[symbol, default: []].append(OfficialDistribution(ex: ex, pay: rocDay(row[4] as? String ?? "") ?? "", amount: amount))
            }
            for (symbol, fresh) in events {
                let seen = Set(fresh.map(\.ex))
                let merged = fresh + old.list(symbol).filter { !seen.contains($0.ex) }
                next.events[symbol] = merged.sorted { $0.ex > $1.ex }
                if let label = frequency(of: next.events[symbol] ?? []) { next.freq[symbol] = label }
            }
            next.sources["twse"] = DataChecks.day()
        } catch { errors.append("證交所：\(error.localizedDescription)") }
        do {
            let bytes = try await PublicHTTP.get(URL(string: "https://www.tpex.org.tw/openapi/v1/tpex_exright_prepost")!)
            guard let rows = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] else { throw AppDataError("櫃買中心回傳格式不符。") }
            for row in rows {
                guard let symbol = (row["SecuritiesCompanyCode"] as? String)?.trimmingCharacters(in: .whitespaces), markets[symbol] == "TPEx",
                      (row["ExRrightsExDividend"] as? String ?? "").contains("息"), let ex = rocDay(row["ExRrightsExDividendDate"] as? String ?? "") else { continue }
                let amount = Double((row["CashDividend"] as? String ?? "").replacingOccurrences(of: ",", with: "")).flatMap { $0 > 0 ? $0 : nil }
                var list = next.list(symbol).filter { $0.ex != ex }
                list.append(OfficialDistribution(ex: ex, pay: "", amount: amount))
                next.events[symbol] = list.sorted { $0.ex > $1.ex }
            }
            next.sources["tpex"] = DataChecks.day()
        } catch { errors.append("櫃買中心：\(error.localizedDescription)") }
        if errors.count == 2 { throw AppDataError("無法更新官方配息資料，保留原本資料。\(errors.joined(separator: "；"))") }
        return next
    }
}
extension PortfolioStore {
    /// Official announcements for held ETFs (ex-dividend from a week ago onwards) not yet in the user's records.
    func officialForHoldings() -> [(symbol: String, event: OfficialDistribution, shares: Double)] {
        let from = DataChecks.day(Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
        var result: [(symbol: String, event: OfficialDistribution, shares: Double)] = []
        for symbol in Set(data.holdings.map(\.symbol)).sorted() {
            let shares = data.holdings.filter { $0.symbol == symbol }.reduce(0) { $0 + $1.shares }
            for event in official.list(symbol) where event.ex >= from {
                let recorded = data.dividends.contains { $0.symbol == symbol && ($0.exDate.map(DataChecks.day) == event.ex || (!event.pay.isEmpty && DataChecks.day($0.date) == event.pay)) }
                if !recorded { result.append((symbol, event, shares)) }
            }
        }
        return result.sorted { $0.event.ex < $1.event.ex }
    }
}
