import Foundation
import CoreFoundation
import CoreGraphics

struct CSVTable {
    var headers: [String]
    var rows: [[String]]
    static func parse(_ bytes: Data) throws -> Self {
        guard bytes.count <= 5_000_000 else { throw AppDataError("CSV 不可超過 5 MB。") }
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        let utf16BOM = bytes.starts(with: [0xff,0xfe]) || bytes.starts(with: [0xfe,0xff])
        let decoded = utf16BOM ? String(data: bytes, encoding: .utf16) : (String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: big5))
        guard let text = decoded else { throw AppDataError("請將對帳單另存為 UTF-8 CSV。") }
        var rows: [[String]] = []; var row: [String] = []; var cell = ""; var quoted = false; var endedQuote = false
        let chars = Array(text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}")).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")); var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { cell.append("\""); i += 1 } else { quoted = false; endedQuote = true }
                } else { cell.append(c) }
            } else if c == "\"" {
                guard cell.isEmpty, !endedQuote else { throw AppDataError("CSV 引號格式錯誤。") }; quoted = true
            } else if c == "," || c == "\n" {
                row.append(cell.trimmingCharacters(in: .whitespacesAndNewlines)); cell = ""; endedQuote = false
                if c == "\n" { if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = [] }
            } else {
                guard !endedQuote || c == " " else { throw AppDataError("CSV 引號後出現不明字元。") }
                if !endedQuote { cell.append(c) }
            }
            i += 1
        }
        guard !quoted else { throw AppDataError("CSV 引號未結束，未匯入。") }
        row.append(cell.trimmingCharacters(in: .whitespacesAndNewlines)); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        guard rows.count >= 2, rows.count <= 10001 else { throw AppDataError("需要標題列與持有資料，最多 10,000 筆。") }
        var headers = rows.removeFirst(); headers[0] = headers[0].replacingOccurrences(of: "\u{feff}", with: "")
        guard headers.count <= 100, rows.allSatisfy({ $0.count == headers.count }) else { throw AppDataError("CSV 每列欄位數不一致。") }
        return Self(headers: headers, rows: rows)
    }
    /// The column titled with one of `names`, trying the names in order (so 總成本 wins over a plain 成本).
    func guess(_ names: [String]) -> Int {
        for name in names { if let i = headers.firstIndex(where: { $0.lowercased() == name }) { return i } }
        return -1
    }
}
struct BrokerMapping {
    var symbol: Int
    var name: Int
    var shares: Int
    var cost: Int
    var lots: Bool = false
    var totalCost: Bool = true
}
extension BrokerMapping {
    /// Picks columns by their titles, including 國泰證券's (股票代號、商品名稱、現股庫存、付出成本).
    init(guessing table: CSVTable) {
        self.init(symbol: table.guess(["代碼", "代號", "股票代號", "股票代碼", "證券代號", "商品代碼", "商品代號", "symbol", "code"]),
                  name: table.guess(["名稱", "股票名稱", "證券名稱", "商品名稱", "name"]),
                  shares: table.guess(["股數", "庫存股數", "現股庫存", "庫存數量", "數量", "shares", "quantity"]),
                  cost: table.guess(["總成本", "付出成本", "持有成本", "投資成本", "成本", "cost"]))
    }
}
struct BrokerPreview {
    var holdings: [Holding]
    var sourceAccount: String
    var broker: String
    var totalCost: Double { holdings.reduce(0) { $0 + $1.cost } }
    /// One position to import; `place` names it in error messages.
    private struct Entry { var place: String; var code: String; var name: String; var quantity: Double?; var cost: Double? }
    /// ETFs take the fund list's name and strategy; stocks are named from the stock list and left unclassified, as in the 新增持有 form.
    static func make(table: CSVTable, mapping: BrokerMapping, broker: String, account: String, funds: [Fund], stock: (String) -> StockInfo? = { StockSnapshot.bundled?.byID[$0] }) throws -> Self {
        guard [mapping.symbol, mapping.shares, mapping.cost].allSatisfy({ table.headers.indices.contains($0) }),
              Set([mapping.symbol, mapping.shares, mapping.cost]).count == 3 else { throw AppDataError("請指定不同的代號、數量與成本欄。") }
        let entries = table.rows.enumerated().map { offset, row in
            Entry(place: "第 \(offset + 2) 列", code: row[mapping.symbol].uppercased(), name: table.headers.indices.contains(mapping.name) ? row[mapping.name] : "",
                  quantity: number(row[mapping.shares]), cost: number(row[mapping.cost]))
        }
        return try build(entries, lots: mapping.lots, totalCost: mapping.totalCost, broker: broker, account: account, funds: funds, stock: stock)
    }
    /// The rows the user checked after reading screenshots: shares and total cost, both required.
    static func make(drafts: [ScreenshotImport.Draft], broker: String, account: String, funds: [Fund], stock: (String) -> StockInfo? = { StockSnapshot.bundled?.byID[$0] }) throws -> Self {
        guard !drafts.isEmpty else { throw AppDataError("沒有要匯入的持有。") }
        var entries: [Entry] = []
        for (offset, draft) in drafts.enumerated() {
            let code = draft.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), place = "第 \(offset + 1) 筆"
            guard !code.isEmpty else { throw AppDataError("\(place)還沒有代號，請填入或刪除這一筆。") }
            guard let quantity = number(draft.shares) else { throw AppDataError("\(place) \(code) 還沒有股數，請對照截圖填入。") }
            guard let cost = number(draft.cost) else { throw AppDataError("\(place) \(code) 還沒有總成本，請對照截圖填入。") }
            entries.append(Entry(place: place, code: code, name: "", quantity: quantity, cost: cost))
        }
        return try build(entries, lots: false, totalCost: true, broker: broker, account: account, funds: funds, stock: stock)
    }
    private static func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")) }
    private static func build(_ entries: [Entry], lots: Bool, totalCost: Bool, broker: String, account: String, funds: [Fund], stock: (String) -> StockInfo?) throws -> Self {
        let name = broker.trimmingCharacters(in: .whitespacesAndNewlines); let alias = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !alias.isEmpty, alias.count <= 80 else { throw AppDataError("請填券商名稱與帳戶暱稱（各 80 字以內）。") }
        let source = StableID.make("broker-account", name + "\u{0}" + alias).uuidString
        var holdings: [Holding] = []; var seen = Set<String>()
        for entry in entries {
            let code = entry.code
            guard DataChecks.code(code), let qty = entry.quantity, let cost = entry.cost, qty.isFinite, qty > 0, cost.isFinite, cost >= 0 else { throw AppDataError("\(entry.place)有無效代號、數量或成本，整份未匯入。") }
            guard seen.insert(code).inserted else { throw AppDataError("\(code) 有多列，請先將同帳戶同一檔合併為一筆庫存。") }
            if lots && (code.hasSuffix("C") || code.hasSuffix("K")) { throw AppDataError("\(code) 為外幣級別，交易單位可能不是 1,000 股；請將數量改為實際股數再匯入。") }
            let shares = qty * (lots ? 1000 : 1)
            let fund = funds.first { $0.id == code }
            guard let listed = fund?.name ?? stock(code)?.name else { throw AppDataError("\(entry.place) \(code) 不在目前股票或 ETF 名單；請先更新名單，或移除該列。") }
            let holding = Holding(id: StableID.make("broker-position", source + "\u{0}" + code), symbol: code, name: entry.name.isEmpty ? listed : entry.name,
                                  shares: shares, unitCost: totalCost ? cost / shares : cost, broker: name, strategy: fund?.strategy ?? .unclassified, sourceAccount: source)
            try holding.validate(); holdings.append(holding)
        }
        return Self(holdings: holdings, sourceAccount: source, broker: name)
    }
}
extension PortfolioStore {
    func importBroker(_ preview: BrokerPreview, replaceAccount: Bool) throws {
        var next = data
        if replaceAccount { next.holdings.removeAll { $0.sourceAccount == preview.sourceAccount } }
        for holding in preview.holdings {
            if let i = next.holdings.firstIndex(where: { $0.id == holding.id }) { next.holdings[i] = holding } else { next.holdings.append(holding) }
            next.log(.brokerImport, holding)
        }
        try saveRecovery(); try commit(next)
    }
}

/// Reads holdings from the text of a broker's inventory screenshot. The app runs the system's on-device text
/// recognition and passes the lines here, so this part works on plain text and is tested without images.
/// A figure the text does not clearly label stays empty for the user to fill in; nothing is estimated.
enum ScreenshotImport {
    struct Row: Equatable {
        var symbol: String
        var shares: Double? = nil
        var cost: Double? = nil
    }
    /// A row of the editable list the user checks before importing.
    struct Draft: Identifiable, Equatable {
        var id = UUID()
        var symbol = ""
        var shares = ""
        var cost = ""
        init() {}
        init(_ row: Row) { symbol = row.symbol; shares = row.shares.map(Self.plain) ?? ""; cost = row.cost.map(Self.plain) ?? "" }
        private static func plain(_ value: Double) -> String { value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value) }
    }
    private enum Field { case shares, lots, cost }
    /// Titles of a share count; a count in 張 (1,000 shares) is converted.
    static let shareLabels: Set<String> = ["股數", "庫存股數", "現股庫存", "持有股數", "現股股數", "集保股數", "集保庫存"]
    static let lotLabels: Set<String> = ["張數", "庫存張數", "持有張數", "現股張數"]
    /// Titles of the total amount paid; a per-share average such as 成本均價 is not used.
    static let costLabels: Set<String> = ["付出成本", "持有成本", "總成本", "投資成本", "成本總額"]

    /// Groups recognised text boxes (Vision's normalised boxes, origin at the bottom left) into lines, top to bottom.
    static func lines(from boxes: [(text: String, box: CGRect)]) -> [String] {
        var rows: [(middle: CGFloat, height: CGFloat, items: [(x: CGFloat, text: String)])] = []
        for item in boxes.sorted(by: { $0.box.midY > $1.box.midY }) where !item.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if let i = rows.firstIndex(where: { abs($0.middle - item.box.midY) < min($0.height, item.box.height) / 2 }) {
                rows[i].items.append((x: item.box.minX, text: item.text))
            } else {
                rows.append((middle: item.box.midY, height: item.box.height, items: [(x: item.box.minX, text: item.text)]))
            }
        }
        return rows.map { row in row.items.sorted { $0.x < $1.x }.map { $0.text }.joined(separator: " ") }
    }

    /// Holdings in the order they appear. Only codes in the stock or ETF lists (`isKnown`) start a holding; a share
    /// count or total cost is taken when its title is beside it (付出成本 580,365) or above it in a row of titles.
    static func parse(_ lines: [String], isKnown: (String) -> Bool) -> [Row] {
        var rows: [Row] = []
        var current: Int?
        var header: [Field?]?
        var headerFresh = false
        for line in lines {
            let words = tokens(line)
            guard !words.isEmpty else { continue }
            // Totals belong to no single holding.
            if words.contains(where: { $0.contains("合計") || $0.contains("總計") || $0.contains("小計") }) { current = nil; headerFresh = false; continue }
            let codes = words.map { $0.uppercased() }
            let codeIndex = codes.indices.first { DataChecks.code(codes[$0]) && isKnown(codes[$0]) }
            if let i = codeIndex {
                if current.map({ rows[$0].symbol }) != codes[i] { rows.append(Row(symbol: codes[i])); current = rows.count - 1 }
            } else if unlisted(words) {
                current = nil
            }
            let fields = words.map(field)
            if fields.contains(where: { $0 != nil }) {
                var paired = false
                for j in words.indices.dropLast() {
                    if let kind = fields[j], let value = amount(words[j + 1]) { paired = true; fill(&rows, current, kind, value) }
                }
                // Titles with no value beside them head the values on the lines below.
                if !paired && codeIndex == nil { header = fields; headerFresh = true } else { headerFresh = false }
                continue
            }
            // Under a row of titles: the line right below it, or a table row with its own code. Values line up
            // from the right, since a name may take two words; a line shorter than the titles is left alone.
            if let header, headerFresh || codeIndex != nil, words.count >= header.count {
                let offset = words.count - header.count
                for (k, kind) in header.enumerated() {
                    if let kind, k + offset != codeIndex, let value = amount(words[k + offset]) { fill(&rows, current, kind, value) }
                }
            }
            headerFresh = false
        }
        return rows
    }

    /// Several screenshots of one list overlap: a holding seen again with no conflicting figure is completed, not
    /// repeated. Differing figures stay as separate rows for the user to resolve.
    static func merge(_ pages: [[Row]]) -> [Row] {
        var result: [Row] = []
        for row in pages.joined() {
            if let i = result.firstIndex(where: { $0.symbol == row.symbol && agrees($0.shares, row.shares) && agrees($0.cost, row.cost) }) {
                result[i].shares = result[i].shares ?? row.shares
                result[i].cost = result[i].cost ?? row.cost
            } else {
                result.append(row)
            }
        }
        return result
    }
    private static func agrees(_ a: Double?, _ b: Double?) -> Bool { a == nil || b == nil || a == b }

    private static let rewrites: [(String, String)] = [
        (#"[(（]([0-9]{4,6}[A-Z]?)[)）]"#, " $1 "),                                    // 台積電(2330)
        (#"\s+(?=[(（])"#, ""),                                                         // 付出成本 (元)
        (#"(?<![0-9,.])([0-9]{4,6}[A-Z]?)(?=\p{Han})(?![股張])(?!元(?!大))"#, "$1 "),   // 2330台積電, 0050元大台灣50
        (#"(?<=\p{Han})(?=[0-9]{4,6}[A-Z]?(?![0-9,.]))"#, " "),                         // 台積電2330
        ("(" + shareLabels.union(lotLabels).union(costLabels).sorted { $0.count > $1.count }.joined(separator: "|") + #")((?:[(（][^)）]*[)）])?)(?=[0-9])"#, "$1$2 ")  // 股數1,000
    ]
    /// The words of a line, with full-width digits and punctuation made plain and codes split from names.
    private static func tokens(_ line: String) -> [String] {
        var scalars = String.UnicodeScalarView()
        for scalar in line.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19: scalars.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            case 0xFF08: scalars.append("(")
            case 0xFF09: scalars.append(")")
            case 0xFF0C: scalars.append(",")
            case 0xFF0E: scalars.append(".")
            case 0x3A, 0xFF1A, 0x3000: scalars.append(" ")
            default: scalars.append(scalar)
            }
        }
        var text = String(scalars)
        for (pattern, template) in rewrites { text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression) }
        return text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
    /// What a title labels; a unit in brackets such as (張) is read too.
    private static func field(_ word: String) -> Field? {
        var title = word, inLots = false
        if let unit = title.range(of: #"[(（][^)）]*[)）]$"#, options: .regularExpression) { inLots = title[unit].contains("張"); title.removeSubrange(unit) }
        if costLabels.contains(title) { return .cost }
        if lotLabels.contains(title) { return .lots }
        if shareLabels.contains(title) { return inLots ? .lots : .shares }
        return nil
    }
    /// A plain amount such as 1,000 or 580,365; signed figures and percentages are gains, not holdings.
    private static func amount(_ word: String) -> (number: Double, lots: Bool)? {
        var text = word, lots = false
        if text.hasSuffix("張") { lots = true; text.removeLast() } else if text.hasSuffix("股") || text.hasSuffix("元") { text.removeLast() }
        guard text.range(of: #"^([0-9]{1,3}(,[0-9]{3})+|[0-9]+)(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let number = Double(text.replacingOccurrences(of: ",", with: "")), number.isFinite else { return nil }
        return (number, lots)
    }
    /// A code missing from the lists beside a company name: a holding the app cannot import, so the figures
    /// after it must not go to the holding before it.
    private static func unlisted(_ words: [String]) -> Bool {
        words.indices.prefix(2).contains { i in
            DataChecks.code(words[i].uppercased()) && [i - 1, i + 1].contains { j in
                words.indices.contains(j) && field(words[j]) == nil && words[j].unicodeScalars.filter { $0.properties.isIdeographic }.count >= 2
            }
        }
    }
    private static func fill(_ rows: inout [Row], _ index: Int?, _ kind: Field, _ value: (number: Double, lots: Bool)) {
        guard let index else { return }
        if kind == .cost {
            if rows[index].cost == nil { rows[index].cost = value.number }
        } else {
            let shares = value.number * (kind == .lots || value.lots ? 1000 : 1)
            if rows[index].shares == nil, shares > 0, shares == shares.rounded() { rows[index].shares = shares }
        }
    }
}
