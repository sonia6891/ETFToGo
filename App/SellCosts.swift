import Foundation

/// 市值 the way brokers such as 國泰證券 show it: what selling today would bring in, the price × shares less the
/// estimated selling fee (0.1425% × the viewer's discount, rounded down, at least the minimum fee) and the securities
/// transaction tax (stocks 0.3%, ETFs 0.1%, bond ETFs exempt through 2026), also rounded down. The discount, the minimum
/// and whether to deduct at all are set in 設定 › 市值計算.
enum SellCosts {
    static let netKey = "netMarketValue", discountKey = "feeDiscount", minimumKey = "feeMinimum"
    /// Deduct the estimated selling costs from 市值 (on unless turned off).
    static var enabled: Bool { (UserDefaults.standard.object(forKey: netKey) as? Bool) ?? true }
    /// The broker's discount in 折: 2.8 means 28% of the list fee. 國泰證券's online rate is the default.
    static var discount: Double { min(max((UserDefaults.standard.object(forKey: discountKey) as? Double) ?? 2.8, 0), 10) }
    /// The smallest fee charged on a sale, in NT$.
    static var minimum: Double { min(max((UserDefaults.standard.object(forKey: minimumKey) as? Double) ?? 1, 0), 1000) }
    /// Bond ETFs are exempt from the transaction tax until the end of 2026.
    static let bondExemptionEnd = DataChecks.date("2027-01-01")!

    static func taxRate(stock: Bool, bond: Bool, on day: Date = Date()) -> Double {
        if stock { return 0.003 }
        return bond && day < bondExemptionEnd ? 0 : 0.001
    }
    static func fee(_ gross: Double, discount: Double = Self.discount, minimum: Double = Self.minimum) -> Double {
        guard gross > 0 else { return 0 }
        return max(minimum, down(gross * 0.001425 * discount / 10))
    }
    /// The price × shares after the estimated fee and tax of selling them.
    static func net(_ gross: Double, stock: Bool, bond: Bool, discount: Double = Self.discount, minimum: Double = Self.minimum, on day: Date = Date()) -> Double {
        guard gross > 0 else { return gross }
        let tax = down(gross * taxRate(stock: stock, bond: bond, on: day))
        return gross - fee(gross, discount: discount, minimum: minimum) - tax
    }
    /// Rounded down to whole dollars; a hair is added so 300.0 that comes out as 299.9999… stays 300.
    private static func down(_ value: Double) -> Double { (value + 1e-6).rounded(.down) }
}
