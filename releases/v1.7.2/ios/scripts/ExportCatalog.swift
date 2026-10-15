import Foundation

@main
struct ExportCatalog {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw AppError("Usage: export-catalog input.json output-directory") }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let records = try CatalogParser.twse(Data(contentsOf: input))
        let catalog = Catalog(records: records, fetchedAt: ISO8601DateFormatter().string(from: Date()), coverage: "台灣證交所上市 ETF，包含海外投資標的及外幣交易級別；不含上櫃。代碼數不等於獨立基金數。", sources: [CatalogParser.twseURL])
        try catalog.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try encoder.encode(catalog).write(to: output.appendingPathComponent("catalog.json"))
        func csv(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = [["代碼", "名稱", "投資角色", "判定狀態", "理由", "風險", "資料日", "來源"].map(csv).joined(separator: ",")]
        var counts: [String: Int] = [:]
        for e in records {
            let c = RoleClassifier.classify(e); counts[c.role?.title ?? "待核驗", default: 0] += 1
            lines.append([e.code, e.name, c.role?.title ?? "待核驗", c.status, c.reason, c.risk, e.sourceDate, e.sourceURL].map(csv).joined(separator: ","))
        }
        try ("\u{FEFF}" + lines.joined(separator: "\r\n")).write(to: output.appendingPathComponent("classification.csv"), atomically: true, encoding: .utf8)
        print("Catalog records: \(records.count); classification: \(counts)")
    }
}
