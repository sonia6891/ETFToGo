import Foundation

struct PlanningData: Codable, Equatable {
    var version: Int = 2
    var holdings: [Holding] = []
    var dividends: [Dividend] = []
    var plan: Plan = Plan()
    init() {}
    enum CodingKeys: String, CodingKey { case version, holdings, dividends, plan }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        version = try box.decode(Int.self, forKey: .version)
        holdings = try box.decode([Holding].self, forKey: .holdings)
        dividends = try box.decode([Dividend].self, forKey: .dividends)
        plan = try box.decodeIfPresent(Plan.self, forKey: .plan) ?? Plan()
    }
}
struct UserData: Codable, Equatable {
    var app: String = "ETF_TOGO_NATIVE"
    var version: Int = 1
    var planning: PlanningData = PlanningData()
    var favorites: [String] = []
    var comparison: [String] = []
    var components: [String: ComponentSnapshot]? = nil
    func validate() throws {
        guard app == "ETF_TOGO_NATIVE", version == 1, planning.version == 2, planning.holdings.count <= 10_000, planning.dividends.count <= 50_000 else { throw AppError("備份版本或紀錄數不支援。") }
        guard Set(planning.holdings.map(\.id)).count == planning.holdings.count, Set(planning.dividends.map(\.id)).count == planning.dividends.count else { throw AppError("備份內含重複紀錄編號。") }
        for h in planning.holdings { try h.validate() }
        for d in planning.dividends { try d.validate() }
        try planning.plan.validate()
        if let components {
            guard components.count <= 1000 else { throw AppError("成分資料筆數超出上限。") }
            for (code, snapshot) in components { guard code == snapshot.symbol else { throw AppError("成分資料代碼不符。") }; try snapshot.validate() }
        }

        guard favorites.count <= 1000, comparison.count <= 3, favorites.allSatisfy(Validation.isCode), comparison.allSatisfy(Validation.isCode), Set(favorites).count == favorites.count, Set(comparison).count == comparison.count else { throw AppError("收藏或比較名單格式不正確。") }
    }
}
enum Backup {
    private struct Legacy: Decodable {
        let app: String
        let version: Int
        let planning: PlanningData
        let favorites: [String]
        let comparison: [String]
    }
    static func decode(_ bytes: Data) throws -> UserData {
        guard bytes.count <= 5_000_000 else { throw AppError("備份超過 5 MB，未匯入。") }
        let decoder = JSONDecoder()
        guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw AppError("備份格式不正確。") }
        let result: UserData
        if root["app"] as? String == "ETF_TOGO_NATIVE" {
            result = try decoder.decode(UserData.self, from: bytes)
        } else if root["app"] as? String == "ETF_CLASSIFIER" {
            let old = try decoder.decode(Legacy.self, from: bytes)
            guard old.version == 3 else { throw AppError("不支援這個舊版備份版本。") }
            result = UserData(planning: old.planning, favorites: old.favorites, comparison: old.comparison)
        } else if root["app"] == nil, root["holdings"] != nil, root["version"] as? Int == 2 {
            result = UserData(planning: try decoder.decode(PlanningData.self, from: bytes))
        } else { throw AppError("不是 ETF 袋著走支援的備份。") }
        try result.validate(); return result
    }
    static func encode(_ data: UserData) throws -> Data {
        try data.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(data)
        guard bytes.count <= 5_000_000 else { throw AppError("資料超過 5 MB，未覆寫既有紀錄。") }
        return bytes
    }
}

/// Commit only after validation and atomic write. Read failures never reset saved data.
final class DataRepository {
    let url: URL
    init(url: URL) { self.url = url }
    func load() throws -> UserData {
        guard FileManager.default.fileExists(atPath: url.path) else { return UserData() }
        return try Backup.decode(Data(contentsOf: url))
    }
    func save(_ data: UserData) throws {
        let bytes = try Backup.encode(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try bytes.write(to: url, options: .atomic)
        #endif
    }
}
