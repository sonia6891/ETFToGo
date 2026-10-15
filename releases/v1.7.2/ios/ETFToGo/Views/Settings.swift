import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { guard let bytes = configuration.file.regularFileContents else { throw AppError("檔案無法讀取。") }; data = bytes }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("appearance") private var appearance = "system"
    @State private var key = ""
    @State private var keyStatus = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var document = BackupDocument()
    @State private var pendingImport: UserData?
    @State private var confirmImport = false
    var body: some View {
        Form {
            Section("顯示") {
                Picker("外觀", selection: $appearance) { Text("跟隨系統").tag("system"); Text("淺色").tag("light"); Text("深色").tag("dark") }
                NavigationLink("複利與現金流試算") { PlanningView() }
                NavigationLink("ETF 比較") { ComparisonView() }
            }
            Section("個人富果行情") {
                SecureField("輸入個人 API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("儲存至 iPhone 鑰匙圈") {
                    do { try QuoteKeychain.save(key); key = ""; keyStatus = "已儲存；尚未驗證授權，請在 ETF 詳情查詢行情。" } catch { store.message = error.localizedDescription }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("移除行情金鑰", role: .destructive) {
                    do { try QuoteKeychain.remove(); key = ""; keyStatus = "已移除" } catch { store.message = error.localizedDescription }
                }
                Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                Text("只向富果傳送行情金鑰；金鑰不會包含在備份中。行情查詢依你的資料方案，成分股需要對應授權。").font(.caption).foregroundStyle(.secondary)
                Link("富果行情文件", destination: URL(string: "https://developer.fugle.tw/docs/data/intro/")!)
            }
            Section("資料與備份") {
                Button(store.storageBlocked ? "匯出原始紀錄檔" : "匯出備份 JSON") {
                    do { document = BackupDocument(data: try store.exportBytes()); exporting = true } catch { store.message = error.localizedDescription }
                }
                Button("匯入舊版／原生版備份") { importing = true }
                Text("支援舊版 1.5.0 匯出的備份。匯入前顯示筆數並確認，原檔另存復原副本。").font(.caption).foregroundStyle(.secondary)
                Button { Task { await store.refreshCatalog() } } label: { HStack { Text("更新上市 ETF 名單"); if store.refreshing { ProgressView() } } }.disabled(store.refreshing)
                Text("\(store.catalogStatus) · \(store.catalog?.records.count ?? 0) 個代碼").font(.caption)
                Text(store.catalog?.coverage ?? "尚無名單").font(.caption).foregroundStyle(.secondary)
            }
            Section("我的券商") {
                Text("跨券商自動同步尚未開放").font(.headline)
                Text("目前可在持有紀錄登錄券商名稱。無需券商登入密碼；此版不提供交易或下單。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("關於 ETF 袋著走") {
                Text("把你的 ETF，都袋著走。")
                LabeledContent("原生版", value: "0.1.0 · 基於既有 1.5.0")
                NavigationLink("三種投資角色的判斷方式") { ClassificationInfoView() }
                Link("證交所 ETF 資訊", destination: URL(string: "https://www.twse.com.tw/zh/ETFortune/index")!)
                Text("持有、配息及匯入成分資料儲存在本機；無帳號、廣告或追蹤 SDK。開啟官方連結會離開 App。裝置系統備份可能包含你的紀錄，請自行保管匯出檔。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("更多")
            .task { do { keyStatus = try QuoteKeychain.load() == nil ? "尚未設定金鑰" : "已儲存個人金鑰；授權依查詢結果。" } catch { keyStatus = error.localizedDescription } }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "ETFToGo-backup-\(Validation.day())") { result in if case .failure(let error) = result { store.message = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 5_000_000 else { throw AppError("備份不可超過 5 MB。") }
                    pendingImport = try Backup.decode(Data(contentsOf: url)); confirmImport = true
                } catch { pendingImport = nil; store.message = error.localizedDescription }
            }
            .confirmationDialog("取代目前紀錄？", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("確認匯入並取代", role: .destructive) { if let data = pendingImport { do { try store.restore(data); store.message = "備份匯入完成。" } catch { store.message = error.localizedDescription } }; pendingImport = nil }
                Button("取消", role: .cancel) { pendingImport = nil }
            } message: { Text("匯入 \(pendingImport?.planning.holdings.count ?? 0) 筆持有、\(pendingImport?.planning.dividends.count ?? 0) 筆配息。現有紀錄會先保存復原副本。") }
    }
}
struct ClassificationInfoView: View {
    var body: some View {
        List {
            ForEach(InvestmentRole.allCases) { role in Section(role.title) { Text(role.explanation) } }
            Section("如何判斷") {
                Text("先檢查槓桿、反向、期貨、信用風險與產業集中，再考慮累積或收益取向。名稱與指數只提供初步線索，不能證明獲利穩定。")
                Text("本版尚未接入足以檢驗穩定性的歷史含息報酬。印鈔機均為候選，待查核年度總報酬、最大回撤、波動率與獲利一致性；不以高配息冒充穩定獲利。")
                Text("資料不足顯示「待核驗」，這是狀態，不是第四個投資角色。三類不是官方風險等級，也不是買賣建議。")
                Text("分類規則版本：\(RoleClassifier.version)").font(.caption).foregroundStyle(.secondary)
            }
            Section("查證資料") {
                Link("證交所 ETF 特性與風險", destination: URL(string: "https://www.twse.com.tw/zh/products/securities/etf/overview/introduction.html")!)
                Link("槓桿與反向 ETF", destination: URL(string: "https://www.twse.com.tw/zh/products/securities/etf/products/li.html")!)
                Link("配息與總報酬", destination: URL(string: "https://shl.twse.com.tw/newsArticle/detail/8a8221128df92773018e5ff3c1510010?tagName=")!)
            }
        }.navigationTitle("投資角色說明")
    }
}
