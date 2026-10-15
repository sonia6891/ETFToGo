import Foundation

/// Reject redirects so the API key can only be delivered to the intended host.
private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct Quote: Decodable {
    var date: String
    var symbol: String
    var name: String
    var closePrice: Double?
    var lastUpdated: Double?
}
enum MarketAPI {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }()
    static func request(_ url: URL, method: String = "GET", key: String? = nil) async throws -> Data {
        var r = URLRequest(url: url); r.httpMethod = method; r.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" { r.httpBody = Data(); r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        if let key { guard url.host == "api.fugle.tw", url.scheme == "https" else { throw AppError("不允許傳送金鑰至其他主機。") }; r.setValue(key, forHTTPHeaderField: "X-API-KEY") }
        let (bytes, response) = try await session.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw AppError("服務回應不正確。") }
        if http.statusCode == 401 || http.statusCode == 403 { throw AppError("金鑰無效或資料方案不支援此查詢。") }
        if http.statusCode == 429 { throw AppError("查詢次數已達限制，請稍後再試。") }
        guard http.statusCode == 200, bytes.count <= 5_000_000 else { throw AppError("資料服務暫時無法使用（\(http.statusCode)）。") }
        return bytes
    }
    static func catalog() async throws -> Catalog {
        let bytes = try await request(URL(string: CatalogParser.twseURL)!)
        let records = try CatalogParser.twse(bytes)
        return Catalog(records: records, fetchedAt: ISO8601DateFormatter().string(from: Date()), coverage: "台灣證交所上市 ETF，包含海外投資標的及外幣交易級別；不含上櫃。代碼數不等於獨立基金數。", sources: [CatalogParser.twseURL])
    }

    static func quote(_ code: String) async throws -> Quote {
        guard code.range(of: "^[0-9]{4,6}[A-Z]?$", options: .regularExpression) != nil else { throw AppError("請使用台灣 ETF 代碼。") }
        guard let key = try QuoteKeychain.load() else { throw AppError("請先到「更多」設定個人富果行情金鑰。") }
        let bytes = try await request(URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/intraday/quote/\(code)")!, key: key)
        let q = try JSONDecoder().decode(Quote.self, from: bytes)
        guard q.symbol == code, Validation.isDate(q.date) else { throw AppError("行情代碼或日期不符。") }
        if let price = q.closePrice, !price.isFinite || price < 0 { throw AppError("行情價格不正確。") }
        return q
    }
    static func components(_ code: String) async throws -> ComponentSnapshot {
        guard code.range(of: "^[0-9]{4,6}[A-Z]?$", options: .regularExpression) != nil else { throw AppError("ETF 代碼不正確。") }
        guard let key = try QuoteKeychain.load() else { throw AppError("請先設定個人富果行情金鑰。") }
        struct Response: Decodable { var symbol: String; var data: [Day] }
        struct Day: Decodable { var date: String; var components: [FundComponent] }
        let bytes = try await request(URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/ownership/etf-holdings/\(code)")!, key: key)
        let response = try JSONDecoder().decode(Response.self, from: bytes)
        guard response.symbol == code else { throw AppError("成分資料代碼不符。") }
        guard let day = response.data.sorted(by: { $0.date > $1.date }).first else { throw AppError("此區間沒有股票成分資料；純債、期貨等 ETF 可能不提供股票成分。") }
        let snapshot = ComponentSnapshot(symbol: code, date: day.date, components: day.components, source: "富果 ETF Holdings")
        try snapshot.validate(); return snapshot
    }

}
