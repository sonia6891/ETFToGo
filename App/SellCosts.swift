import Foundation

/// A broker's selling fee: the discount in 折 (2.8 means 28% of the list 0.1425%) and the smallest fee charged.
struct FeeRate: Codable, Equatable {
    var discount: Double
    var minimum: Double
    var valid: FeeRate { FeeRate(discount: min(max(discount, 0), 10), minimum: min(max(minimum, 0), 1000)) }
}

/// 市值 the way brokers show it: what selling today would bring in, the price × shares less the estimated selling fee
/// (0.1425% × the broker's discount, rounded down, at least its minimum) and the securities transaction tax (stocks
/// 0.3%, ETFs 0.1%, bond ETFs exempt through 2026), also rounded down. Discounts differ by broker and by account, so
/// each broker's rate is the viewer's to set in 設定; a broker without one is charged the list price.
enum SellCosts {
    static let netKey = "netMarketValue", ratesKey = "brokerFeeRates"
    /// The list price: no discount, at least NT$20 (most brokers' minimum on a board-lot trade).
    static let standard = FeeRate(discount: 10, minimum: 20)
    /// Bond ETFs are exempt from the transaction tax until the end of 2026.
    static let bondExemptionEnd = DataChecks.date("2027-01-01")!
    /// Deduct the estimated selling costs from 市值 (on unless turned off).
    static var enabled: Bool { (UserDefaults.standard.object(forKey: netKey) as? Bool) ?? true }

    /// The broker a fee belongs to: 融資 holdings sell through the same broker as cash ones.
    static func brokerKey(_ broker: String) -> String {
        broker.replacingOccurrences(of: "（融資）", with: "").replacingOccurrences(of: "(融資)", with: "").trimmingCharacters(in: .whitespaces)
    }
    /// The rates the viewer set, by broker; the key "" holds a default for every other broker.
    static func rates(in defaults: UserDefaults = .standard) -> [String: FeeRate] {
        guard let bytes = defaults.data(forKey: ratesKey), let stored = try? JSONDecoder().decode([String: FeeRate].self, from: bytes) else { return [:] }
        return stored
    }
    static func save(_ rates: [String: FeeRate], in defaults: UserDefaults = .standard) {
        if let bytes = try? JSONEncoder().encode(rates) { defaults.set(bytes, forKey: ratesKey) }
    }
    static func rate(for broker: String, in defaults: UserDefaults = .standard) -> FeeRate {
        let set = rates(in: defaults)
        return (set[brokerKey(broker)] ?? set[""] ?? standard).valid
    }
    /// Whether this broker's fee is the viewer's own setting rather than the list price.
    static func isSet(for broker: String, in defaults: UserDefaults = .standard) -> Bool {
        let set = rates(in: defaults)
        return set[brokerKey(broker)] != nil || set[""] != nil
    }

    static func taxRate(stock: Bool, bond: Bool, on day: Date = Date()) -> Double {
        if stock { return 0.003 }
        return bond && day < bondExemptionEnd ? 0 : 0.001
    }
    static func fee(_ gross: Double, rate: FeeRate) -> Double {
        guard gross > 0 else { return 0 }
        return max(rate.minimum, down(gross * 0.001425 * rate.discount / 10))
    }
    /// The price × shares after the estimated fee and tax of selling them.
    static func net(_ gross: Double, stock: Bool, bond: Bool, rate: FeeRate, on day: Date = Date()) -> Double {
        guard gross > 0 else { return gross }
        let tax = down(gross * taxRate(stock: stock, bond: bond, on: day))
        return gross - fee(gross, rate: rate.valid) - tax
    }
    /// Rounded down to whole dollars; a hair is added so 300.0 that comes out as 299.9999… stays 300.
    private static func down(_ value: Double) -> Double { (value + 1e-6).rounded(.down) }
}
