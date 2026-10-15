import Foundation

struct AppError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum InvestmentRole: String, Codable, CaseIterable, Identifiable {
    case piggyBank, printer, slotMachine
    var id: String { rawValue }
    var title: String {
        switch self { case .piggyBank: return "存錢筒"; case .printer: return "印鈔機"; case .slotMachine: return "老虎機" }
    }
    var subtitle: String {
        switch self { case .piggyBank: return "長期累積"; case .printer: return "持續獲利取向"; case .slotMachine: return "高波動取向" }
    }
    var explanation: String {
        switch self {
        case .piggyBank: return "以長期累積資產為目標；不是銀行存款，也不保本。短債與股票的波動仍不同。"
        case .printer: return "尋找較穩定的含息總報酬；高配息不是穩定獲利的證據。未取得完整歷史資料時只列為候選。"
        case .slotMachine: return "槓桿、反向、產業集中或其他高敏感度策略，可能大漲也可能大跌，不代表一定有高報酬。"
        }
    }
    var symbol: String {
        switch self { case .piggyBank: return "banknote"; case .printer: return "printer.fill"; case .slotMachine: return "bolt.trianglebadge.exclamationmark.fill" }
    }
}

struct ETF: Codable, Identifiable, Equatable {
    var code: String
    var name: String
    var fullName: String
    var fundType: String
    var indexName: String
    var market: String
    var sourceDate: String
    var listingDate: String?
    var sourceURL: String
    var dateLabel: String? = nil
    var id: String { code }
}

extension ETF {
    var strategy: String {
        let text = name + " " + indexName + " " + fundType
        if text.contains("槓桿") || text.contains("反向") { return "槓桿／反向" }
        if text.contains("期貨") { return "期貨／商品" }
        if text.contains("主動") { return "主動型" }
        if text.contains("債") { return "債券" }
        if ["高股息", "高息", "優息", "優利", "股利", "收益"].contains(where: text.contains) { return "高股息／收益" }
        if RoleClassifier.classify(self).role == .slotMachine { return "產業主題" }
        if RoleClassifier.classify(self).role == .piggyBank { return "市值／大盤" }
        if ["ESG", "永續", "低波", "因子", "等權", "動能", "價值"].contains(where: text.contains) { return "因子／其他策略" }
        return "待分類"
    }
}

struct Catalog: Codable {
    var records: [ETF]
    var fetchedAt: String
    var coverage: String
    var sources: [String]
    func validate() throws {
        guard !records.isEmpty, records.count <= 5000, Set(records.map(\.code)).count == records.count else { throw AppError("ETF 名單為空或代碼重複，保留原名單。") }
        for e in records {
            guard Validation.isCode(e.code), !e.name.isEmpty, e.name.count <= 120, Validation.isDate(e.sourceDate), e.market == "TWSE" else { throw AppError("ETF 名單欄位異常，保留原名單。") }
        }
    }
}

struct Classification: Equatable {
    let role: InvestmentRole?
    let status: String
    let reason: String
    let risk: String
    let historyVerified: Bool
}

/// App-defined investment roles, never official risk ratings or a promise of returns.
/// Missing price/dividend history cannot establish stable profitability.
enum RoleClassifier {
    static let version = "role-1.0"
    static func classify(_ e: ETF) -> Classification {
        let s = "\(e.name) \(e.fullName) \(e.fundType) \(e.indexName)".lowercased()
        func contains(_ words: [String]) -> Bool { words.contains { s.contains($0.lowercased()) } }
        func result(_ role: InvestmentRole?, _ status: String, _ reason: String, _ risk: String) -> Classification {
            Classification(role: role, status: status, reason: reason, risk: risk, historyVerified: false)
        }
        if contains(["槓桿", "反向", "正2", "反1", "正向兩倍", "兩倍", "2倍"]) || e.code.hasSuffix("L") || e.code.hasSuffix("R") {
            return result(.slotMachine, "結構判定", "官方類型或名稱顯示槓桿／反向結構，通常以單日倍數為目標。", "高｜每日重設與複利偏離；長期結果不是指數的固定倍數。")
        }
        if contains(["非投資等級", "高收益債", "新興市場債", "新興美元債", "新興債"]) {
            return result(.slotMachine, "策略初判", "名稱或指數含較高信用／新興市場曝險。", "偏高｜信用、匯率及流動性風險；仍須檢查實際持倉。")
        }
        if contains(["期貨", "期信", "石油", "原油", "vix", "波動率"]) {
            return result(.slotMachine, "結構初判", "商品或期貨結構，須考慮轉倉與追蹤差異。", "偏高｜不適合僅因價格低而視為存錢工具。")
        }
        if contains(["半導體", "科技", "生技", "機器人", "電動車", "航太", "5g", "網路", "人工智慧", "金融", "ic設計", "數位", "太空", "綠能", "nasdaq", "納斯達克", "那斯達克", "fang"]) || s.range(of: "\\bai\\b", options: .regularExpression) != nil {
            return result(.slotMachine, "集中度初判", "名稱或指數具有產業／主題集中，優先於高息字樣判斷。", "偏高｜產業景氣和集中度可能放大波動；未核驗歷史波動。")
        }
        if contains(["20年", "20+", "20yr", "20y", "長天期", "長期公債", "長債", "15年", "15+", "10年", "10+"]) && contains(["債", "bond", "treasury"]) {
            return result(.slotMachine, "利率敏感度初判", "長天期債券對利率較敏感，不能因固定配息就視為穩定獲利。", "偏高｜利率及匯率風險；分類是 App 初判。")
        }
        if contains(["0-1", "0至1", "0到1", "1-3", "1至3", "短期", "短天期", "短債"]) && contains(["公債", "政府債", "國庫券", "treasury"]) {
            return result(.piggyBank, "策略初判", "短天期政府債策略偏向保守累積。", "仍有匯率、利率與價格風險；不是保本存款。")
        }
        if contains(["高股息", "高息", "優息", "優利", "股利", "收益", "投資級", "投資等級", "公司債", "債券"]) {
            return result(.printer, "候選・待核驗", "具有收益／配息取向；仍須以含息報酬、回撤與跨年度表現驗證獲利穩定性。", "尚未證實穩定獲利；配息不等於總報酬，也可能減少。")
        }
        if contains(["主動式", "主動", "active"]) {
            return result(nil, "待核驗", "主動管理不能直接推定穩定或高風險，需取得持倉與歷史報酬。", "資料不足，暫不強制放入三類。")
        }
        if contains(["台灣50", "臺灣50", "中型100", "s&p 500", "s&p500", "標普500", "標準普爾500", "全市場", "全世界", "全球股票", "msci臺灣", "msci台灣", "加權", "市值", "富櫃50", "摩台", "msci world", "msci acwi"]) {
            return result(.piggyBank, "策略初判", "大盤／廣泛市場指數適合作為長期累積取向的研究起點。", "股票仍可能大幅回撤；單一市場或權重集中仍有風險。")
        }
        return result(nil, "待核驗", "目前公開欄位不足以判斷投資角色，需檢查指數規則、持倉與含息報酬。", "不以名稱猜測穩定獲利。")
    }
}

enum Validation {
    static let locale = Locale(identifier: "en_US_POSIX")
    static func dateFormatter() -> DateFormatter {
        let f = DateFormatter(); f.locale = locale; f.timeZone = TimeZone(identifier: "Asia/Taipei"); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false; return f
    }
    static func day(_ date: Date = Date()) -> String { dateFormatter().string(from: date) }
    static func isDate(_ s: String) -> Bool {
        guard s.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil, s >= "1900-01-01", s <= "2200-12-31", let d = dateFormatter().date(from: s) else { return false }
        return day(d) == s
    }
    static func isCode(_ s: String) -> Bool { s.range(of: "^[A-Za-z0-9.-]{1,20}$", options: .regularExpression) != nil }
    static func amount(_ n: Decimal, max: Decimal = 1_000_000_000_000_000) -> Bool { !n.isNaN && n >= 0 && n <= max }
    static func text(_ s: String, max: Int) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.count <= max }
}

struct Holding: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var code: String
    var name: String
    var shares: Int
    var cost: Decimal
    var price: Decimal?
    var priceDate: String?
    var broker: String? = nil
    var value: Decimal? { price.map { $0 * Decimal(shares) } }
    func validate() throws {
        guard Validation.text(id, max: 80), Validation.isCode(code), Validation.text(name, max: 120), shares > 0, shares <= 10_000_000_000, Validation.amount(cost, max: 10_000_000_000_000) else { throw AppError("持有紀錄的代碼、名稱、股數或成本不正確。") }
        if let price { guard Validation.amount(price, max: 10_000_000), let date = priceDate, Validation.isDate(date) else { throw AppError("參考價須為有效金額，並填寫價格日期。") } }
        if let priceDate, !Validation.isDate(priceDate) { throw AppError("價格日期不正確。") }
        if let broker, broker.count > 120 { throw AppError("券商名稱過長。") }
    }
}

enum DividendStatus: String, Codable, CaseIterable, Identifiable {
    case planned, announced, received
    var id: String { rawValue }
    var title: String { switch self { case .planned: return "預估"; case .announced: return "已公告"; case .received: return "已入帳" } }
}
struct Dividend: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var code: String
    var name: String
    var paymentDate: String
    var exDate: String?
    var eligibleShares: Int
    var perShare: Decimal
    var deductions: Decimal
    var status: DividendStatus
    var actualReceived: Decimal?
    var sourceUrl: String
    var amount: Decimal { status == .received ? (actualReceived ?? 0) : Decimal(eligibleShares) * perShare - deductions }
    func validate() throws {
        guard Validation.text(id, max: 80), Validation.isCode(code), Validation.text(name, max: 120), Validation.isDate(paymentDate), eligibleShares > 0, eligibleShares <= 10_000_000_000, Validation.amount(perShare, max: 100_000), Validation.amount(deductions, max: Decimal(eligibleShares) * perShare) else { throw AppError("配息紀錄欄位或扣費不正確。") }
        if let exDate { guard Validation.isDate(exDate), paymentDate >= exDate else { throw AppError("入帳日不可早於除息日。") } }
        if status == .received && actualReceived == nil { throw AppError("已入帳紀錄須填實際入帳金額。") }
        if let actualReceived, !Validation.amount(actualReceived) { throw AppError("實際入帳金額不正確。") }
        if !sourceUrl.isEmpty {
            guard sourceUrl.count <= 2048, let url = URL(string: sourceUrl), ["https", "http"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil else { throw AppError("來源連結不正確。") }
        }
    }
}

struct Plan: Codable, Equatable {
    var principal: Double = 100_000
    var monthly: Double = 5_000
    var years: Int = 10
    var totalReturn: Double = 0.06
    var distributionRate: Double = 0.04
    var frequency: Int = 4
    var reinvest: Double = 1
    var deductionRate: Double = 0
    func validate() throws {
        guard principal.isFinite, (0...1e12).contains(principal), monthly.isFinite, (0...1e9).contains(monthly), (1...50).contains(years), totalReturn.isFinite, (-0.9...0.5).contains(totalReturn), distributionRate.isFinite, (0...0.3).contains(distributionRate), [1,2,4,12].contains(frequency), reinvest.isFinite, (0...1).contains(reinvest), deductionRate.isFinite, (0...0.2).contains(deductionRate) else { throw AppError("試算參數超出範圍。") }
    }
}
struct Projection: Identifiable {
    var year: Int
    var invested: Double
    var cash: Double
    var contributed: Double
    var id: Int { year }
    var total: Double { invested + cash }
}
enum Finance {
    static func project(_ p: Plan) throws -> [Projection] {
        try p.validate()
        let rate = exp(log1p(p.totalReturn)/12) - 1
        var invested = p.principal, cash = 0.0, contributed = p.principal
        var rows = [Projection(year: 0, invested: invested, cash: cash, contributed: contributed)]
        for month in 1...(p.years * 12) {
            invested *= 1 + rate
            if month % (12 / p.frequency) == 0 {
                let gross = invested * p.distributionRate / Double(p.frequency)
                let net = gross * (1 - p.deductionRate)
                invested -= gross; invested += net * p.reinvest; cash += net * (1 - p.reinvest)
            }
            invested += p.monthly; contributed += p.monthly
            if month % 12 == 0 { rows.append(Projection(year: month/12, invested: invested, cash: cash, contributed: contributed)) }
        }
        return rows
    }
    static func summary(_ holdings: [Holding]) -> (cost: Decimal, pricedCost: Decimal, value: Decimal?, count: Int) {
        let known = holdings.filter { $0.price != nil }
        return (holdings.reduce(0) { $0 + $1.cost }, known.reduce(0) { $0 + $1.cost }, known.isEmpty ? nil : known.reduce(0) { $0 + ($1.value ?? 0) }, known.count)
    }
}
