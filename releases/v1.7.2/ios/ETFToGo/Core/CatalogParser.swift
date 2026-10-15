import Foundation

enum CatalogParser {
    static let twseURL = "https://openapi.twse.com.tw/v1/opendata/t187ap47_L"
    static func rocDate(_ raw: String) -> String? {
        let value = raw.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "-", with: "")
        guard value.count == 7 || value.count == 8, value.allSatisfy(\.isNumber), let y = Int(value.dropLast(4)) else { return nil }
        let year = y + (value.count == 7 ? 1911 : 0)
        let date = "\(year)-\(value.suffix(4).prefix(2))-\(value.suffix(2))"
        return Validation.isDate(date) ? date : nil
    }
    static func twse(_ bytes: Data, today: String = Validation.day()) throws -> [ETF] {
        guard bytes.count <= 5_000_000, let rows = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]], !rows.isEmpty else { throw AppError("證交所資料格式異常。") }
        var result: [ETF] = []
        for r in rows {
            guard let code = r["基金代號"] as? String, let name = r["基金簡稱"] as? String, let type = r["基金類型"] as? String, let rawDate = r["出表日期"] as? String, let date = rocDate(rawDate), date <= today, Validation.isCode(code), !name.isEmpty else { throw AppError("證交所欄位有變動，請保留原名單。") }
            let listed = rocDate(r["上市日期"] as? String ?? "")
            if let listed, listed > date { continue }
            result.append(ETF(code: code, name: name, fullName: r["基金中文名稱"] as? String ?? name, fundType: type, indexName: r["標的指數/追蹤指數名稱"] as? String ?? "", market: "TWSE", sourceDate: date, listingDate: listed, sourceURL: twseURL))
        }
        guard !result.isEmpty, Set(result.map(\.code)).count == result.count else { throw AppError("證交所名單為空或重複。") }
        return result.sorted { $0.code < $1.code }
    }
}
