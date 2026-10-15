import SwiftUI
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data = UserData()
    @Published private(set) var catalog: Catalog?
    @Published var message: String?
    @Published var catalogStatus = "載入內附名單"
    @Published var refreshing = false
    @Published private(set) var storageBlocked = false
    private let repository: DataRepository
    private let catalogFile: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ETFToGo", isDirectory: true)
        repository = DataRepository(url: folder.appendingPathComponent("portfolio.json"))
        catalogFile = folder.appendingPathComponent("catalog.json")
        do { data = try repository.load() } catch { storageBlocked = true; message = "紀錄無法讀取，原檔保留且已停止寫入：\(error.localizedDescription)" }
        if let bytes = try? Data(contentsOf: catalogFile), let saved = try? JSONDecoder().decode(Catalog.self, from: bytes), (try? saved.validate()) != nil { catalog = saved; catalogStatus = "上次同步名單" }
        else if let url = Bundle.main.url(forResource: "catalog", withExtension: "json"), let bytes = try? Data(contentsOf: url), let bundled = try? JSONDecoder().decode(Catalog.self, from: bytes), (try? bundled.validate()) != nil { catalog = bundled; catalogStatus = "內附官方名單快照" }
        else { catalogStatus = "名單尚未取得；仍可手動記錄持有" }
    }
    func commit(_ mutation: (inout UserData) throws -> Void) {
        guard !storageBlocked else { message = "原始紀錄讀取異常，已停止寫入。請先匯出原始檔案，確認後再匯入有效備份。"; return }
        do { var next = data; try mutation(&next); try repository.save(next); data = next }
        catch { message = error.localizedDescription }
    }
    func upsert(_ h: Holding) throws {
        guard !storageBlocked else { throw AppError("儲存已鎖定，原始資料未覆寫。") }
        try h.validate(); var next = data
        if let i = next.planning.holdings.firstIndex(where: { $0.id == h.id }) { next.planning.holdings[i] = h } else { next.planning.holdings.append(h) }
        try repository.save(next); data = next
    }
    func upsert(_ d: Dividend) throws {
        guard !storageBlocked else { throw AppError("儲存已鎖定，原始資料未覆寫。") }
        try d.validate(); var next = data
        if let i = next.planning.dividends.firstIndex(where: { $0.id == d.id }) { next.planning.dividends[i] = d } else { next.planning.dividends.append(d) }
        try repository.save(next); data = next
    }
    func toggleFavorite(_ code: String) { commit { if $0.favorites.contains(code) { $0.favorites.removeAll { $0 == code } } else { $0.favorites.append(code) } } }
    func toggleCompare(_ code: String) { commit { value in
        if value.comparison.contains(code) { value.comparison.removeAll { $0 == code } }
        else { guard value.comparison.count < 3 else { throw AppError("最多比較三檔，請先移除一檔。") }; value.comparison.append(code) }
    } }
    func restore(_ next: UserData) throws {
        // Preserve a recovery copy before an explicit replacement, including unreadable bytes.
        if FileManager.default.fileExists(atPath: repository.url.path) {
            let recovery = repository.url.deletingLastPathComponent().appendingPathComponent("before-import-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: repository.url, to: recovery)
        }
        try repository.save(next); data = next; storageBlocked = false
    }
    func exportBytes() throws -> Data {
        if storageBlocked { return try Data(contentsOf: repository.url) }
        return try Backup.encode(data)
    }
    func refreshCatalog() async {
        guard !refreshing else { return }; refreshing = true; defer { refreshing = false }
        do {
            let next = try await MarketAPI.catalog()
            try next.validate()
            if let old = catalog {
                for market in ["TWSE"] {
                    let a = old.records.filter { $0.market == market }, b = next.records.filter { $0.market == market }
                    guard b.count >= Int(Double(a.count) * 0.8), (b.map(\.sourceDate).max() ?? "") >= (a.map(\.sourceDate).max() ?? "") else { throw AppError("名單數量或日期異常，保留上次版本。") }
                }
            }
            let bytes = try JSONEncoder().encode(next)
            try FileManager.default.createDirectory(at: catalogFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: catalogFile, options: .atomic)
            catalog = next; catalogStatus = "官方名單同步成功"
        } catch { catalogStatus = "更新失敗，保留原名單"; message = error.localizedDescription }
    }
    func etf(_ code: String) -> ETF? { catalog?.records.first { $0.code == code } }
}
