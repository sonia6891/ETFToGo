import SwiftUI
import UniformTypeIdentifiers

struct ComponentsView: View {
    @EnvironmentObject private var store: AppStore
    let code: String
    @State private var importing = false
    @State private var loading = false
    @State private var error: String?
    private var snapshot: ComponentSnapshot? { store.data.components?[code] }
    var body: some View {
        List {
            Section {
                Button { Task { loading = true; error = nil; defer { loading = false }; do { let data = try await MarketAPI.components(code); save(data) } catch { self.error = error.localizedDescription } } } label: { HStack { Text("查詢最新成分股"); if loading { ProgressView() } } }.disabled(loading || store.storageBlocked)
                Button("匯入成分股 JSON") { importing = true }.disabled(store.storageBlocked)
                Text("需有富果成分股資料權限，或匯入投信提供的資料。無資料時不顯示虛構比重。").font(.caption).foregroundStyle(.secondary)
                InlineError(text: error)
            }
            if let snapshot {
                Section {
                    LabeledContent("基準日", value: snapshot.date)
                    LabeledContent("來源", value: snapshot.source ?? "未提供")
                    LabeledContent("已列權重", value: "\(snapshot.totalWeight.formatted(.number.precision(.fractionLength(2))))%")
                    Text("這是已揭露股票部位，可能不含現金、債券、期貨等資產；不等於完整基金組合。").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(snapshot.components.sorted { $0.weight > $1.weight }) { c in LabeledContent("\(c.symbol) \(c.name ?? "")", value: "\(c.weight.formatted(.number.precision(.fractionLength(2))))%") }
            } else { ContentUnavailableView("等待成分資料", systemImage: "square.grid.2x2", description: Text("取得資料後，可查看權重及持股透視。")) }
        }.navigationTitle("\(code) 成分股")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_000_000 else { throw AppError("檔案不可超過 1 MB。") }
                    let data = try ComponentSnapshot.imported(Data(contentsOf: url), code: code); save(data)
                } catch { self.error = error.localizedDescription }
            }
    }
    private func save(_ value: ComponentSnapshot) { store.commit { if $0.components == nil { $0.components = [:] }; $0.components?[code] = value } }
}
struct InsightsView: View {
    @EnvironmentObject private var store: AppStore
    private var snapshots: [String: ComponentSnapshot] { store.data.components ?? [:] }
    private var rows: [Exposure] { ExposureCalculator.calculate(holdings: store.data.planning.holdings, snapshots: snapshots) }
    private var included: Int { store.data.planning.holdings.filter { $0.price != nil && snapshots[$0.code] != nil }.count }
    var body: some View {
        List {
            Section {
                Text("ETF 背後，真正投資了什麼？").font(.headline)
                Text("已納入 \(included)／\(store.data.planning.holdings.count) 筆持有。僅計算有成分資料及台幣參考價的部分，並非完整資產總額。").font(.footnote).foregroundStyle(.secondary)
            }
            if rows.isEmpty { ContentUnavailableView("尚缺成分資料", systemImage: "chart.pie", description: Text("在 ETF 詳情取得成分股，再填寫持有參考價。")) }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) { HStack { Text(row.name).font(.headline); Spacer(); Text(money(row.value)) }; Text("\(row.symbol) · 來自 \(row.funds.sorted().joined(separator: "、"))").font(.caption).foregroundStyle(.secondary) }
            }
        }.navigationTitle("持股透視")
    }
}
