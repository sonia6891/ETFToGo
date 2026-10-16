import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI
import Vision

struct BrokerView: View {
    @EnvironmentObject var store: PortfolioStore
    @State private var broker = ""
    @State private var account = ""
    @State private var table: CSVTable?
    @State private var mapping = BrokerMapping(symbol: -1, name: -1, shares: -1, cost: -1)
    @State private var importing = false
    @State private var shots: [PhotosPickerItem] = []
    @State private var reading = false
    @State private var drafts: [ScreenshotImport.Draft] = []
    @State private var preview: BrokerPreview?
    @State private var confirmation = false
    @State private var replace = false
    @State private var message: String?
    var body: some View { Form {
        Section("所有券商：持有對帳單匯入") {
            Text("可匯入券商匯出的 CSV，再選擇對應欄位；不能匯出 CSV 的券商（例如國泰證券），可改用庫存畫面截圖。這是檔案匯入，尚未連接券商帳戶自動同步。").font(.subheadline)
            TextField("券商名稱", text: $broker).accessibilityIdentifier("broker-import-name")
            TextField("帳戶暱稱（例如主要帳戶）", text: $account).accessibilityIdentifier("broker-import-account")
            Text("同券商同暱稱會更新同一組庫存；請勿輸入完整帳號或密碼。成本請先換算為台幣。").font(.caption).foregroundStyle(.secondary)
            Button("選擇庫存 CSV") { importing = true }
            PhotosPicker(selection: $shots, maxSelectionCount: 10, matching: .images) { Text("從截圖匯入") }.disabled(reading).accessibilityIdentifier("broker-import-screenshots")
            Text("可一次選多張庫存畫面截圖（最多 10 張）。文字只在這支手機上辨識，不會上傳。").font(.caption).foregroundStyle(.secondary)
        }
        if reading { Section { HStack(spacing: 10) { ProgressView(); Text("正在辨識截圖文字…") } } }
        if let table {
            Section("對應欄位 · \(table.rows.count) 筆") {
                column("股票／ETF 代號", selection: $mapping.symbol, table: table)
                column("名稱（選填）", selection: $mapping.name, table: table)
                column("持有數量", selection: $mapping.shares, table: table)
                column("成本", selection: $mapping.cost, table: table)
                Toggle("數量以張為單位（1 張 = 1,000 股）", isOn: $mapping.lots)
                Toggle("成本欄是總成本", isOn: $mapping.totalCost)
                Text(mapping.totalCost ? "總成本會除以股數，轉成每股成本。" : "成本欄會直接當成每股台幣成本。").font(.caption)
                Button("驗證並預覽") { do { preview = try BrokerPreview.make(table: table, mapping: mapping, broker: broker, account: account, funds: store.funds, stock: { store.stock($0) }); message = nil } catch { preview = nil; message = error.localizedDescription } }
            }
        }
        if !drafts.isEmpty { screenshotRows }
        if let preview {
            Section("確認匯入內容") {
                LabeledContent("券商", value: preview.broker); LabeledContent("筆數", value: "\(preview.holdings.count)"); LabeledContent("總成本（台幣）", value: money(preview.totalCost))
                ForEach(preview.holdings.prefix(20)) { h in VStack(alignment: .leading) { Text("\(h.symbol) \(h.name)"); Text("\(decimal(h.shares)) 股 · 總成本 \(money(h.cost))").font(.caption).foregroundStyle(.secondary) } }
                Toggle("替換此帳戶先前匯入的庫存", isOn: $replace)
                Text(replace ? "會移除這個帳戶先前匯入、但本次檔案已沒有的部位。其他帳戶與手動紀錄保留。" : "只新增或更新本檔部位；檔案未列出的舊部位保留。").font(.caption)
                Button("確認匯入 \(preview.holdings.count) 筆") { confirmation = true }
            }
        }
        if let message { Section { Text(message) } }
        Section("帳戶授權同步") {
            Text("各券商需分別提供 API、帳務查詢權限與憑證。目前沒有已驗證的自動同步帳戶；不會用行情金鑰冒充帳戶授權。").font(.footnote)
            Link("富果合作券商與申請說明", destination: URL(string: "https://developer.fugle.tw/docs/trading/brokerage_partner/")!)
            Link("富邦官方 API 說明", destination: URL(string: "https://www.fbs.com.tw/TradeAPI/docs/trading/quickstart/")!)
            Link("永豐官方帳務 API 說明", destination: URL(string: "https://sinotrade.github.io/tutor/accounting/position/")!)
        }
    }.navigationTitle("券商持有資料").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            preview = nil; table = nil; drafts = []; message = nil
            do {
                let value = try CSVTable.parse(DataChecks.readFile(result.get())); table = value
                mapping = BrokerMapping(guessing: value)
            } catch { message = error.localizedDescription }
        }
        .onChange(of: shots) { _, items in if !items.isEmpty { Task { await read(items) } } }
        .confirmationDialog("將匯入庫存，並先保存一份復原備份。", isPresented: $confirmation, titleVisibility: .visible) { Button("匯入") { do { if let preview { try store.importBroker(preview, replaceAccount: replace); message = "已匯入 \(preview.holdings.count) 筆。"; self.preview = nil; table = nil; drafts = [] } } catch { message = error.localizedDescription } }; Button("取消", role: .cancel) {} }
        .onChange(of: broker) { _, _ in preview = nil }.onChange(of: account) { _, _ in preview = nil }.onChange(of: drafts) { _, _ in preview = nil }
        .onChange(of: mapping.symbol) { _, _ in preview = nil }.onChange(of: mapping.name) { _, _ in preview = nil }.onChange(of: mapping.shares) { _, _ in preview = nil }.onChange(of: mapping.cost) { _, _ in preview = nil }.onChange(of: mapping.lots) { _, _ in preview = nil }.onChange(of: mapping.totalCost) { _, _ in preview = nil }
    }
    private func column(_ title: String, selection: Binding<Int>, table: CSVTable) -> some View { Picker(title, selection: selection) { Text("未選擇").tag(-1); ForEach(table.headers.indices, id: \.self) { i in Text("\(i + 1). \(table.headers[i])").tag(i) } } }
    /// What the screenshots showed, for the user to check against them before the usual preview.
    private var screenshotRows: some View {
        Section {
            ForEach($drafts) { $draft in
                VStack(alignment: .leading, spacing: 6) {
                    Text(listedName(draft.symbol)).font(.headline)
                    LabeledContent("代號") { TextField("例如 2330", text: $draft.symbol).textInputAutocapitalization(.characters).autocorrectionDisabled().multilineTextAlignment(.trailing) }
                    LabeledContent("股數") { TextField("未辨識，請填寫", text: $draft.shares).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    LabeledContent("總成本（元）") { TextField("未辨識，請填寫", text: $draft.cost).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }.padding(.vertical, 2)
            }.onDelete { drafts.remove(atOffsets: $0) }
            Button("新增一筆") { drafts.append(ScreenshotImport.Draft()) }
            Button("驗證並預覽") { do { preview = try BrokerPreview.make(drafts: drafts, broker: broker, account: account, funds: store.funds, stock: { store.stock($0) }); message = nil } catch { preview = nil; message = error.localizedDescription } }
        } header: {
            Text("截圖辨識結果 · \(drafts.count) 筆")
        } footer: {
            Text("請逐筆對照截圖確認或修改。沒辨識到的欄位會留空，請自行填入；股數以股為單位（1 張 = 1,000 股），總成本填含手續費的台幣金額。向左滑可刪除一筆。")
        }
    }
    private func listedName(_ symbol: String) -> String {
        let code = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return "新的一筆" }
        return store.funds.first { $0.id == code }?.name ?? store.stock(code)?.name ?? "\(code)（不在股票或 ETF 名單）"
    }
    /// Reads the chosen screenshots one by one, then lists what was found for the user to check.
    private func read(_ items: [PhotosPickerItem]) async {
        reading = true; preview = nil; table = nil; drafts = []; message = nil
        let funds = Set(store.funds.map(\.id)), stocks = store.stockSnapshot?.byID ?? [:]
        var pages: [[ScreenshotImport.Row]] = [], failed = 0
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { failed += 1; continue }
                let lines = try await Task.detached(priority: .userInitiated) { try ScreenshotReader.lines(data) }.value
                pages.append(ScreenshotImport.parse(lines) { funds.contains($0) || stocks[$0] != nil })
            } catch { failed += 1 }
        }
        drafts = ScreenshotImport.merge(pages).map { ScreenshotImport.Draft($0) }
        var notes: [String] = []
        if !drafts.isEmpty { notes.append("已從 \(pages.count) 張截圖讀出 \(drafts.count) 筆，請在上方逐筆對照確認。") }
        if failed > 0 { notes.append("有 \(failed) 張圖片無法辨識。") }
        if drafts.isEmpty && !pages.isEmpty { notes.append("截圖裡沒有找到股票或 ETF 名單中的代號。請確認截圖有顯示代號，或到「持有 › 新增持有」逐筆輸入。") }
        message = notes.isEmpty ? nil : notes.joined(separator: "\n")
        reading = false; shots = []
    }
}

/// Reads a screenshot's text with the system's text recognition, on this phone only (nothing is uploaded).
enum ScreenshotReader {
    static func lines(_ data: Data) throws -> [String] {
        guard let image = UIImage(data: data), let picture = image.cgImage else { throw AppDataError("無法讀取這張圖片。") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "en-US"]
        try VNImageRequestHandler(cgImage: picture, orientation: orientation(image.imageOrientation)).perform([request])
        let boxes = (request.results ?? []).compactMap { observation in observation.topCandidates(1).first.map { (text: $0.string, box: observation.boundingBox) } }
        return ScreenshotImport.lines(from: boxes)
    }
    private static func orientation(_ value: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch value {
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        default: return .up
        }
    }
}
