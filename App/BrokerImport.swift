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
            guard let quantity = shareCount(draft.shares) else { throw AppDataError("\(place) \(code) 還沒有股數，請對照截圖填入。") }
            guard let cost = number(draft.cost) else { throw AppDataError("\(place) \(code) 還沒有總成本，請對照截圖填入。") }
            entries.append(Entry(place: place, code: code, name: "", quantity: quantity, cost: cost))
        }
        return try build(entries, lots: false, totalCost: true, broker: broker, account: account, funds: funds, stock: stock)
    }
    private static func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")) }
    /// A share count written 1,000, 1,000股 or 2張 (1 張 = 1,000 股).
    private static func shareCount(_ text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lots = value.hasSuffix("張")
        if lots || value.hasSuffix("股") { value.removeLast() }
        return number(value).map { lots ? $0 * 1000 : $0 }
    }
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
/// A holding is found by a listed code, else by a listed name. A figure the text does not clearly label stays
/// empty, and a name that fits no single code leaves the code for the user to choose; nothing is estimated.
enum ScreenshotImport {
    struct Row: Equatable {
        var symbol: String
        var shares: Double? = nil
        var cost: Double? = nil
        /// The name the screenshot showed when it did not settle on one code; `choices` are the codes it may be.
        var name: String? = nil
        var choices: [String] = []
        /// Figures that differed between screenshots of the same holding.
        var note: String? = nil
    }
    /// A row of the editable list the user checks before importing.
    struct Draft: Identifiable, Equatable {
        var id = UUID()
        var symbol = ""
        var shares = ""
        var cost = ""
        var seen = ""
        var choices: [String] = []
        var note: String?
        init() {}
        init(_ row: Row) {
            symbol = row.symbol; shares = row.shares.map(Self.plain) ?? ""; cost = row.cost.map(Self.plain) ?? ""
            seen = row.name ?? ""; choices = row.choices; note = row.note
        }
        private static func plain(_ value: Double) -> String { value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value) }
    }
    /// The stock and ETF lists by code and by name.
    struct Listing {
        private(set) var codes: Set<String> = []
        private var byName: [String: [String]] = [:]
        private var names: [(key: [Character], code: String)] = []
        init(_ entries: [(code: String, name: String)]) {
            for entry in entries where DataChecks.code(entry.code) && !codes.contains(entry.code) {
                codes.insert(entry.code)
                let key = Self.key(entry.name)
                guard !key.isEmpty else { continue }
                byName[key, default: []].append(entry.code); names.append((key: Array(key), code: entry.code))
            }
        }
        func knows(_ code: String) -> Bool { codes.contains(code) }
        /// Codes whose name is exactly this, ignoring spaces, full-width letters and 臺／台.
        func exact(_ name: String) -> [String] { byName[Self.key(name)] ?? [] }
        /// Codes whose name is one misread character away, or begins with this cut-off name: choices, never a match.
        func near(_ name: String) -> [String] {
            var key = Array(Self.key(name))
            while let last = key.last, last == "…" || last == "." { key.removeLast() }
            guard key.count >= 3 else { return [] }
            return Array(names.filter { $0.key.starts(with: key) || ($0.key.count >= 3 && Self.oneEdit(key, $0.key)) }.map { $0.code }.prefix(8))
        }
        static func key(_ text: String) -> String {
            var scalars = String.UnicodeScalarView()
            for scalar in text.unicodeScalars where !scalar.properties.isWhitespace {
                switch scalar.value {
                case 0xFF01...0xFF5E: scalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
                case 0x81FA: scalars.append("台")
                default: scalars.append(scalar)
                }
            }
            return String(scalars).uppercased()
        }
        /// One character replaced, added or left out.
        private static func oneEdit(_ a: [Character], _ b: [Character]) -> Bool {
            if a.count == b.count { return zip(a, b).filter { $0 != $1 }.count == 1 }
            guard abs(a.count - b.count) == 1 else { return false }
            let short = a.count < b.count ? a : b, long = a.count < b.count ? b : a
            var i = 0, j = 0, skipped = false
            while i < short.count && j < long.count {
                if short[i] == long[j] { i += 1; j += 1 } else if skipped { return false } else { skipped = true; j += 1 }
            }
            return true
        }
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

    /// Holdings in the order they appear. A listed code or name starts a holding; a share count or total cost is
    /// taken when its title is beside it (付出成本 580,365) or above it in a row of titles.
    static func parse(_ lines: [String], in listing: Listing) -> [Row] {
        var rows: [Row] = []
        var current: Int?
        var header: [Field?]?
        var headerFresh = false
        for line in lines {
            let words = tokens(line)
            guard !words.isEmpty else { continue }
            // Totals belong to no single holding.
            if words.contains(where: { $0.contains("合計") || $0.contains("總計") || $0.contains("小計") }) { current = nil; headerFresh = false; continue }
            let found = holding(in: words, listing)
            if let found {
                let row = Row(symbol: found.code ?? "", name: found.code == nil ? found.name : nil, choices: found.choices)
                if current.map({ rows[$0].symbol != row.symbol || rows[$0].name != row.name }) ?? true { rows.append(row); current = rows.count - 1 }
            } else if unlisted(words) {
                current = nil
            }
            let fields = words.map(field)
            if fields.contains(where: { $0 != nil }) {
                var paired = false
                for j in words.indices.dropLast() {
                    if let kind = fields[j], let value = amount(words[j + 1]) { paired = true; if let current { fill(&rows[current], kind, value) } }
                }
                // Titles with no value beside them head the values on the lines below.
                if !paired && found == nil { header = fields; headerFresh = true } else { headerFresh = false }
                continue
            }
            // Under a row of titles: the line right below it, or a table row of its own. Values line up from the
            // right, since a name may take two words; a line shorter than the titles is left alone.
            if let header, words.count >= header.count, found != nil || headerFresh || leadingName(words) != nil {
                let offset = words.count - header.count
                var figures = Row(symbol: "")
                for (k, kind) in header.enumerated() {
                    if let kind, !(found?.words.contains(k + offset) ?? false), let value = amount(words[k + offset]) { fill(&figures, kind, value) }
                }
                if found == nil && !headerFresh {
                    // A table row whose name fits nothing in the lists: its figures are kept, the code left to the user.
                    guard figures.shares != nil, let name = leadingName(words) else { headerFresh = false; continue }
                    rows.append(Row(symbol: "", name: name)); current = rows.count - 1
                }
                if let current {
                    if rows[current].shares == nil { rows[current].shares = figures.shares }
                    if rows[current].cost == nil { rows[current].cost = figures.cost }
                }
            }
            headerFresh = false
        }
        return rows
    }

    /// One row per holding across all screenshots (a long list is captured in several overlapping ones). A figure
    /// read differently in different places is left empty, with the readings in a note for the user to check.
    static func merge(_ pages: [[Row]]) -> [Row] {
        var result: [Row] = [], shares: [[Double]] = [], costs: [[Double]] = []
        for row in pages.joined() {
            let i: Int
            if let found = result.firstIndex(where: { $0.symbol.isEmpty ? row.symbol.isEmpty && $0.name == row.name : $0.symbol == row.symbol }) {
                i = found
            } else {
                result.append(Row(symbol: row.symbol, name: row.name, choices: row.choices)); shares.append([]); costs.append([]); i = result.count - 1
            }
            if let value = row.shares, !shares[i].contains(value) { shares[i].append(value) }
            if let value = row.cost, !costs[i].contains(value) { costs[i].append(value) }
        }
        for i in result.indices {
            result[i].shares = shares[i].count == 1 ? shares[i][0] : nil
            result[i].cost = costs[i].count == 1 ? costs[i][0] : nil
            var differing: [String] = []
            if shares[i].count > 1 { differing.append("股數 " + shares[i].map(grouped).joined(separator: "／")) }
            if costs[i].count > 1 { differing.append("總成本 " + costs[i].map(grouped).joined(separator: "／")) }
            if !differing.isEmpty { result[i].note = "截圖之間數字不一致（" + differing.joined(separator: "；") + "），請對照確認後填入。" }
        }
        return result
    }

    /// The holding a line names: a listed code, else a listed name of up to three words (the longest first), else
    /// names one misread character away, offered as choices.
    private struct Found { var words: Range<Int>; var code: String?; var name: String; var choices: [String] }
    private static func holding(in words: [String], _ listing: Listing) -> Found? {
        let upper = words.map { $0.uppercased() }
        if let i = upper.indices.first(where: { DataChecks.code(upper[$0]) && listing.knows(upper[$0]) }) { return Found(words: i..<i + 1, code: upper[i], name: "", choices: []) }
        let parts = words.map(namePart)
        for i in words.indices {
            for count in stride(from: min(3, words.count - i), through: 1, by: -1) {
                let piece = parts[i..<i + count]
                guard !piece.contains(where: { $0 == nil }) else { continue }
                let name = piece.compactMap { $0 }.joined()
                let codes = listing.exact(name)
                if codes.count == 1 { return Found(words: i..<i + count, code: codes[0], name: name, choices: []) }
                if codes.count > 1 { return Found(words: i..<i + count, code: nil, name: name, choices: codes) }
            }
        }
        for i in words.indices {
            guard let word = parts[i], ideographs(word) >= 2 else { continue }
            let near = listing.near(word)
            if !near.isEmpty { return Found(words: i..<i + 1, code: nil, name: word, choices: near) }
        }
        return nil
    }
    /// A word that may be part of a name: not a title, amount, code, signed figure or percentage. A trailing
    /// note in brackets, as in 台積電(現股), is dropped.
    private static func namePart(_ word: String) -> String? {
        guard field(word) == nil, amount(word) == nil, !DataChecks.code(word.uppercased()),
              !word.contains(","), !word.contains("%"), !word.hasPrefix("+"), !word.hasPrefix("-") else { return nil }
        return word.replacingOccurrences(of: #"[(（][^)）]*[)）]$"#, with: "", options: .regularExpression)
    }
    /// The words before a line's figures, when they read as a name (two or more Chinese characters).
    private static func leadingName(_ words: [String]) -> String? {
        let name = words.prefix(while: { namePart($0) != nil }).compactMap(namePart).joined()
        return ideographs(name) >= 2 ? name : nil
    }
    private static func ideographs(_ text: String) -> Int { text.unicodeScalars.filter { $0.properties.isIdeographic }.count }

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
                words.indices.contains(j) && field(words[j]) == nil && ideographs(words[j]) >= 2
            }
        }
    }
    private static func fill(_ row: inout Row, _ kind: Field, _ value: (number: Double, lots: Bool)) {
        if kind == .cost {
            if row.cost == nil { row.cost = value.number }
        } else {
            let shares = value.number * (kind == .lots || value.lots ? 1000 : 1)
            if row.shares == nil, shares > 0, shares == shares.rounded() { row.shares = shares }
        }
    }
    private static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US"); formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
