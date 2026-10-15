import Foundation

struct FundComponent: Codable, Identifiable, Equatable {
    var symbol: String
    var name: String?
    var weight: Double
    var id: String { symbol }
}
struct ComponentSnapshot: Codable, Equatable {
    var symbol: String
    var date: String
    var components: [FundComponent]
    var source: String?
    var totalWeight: Double { components.reduce(0) { $0 + $1.weight } }
    func validate() throws {
        guard Validation.isCode(symbol), Validation.isDate(date), date <= Validation.day(), !components.isEmpty, components.count <= 1000, Set(components.map(\.symbol)).count == components.count, totalWeight.isFinite, totalWeight > 0, totalWeight <= 101 else { throw AppError("成分資料日期、筆數或權重不正確。") }
        for c in components {
            guard Validation.text(c.symbol, max: 40), c.symbol.rangeOfCharacter(from: .controlCharacters) == nil, (c.name?.count ?? 0) <= 120, c.weight.isFinite, (0...100).contains(c.weight) else { throw AppError("成分欄位未通過驗證。") }
        }
    }
    static func imported(_ bytes: Data, code: String) throws -> ComponentSnapshot {
        guard bytes.count <= 1_000_000 else { throw AppError("成分檔不可超過 1 MB。") }
        var snapshot = try JSONDecoder().decode(ComponentSnapshot.self, from: bytes)
        guard snapshot.symbol == code else { throw AppError("成分檔 ETF 代碼不符。") }
        snapshot.source = "使用者匯入（未經核驗）"
        try snapshot.validate(); return snapshot
    }
}
struct Exposure: Identifiable {
    var symbol: String
    var name: String
    var value: Decimal
    var funds: Set<String>
    var id: String { symbol }
}
enum ExposureCalculator {
    static func calculate(holdings: [Holding], snapshots: [String: ComponentSnapshot]) -> [Exposure] {
        var values: [String: Exposure] = [:]
        for h in holdings {
            guard let value = h.value, let snapshot = snapshots[h.code] else { continue }
            for c in snapshot.components {
                var row = values[c.symbol] ?? Exposure(symbol: c.symbol, name: c.name ?? c.symbol, value: 0, funds: [])
                row.value += value * Decimal(c.weight) / 100; row.funds.insert(h.code); values[c.symbol] = row
            }
        }
        return values.values.sorted { $0.value > $1.value }
    }
}
