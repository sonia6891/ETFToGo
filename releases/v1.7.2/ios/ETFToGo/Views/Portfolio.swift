import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject private var store: AppStore
    @State private var add = false
    @State private var editing: Holding?
    @State private var deleting: Holding?
    var body: some View {
        List {
            Section {
                LabeledContent("總投入成本（台幣）", value: money(Finance.summary(store.data.planning.holdings).cost))
                Text("持有紀錄由你登錄；券商自動同步尚未開放。").font(.footnote).foregroundStyle(.secondary)
                NavigationLink("我的持股透視") { InsightsView() }
            }
            if store.data.planning.holdings.isEmpty {
                ContentUnavailableView("還沒有持有紀錄", systemImage: "wallet.pass", description: Text("按右上角＋，輸入股數與總成本。"))
            }
            ForEach(store.data.planning.holdings) { h in
                Button { editing = h } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text("\(h.code) \(h.name)").font(.headline); Spacer(); Text("\(h.shares) 股").font(.subheadline) }
                        HStack { Text(h.broker ?? "手動登錄"); Spacer(); Text("成本 \(money(h.cost))") }.font(.caption).foregroundStyle(.secondary)
                        if let date = h.priceDate { Text("台幣參考市值 \(money(h.value)) · \(date)").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }.foregroundStyle(.primary).swipeActions { Button("刪除", role: .destructive) { deleting = h } }
            }
        }.navigationTitle("我的持有")
            .toolbar { Button { add = true } label: { Image(systemName: "plus") }.accessibilityLabel("新增持有") }
            .sheet(isPresented: $add) { HoldingEditor() }
            .sheet(item: $editing) { HoldingEditor(holding: $0) }
            .alert("刪除這筆持有？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("刪除", role: .destructive) { if let h = deleting { store.commit { $0.planning.holdings.removeAll { $0.id == h.id } } }; deleting = nil }
            } message: { Text("配息紀錄會保留。") }
    }
}

struct HoldingEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let identifier: String
    @State private var code: String
    @State private var name: String
    @State private var shares: String
    @State private var unit = "shares"
    @State private var cost: String
    @State private var price: String
    @State private var priceDate: Date
    @State private var broker: String
    @State private var error: String?
    init(holding: Holding? = nil, etf: ETF? = nil) {
        identifier = holding?.id ?? UUID().uuidString
        _code = State(initialValue: holding?.code ?? etf?.code ?? "")
        _name = State(initialValue: holding?.name ?? etf?.name ?? "")
        _shares = State(initialValue: holding.map { String($0.shares) } ?? "")
        _cost = State(initialValue: holding.map { NSDecimalNumber(decimal: $0.cost).stringValue } ?? "")
        _price = State(initialValue: holding?.price.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _priceDate = State(initialValue: holding?.priceDate.flatMap { Validation.dateFormatter().date(from: $0) } ?? Date())
        _broker = State(initialValue: holding?.broker ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("ETF") {
                    TextField("代碼，例如 0050", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .onChange(of: code) { _, value in if let e = store.etf(value.trimmingCharacters(in: .whitespaces).uppercased()) { name = e.name } }
                    TextField("名稱", text: $name)
                    TextField("券商名稱（選填）", text: $broker)
                }
                Section("持有數量與成本") {
                    TextField("數量", text: $shares).keyboardType(.numberPad)
                    Picker("單位", selection: $unit) { Text("股").tag("shares"); Text("張（1,000 股）").tag("lots") }.pickerStyle(.segmented)
                    TextField("總成本（台幣，含費用）", text: $cost).keyboardType(.decimalPad)
                }
                Section {
                    TextField("換算台幣後的每股參考價", text: $price).keyboardType(.decimalPad)
                    DatePicker("價格日期", selection: $priceDate, displayedComponents: .date)
                } header: { Text("選填：估算參考市值") } footer: { Text("所有成本與參考價統一用台幣。外幣級別請先換算；參考價不是自動同步行情。") }
                InlineError(text: error)
            }.navigationTitle("持有紀錄").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("儲存", action: save).disabled(store.storageBlocked) }
                }
        }
    }
    private func save() {
        do {
            guard let count = Int(shares), count > 0, count <= (unit == "lots" ? 10_000_000 : 10_000_000_000), let amount = decimalInput(cost) else { throw AppError("請填有效整數數量與總成本。") }
            let reference: Decimal? = price.isEmpty ? nil : decimalInput(price)
            guard price.isEmpty || reference != nil else { throw AppError("參考價格式不正確。") }
            let h = Holding(id: identifier, code: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), shares: count * (unit == "lots" ? 1000 : 1), cost: amount, price: reference, priceDate: reference == nil ? nil : Validation.day(priceDate), broker: broker.isEmpty ? nil : broker)
            try store.upsert(h); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
