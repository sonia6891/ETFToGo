import SwiftUI

struct DividendsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var month = Date()
    @State private var add = false
    @State private var editing: Dividend?
    @State private var deleting: Dividend?
    private var monthKey: String { String(Validation.day(month).prefix(7)) }
    private var rows: [Dividend] { store.data.planning.dividends.filter { $0.paymentDate.hasPrefix(monthKey) }.sorted { $0.paymentDate < $1.paymentDate } }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Taipei")!; return c }
    private var cells: [String?] {
        guard let first = Validation.dateFormatter().date(from: monthKey + "-01"), let days = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let padding = calendar.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: padding) + days.map { String(format: "%@-%02d", monthKey, $0) }
    }
    var body: some View {
        List {
            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("上一個月")
                    Spacer(); Text(monthKey).font(.headline.monospacedDigit()); Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("下一個月")
                }.buttonStyle(.borderless)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                    ForEach(["日","一","二","三","四","五","六"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    ForEach(cells.indices, id: \.self) { index in
                        if let day = cells[index] {
                            VStack(spacing: 4) {
                                Text(String(Int(day.suffix(2)) ?? 0)).font(.caption)
                                Circle().fill(rows.contains { $0.paymentDate == day } ? Color.blue : Color.clear).frame(width: 5, height: 5)
                            }.frame(maxWidth: .infinity).padding(.vertical, 3).background(day == Validation.day() ? Color.blue.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        } else { Color.clear.frame(height: 30) }
                    }
                }.padding(.vertical, 8)
                LabeledContent("本月已入帳", value: money(rows.filter { $0.status == .received }.reduce(0) { $0 + $1.amount }))
                LabeledContent("本月待入帳／預估", value: money(rows.filter { $0.status != .received }.reduce(0) { $0 + $1.amount }))
            }
            Section("配息紀錄") {
                if rows.isEmpty { Text("這個月尚無紀錄。").foregroundStyle(.secondary) }
                ForEach(rows) { d in
                    Button { editing = d } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text("\(d.code) \(d.name)").font(.headline); Spacer(); Text(money(d.amount)).font(.subheadline.bold()) }
                            Text("\(d.paymentDate) · \(d.status.title)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }.foregroundStyle(.primary).swipeActions { Button("刪除", role: .destructive) { deleting = d } }
                }
            }
            Text("手動配息記帳；預估、公告與實收分開。未啟用自動配息同步或推播通知。").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("股息月曆")
            .toolbar { Button { add = true } label: { Image(systemName: "plus") }.accessibilityLabel("新增配息") }
            .sheet(isPresented: $add) { DividendEditor() }.sheet(item: $editing) { DividendEditor(dividend: $0) }
            .alert("刪除這筆配息？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("刪除", role: .destructive) { if let d = deleting { store.commit { $0.planning.dividends.removeAll { $0.id == d.id } } }; deleting = nil }
            }
    }
    private func shift(_ offset: Int) { if let next = calendar.date(byAdding: .month, value: offset, to: month), (1900...2200).contains(calendar.component(.year, from: next)) { month = next } }
}

struct DividendEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let identifier: String
    @State private var code: String
    @State private var name: String
    @State private var paymentDate: Date
    @State private var hasExDate: Bool
    @State private var exDate: Date
    @State private var shares: String
    @State private var perShare: String
    @State private var deductions: String
    @State private var status: DividendStatus
    @State private var actual: String
    @State private var source: String
    @State private var error: String?
    init(dividend d: Dividend? = nil) {
        identifier = d?.id ?? UUID().uuidString
        _code = State(initialValue: d?.code ?? ""); _name = State(initialValue: d?.name ?? "")
        _paymentDate = State(initialValue: d.flatMap { Validation.dateFormatter().date(from: $0.paymentDate) } ?? Date())
        _hasExDate = State(initialValue: d?.exDate != nil); _exDate = State(initialValue: d?.exDate.flatMap { Validation.dateFormatter().date(from: $0) } ?? Date())
        _shares = State(initialValue: d.map { String($0.eligibleShares) } ?? "")
        _perShare = State(initialValue: d.map { NSDecimalNumber(decimal: $0.perShare).stringValue } ?? "")
        _deductions = State(initialValue: d.map { NSDecimalNumber(decimal: $0.deductions).stringValue } ?? "0")
        _status = State(initialValue: d?.status ?? .planned)
        _actual = State(initialValue: d?.actualReceived.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _source = State(initialValue: d?.sourceUrl ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("ETF") {
                    TextField("代碼", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .onChange(of: code) { _, value in if let e = store.etf(value.uppercased()) { name = e.name } }
                    TextField("名稱", text: $name)
                }
                Section("日期") {
                    DatePicker("入帳日", selection: $paymentDate, displayedComponents: .date)
                    Toggle("填寫除息日", isOn: $hasExDate)
                    if hasExDate { DatePicker("除息日", selection: $exDate, displayedComponents: .date) }
                }
                Section("金額（統一使用台幣）") {
                    TextField("本次具配息資格股數", text: $shares).keyboardType(.numberPad)
                    TextField("每股配息", text: $perShare).keyboardType(.decimalPad)
                    TextField("扣費金額", text: $deductions).keyboardType(.decimalPad)
                    Picker("狀態", selection: $status) { ForEach(DividendStatus.allCases) { Text($0.title).tag($0) } }
                    if status == .received { TextField("實際入帳金額", text: $actual).keyboardType(.decimalPad) }
                }
                Section("來源（選填）") { TextField("https://…", text: $source).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled() }
                InlineError(text: error)
            }.navigationTitle("配息紀錄").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("儲存", action: save).disabled(store.storageBlocked) } }
        }
    }
    private func save() {
        do {
            guard let count = Int(shares), let payout = decimalInput(perShare), let fees = decimalInput(deductions) else { throw AppError("請填有效股數與配息金額。") }
            let received = status == .received ? decimalInput(actual) : nil
            let d = Dividend(id: identifier, code: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), paymentDate: Validation.day(paymentDate), exDate: hasExDate ? Validation.day(exDate) : nil, eligibleShares: count, perShare: payout, deductions: fees, status: status, actualReceived: received, sourceUrl: source.trimmingCharacters(in: .whitespacesAndNewlines))
            try store.upsert(d); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
