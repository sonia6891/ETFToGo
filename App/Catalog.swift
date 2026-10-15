import Foundation

struct AppDataError: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}
enum DataChecks {
    static func code(_ value: String) -> Bool { value.range(of: "^[0-9]{4,6}[A-Z]?$", options: .regularExpression) != nil }
    static func day(_ date: Date = Date()) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Taipei"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func date(_ text: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Taipei"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let value = formatter.date(from: text), formatter.string(from: value) == text else { return nil }
        return value
    }
    static func rocDay(_ text: String) -> String? {
        let raw = text.filter(\.isNumber)
        guard raw.count == 7 || raw.count == 8, let year = Int(raw.dropLast(4)) else { return nil }
        let value = String(year + (raw.count == 7 ? 1911 : 0)) + "-" + raw.dropLast(2).suffix(2) + "-" + raw.suffix(2)
        return date(value) == nil ? nil : value
    }
    static func readFile(_ url: URL, limit: Int = 5_000_000) throws -> Data {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? limit + 1) <= limit else { throw AppDataError("檔案太大，未讀取。") }
        return try Data(contentsOf: url)
    }
}
enum PublicHTTP {
    static func get(_ url: URL, key: String? = nil) async throws -> Data {
        guard url.scheme == "https" else { throw AppDataError("只接受安全的資料連線。") }
        var request = URLRequest(url: url); request.timeoutInterval = 25; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key {
            guard url.host == "api.fugle.tw" else { throw AppDataError("金鑰只能傳給富果。") }
            request.setValue(key, forHTTPHeaderField: "X-API-KEY")
        }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw StoreError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        guard bytes.count <= 10_000_000 else { throw AppDataError("資料超過大小上限，保留原資料。") }
        return bytes
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
struct CatalogSnapshot: Codable {
    var funds: [Fund]
    var listedDate: String
    var fetchedDay: String
    var sources: [String]
    func validate() throws {
        guard !funds.isEmpty, funds.count <= 2000, Set(funds.map(\.id)).count == funds.count,
              DataChecks.date(listedDate) != nil, DataChecks.date(fetchedDay) != nil,
              listedDate <= DataChecks.day(), fetchedDay <= DataChecks.day(),
              funds.allSatisfy({ DataChecks.code($0.id) && !$0.name.isEmpty && $0.name.count <= 120 && ["TWSE", "TPEx"].contains($0.market ?? "") })
        else { throw AppDataError("ETF 名單未通過驗證，保留上次成功資料。") }
    }
    static func bundled() -> CatalogSnapshot? {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"), let bytes = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: bytes), (try? value.validate()) != nil else { return nil }
        return value
    }
}
enum CatalogAPI {
    static let listedURL = "https://openapi.twse.com.tw/v1/opendata/t187ap47_L"
    static let otcURL = "https://info.tpex.org.tw/api/etf?lang=zh-tw"
    static func strategy(_ name: String) -> Strategy {
        if name.contains("正2") || name.contains("反1") || name.contains("槓桿") || name.contains("反向") { return .risk }
        if name.contains("高股息") || name.contains("優息") || name.contains("高息") { return .income }
        if ["元大台灣50", "富邦台50", "元大富櫃50"].contains(name) { return .saving }
        return .unclassified
    }
    static func decode(listed: Data, otc: Data, today: String = DataChecks.day()) throws -> CatalogSnapshot {
        let rows = try JSONDecoder().decode([[String: String]].self, from: listed)
        struct OTC: Decodable { var suggestions: [String] }
        let suggestions = try JSONDecoder().decode(OTC.self, from: otc).suggestions
        guard !rows.isEmpty, !suggestions.isEmpty else { throw AppDataError("上市或上櫃來源缺資料，保留原名單。") }
        var funds: [Fund] = []; var dates: [String] = []
        for row in rows {
            guard let code = row["基金代號"], let name = row["基金簡稱"], let day = DataChecks.rocDay(row["出表日期"] ?? ""), let listing = DataChecks.rocDay(row["上市日期"] ?? ""), day <= today else { throw AppDataError("上市名單欄位或日期改變，未覆寫。") }
            if listing > today { continue }
            funds.append(Fund(id: code, name: name, strategy: strategy(name), market: "TWSE", fullName: row["基金中文名稱"], fundType: row["基金類型"], listingDate: listing))
            dates.append(day)
        }
        for item in suggestions {
            let parts = item.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { throw AppDataError("上櫃名單欄位改變，未覆寫。") }
            let name = String(parts[1]); funds.append(Fund(id: String(parts[0]), name: name, strategy: strategy(name), market: "TPEx"))
        }
        let value = CatalogSnapshot(funds: funds.sorted { $0.id < $1.id }, listedDate: dates.max() ?? today, fetchedDay: today, sources: [listedURL, otcURL])
        try value.validate(); return value
    }
    static func fetch() async throws -> CatalogSnapshot {
        async let listed = PublicHTTP.get(URL(string: listedURL)!)
        async let otc = PublicHTTP.get(URL(string: otcURL)!)
        return try await decode(listed: listed, otc: otc)
    }
}
