import SwiftUI
import Charts

struct PlanningView: View {
    @EnvironmentObject private var store: AppStore
    @State private var plan = Plan()
    @State private var rows: [Projection] = []
    @State private var error: String?
    @State private var monthlyGoal = 10_000.0
    var body: some View {
        Form {
            Section("複利試算") {
                field("初始本金", value: $plan.principal)
                field("每月投入（月末）", value: $plan.monthly)
                Stepper("投資 \(plan.years) 年", value: $plan.years, in: 1...50)
                percent("年化含息總報酬率", value: $plan.totalReturn)
                percent("年配息比例", value: $plan.distributionRate)
                Picker("配息頻率", selection: $plan.frequency) { Text("每月").tag(12); Text("每季").tag(4); Text("每半年").tag(2); Text("每年").tag(1) }
                percent("股息再投入比例", value: $plan.reinvest)
                percent("股息扣費比例", value: $plan.deductionRate)
                Button("計算並儲存設定", action: calculate)
                InlineError(text: error)
            }
            if let result = rows.last {
                Section("假設情境結果") {
                    LabeledContent("累計投入", value: money(Decimal(result.contributed)))
                    LabeledContent("投資部位", value: money(Decimal(result.invested)))
                    LabeledContent("累計領出現金", value: money(Decimal(result.cash)))
                    LabeledContent("資產＋現金", value: money(Decimal(result.total)))
                    Chart(rows) { row in
                        LineMark(x: .value("年", row.year), y: .value("資產＋現金", row.total)).foregroundStyle(by: .value("系列", "資產＋現金"))
                        LineMark(x: .value("年", row.year), y: .value("累計投入", row.contributed)).foregroundStyle(by: .value("系列", "累計投入")).lineStyle(StrokeStyle(dash: [4]))
                    }.chartForegroundStyleScale(["資產＋現金": Color.blue, "累計投入": Color.gray]).frame(height: 180).accessibilityLabel("假設報酬下的資產與投入曲線")
                    Text("藍線：資產＋現金；灰虛線：累計投入。配息先自資產扣除再分配，避免重複計算收益。固定報酬率僅供情境試算，不是預測。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("每月現金流目標") {
                field("希望每月領取", value: $monthlyGoal)
                if monthlyGoal.isFinite && monthlyGoal >= 0 && monthlyGoal <= 100_000_000 && (try? plan.validate()) != nil {
                    if plan.distributionRate > 0 {
                        LabeledContent("估算所需本金", value: money(Decimal(monthlyGoal * 12 / (plan.distributionRate * (1 - plan.deductionRate)))))
                    } else { Text("配息比例為零，無法估算所需本金。") }
                } else { Text("請填有效目標與試算參數。").foregroundStyle(.red) }
                Text("按上方假設配息比例估算；不代表每月固定入帳，也不是安全提領率。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("試算工具").onAppear { plan = store.data.planning.plan; rows = (try? Finance.project(plan)) ?? [] }
            .onChange(of: plan) { _, _ in rows = []; error = nil }
    }
    private func field(_ title: String, value: Binding<Double>) -> some View { HStack { Text(title); Spacer(); TextField(title, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 140) } }
    private func percent(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title); Spacer(); TextField(title, value: Binding(get: { value.wrappedValue * 100 }, set: { value.wrappedValue = $0 / 100 }), format: .number).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).frame(maxWidth: 90); Text("%") }
    }
    private func calculate() {
        do { rows = try Finance.project(plan); error = nil; store.commit { $0.planning.plan = plan } } catch { rows = []; self.error = error.localizedDescription }
    }
}
