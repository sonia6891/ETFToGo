import XCTest
@testable import ETFToGo

final class RestoredFeaturesTests: XCTestCase {
    let legacy = #"{"app":"ETF_CLASSIFIER","version":3,"planning":{"version":2,"holdings":[{"id":"pwa-001","code":"0050","name":"元大台灣50","shares":2000,"cost":100000,"price":55,"priceDate":"2026-10-01"}],"dividends":[{"id":"pwa-dividend-1","code":"0050","name":"元大台灣50","paymentDate":"2026-10-10","exDate":"2026-10-01","eligibleShares":2000,"perShare":1.2,"deductions":10,"status":"received","actualReceived":2385,"sourceUrl":"https://example.com/dividend"}],"plan":{"principal":100000,"monthly":5000,"years":10,"totalReturn":0.06,"distributionRate":0.04,"frequency":4,"reinvest":1,"deductionRate":0}},"favorites":["0050"],"comparison":["0050","00878"]}"#
    func testRealPWAShapeMigratesCostActualDividendAndMetadata() throws {
        let value = try BackupImport.decode(Data(legacy.utf8))
        XCTAssertEqual(value.holdings[0].unitCost, 50)
        XCTAssertEqual(value.cost, 100000)
        XCTAssertEqual(value.dividends[0].amount, 2385, "Actual receipt must win over shares × dividend minus fees")
        XCTAssertEqual(value.dividends[0].status, .paid)
        XCTAssertEqual(DataChecks.day(value.dividends[0].date), "2026-10-10")
        XCTAssertEqual(value.legacyPrices?["pwa-001"]?.price, 55)
        XCTAssertEqual(value.legacyDividends?["pwa-dividend-1"]?.deductions, 10)
        XCTAssertEqual(value.legacyPlan?.distributionRate, 0.04)
        XCTAssertEqual(value.comparison, ["0050", "00878"])
        XCTAssertTrue(value.quotes.isEmpty, "Manually entered prices must not become verified quotes")
    }
    @MainActor func testPWARepeatedImportKeepsCurrentDataAndStableIDs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PortfolioStore(url: dir.appendingPathComponent("portfolio.json"))
        try store.save(Portfolio.demo.holdings[1])
        try store.importBackup(Data(legacy.utf8)); try store.importBackup(Data(legacy.utf8))
        XCTAssertEqual(store.data.holdings.count, 2); XCTAssertEqual(store.data.dividends.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Recovery").path).count, 2)
        let reopened = PortfolioStore(url: dir.appendingPathComponent("portfolio.json"))
        XCTAssertEqual(reopened.data.legacyDividends?.count, 1)
        XCTAssertEqual(reopened.data.holdings.count, 2)
    }
    func testPlannedDividendAndOlderNativeEnvelope() throws {
        let input = legacy.replacingOccurrences(of: "ETF_CLASSIFIER", with: "ETF_TOGO_NATIVE").replacingOccurrences(of: "\"version\":3", with: "\"version\":1").replacingOccurrences(of: "\"received\"", with: "\"planned\"")
        let value = try BackupImport.decode(Data(input.utf8))
        XCTAssertEqual(value.dividends[0].amount, 2390); XCTAssertEqual(value.dividends[0].status, .estimated)
    }
    func testLegacyRejectsNegativeCostsAndMissingActualPayment() {
        XCTAssertThrowsError(try BackupImport.decode(Data(legacy.replacingOccurrences(of: "\"cost\":100000", with: "\"cost\":-1").utf8)))
        XCTAssertThrowsError(try BackupImport.decode(Data(legacy.replacingOccurrences(of: "\"actualReceived\":2385", with: "\"actualReceived\":null").utf8)))
    }
    func testBundledCatalogCoversBothMarketsAndNoDuplicateCodes() throws {
        let catalog = try XCTUnwrap(CatalogSnapshot.bundled())
        try catalog.validate()
        XCTAssertGreaterThan(catalog.funds.filter { $0.market == "TWSE" }.count, 250)
        XCTAssertGreaterThan(catalog.funds.filter { $0.market == "TPEx" }.count, 100)
        XCTAssertTrue(catalog.funds.contains { $0.id == "00679B" && $0.market == "TPEx" })
        XCTAssertEqual(Set(catalog.funds.map(\.id)).count, catalog.funds.count)
    }
    func testCatalogRejectsMissingMarketAndDuplicates() {
        let row = #"[{"基金代號":"0050","基金簡稱":"元大台灣50","出表日期":"1151014","上市日期":"0920630"}]"#
        XCTAssertThrowsError(try CatalogAPI.decode(listed: Data(row.utf8), otc: Data(#"{"suggestions":[]}"#.utf8)))
        XCTAssertThrowsError(try CatalogAPI.decode(listed: Data(row.utf8), otc: Data(#"{"suggestions":["0050 重複代碼"]}"#.utf8)))
    }
    func snapshot(_ symbol: String, _ values: [(String, Double)]) -> ComponentSnapshot {
        ComponentSnapshot(symbol: symbol, date: "2026-10-01", components: values.map { FundComponent(symbol: $0.0, name: $0.0, weight: $0.1) }, source: "test")
    }
    func testOverlapAndExposureUseWeightsAndExcludeMissingQuotes() throws {
        let a = snapshot("0050", [("2330",60),("2454",10)])
        let b = snapshot("00878", [("2330",20),("2317",5)])
        let rows = ResearchMath.overlap(a,b)
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.reduce(0) { $0 + min($1.left,$1.right) }, 20)
        var data = Portfolio.demo; data.components = ["0050":a,"00878":b]
        let exposure = ResearchMath.exposures(data)
        XCTAssertEqual(exposure.first?.value, 91200)
        data.quotes.removeValue(forKey: "00878")
        XCTAssertEqual(ResearchMath.exposures(data).first?.value, 66000)
        data.quotes["0050"]?.currency = "USD"
        XCTAssertTrue(ResearchMath.exposures(data).isEmpty); XCTAssertNil(data.marketValue)
    }
    func testComponentsRejectFutureDatesInvalidWeightsAndUnknownSymbol() {
        var value = snapshot("0050", [("2330",110)])
        XCTAssertThrowsError(try value.validate())
        value = snapshot("0050", [("2330",60)]); value.date = "2099-01-01"
        XCTAssertThrowsError(try value.validate())
        XCTAssertThrowsError(try Fugle.decodeComponents(Data(#"{"symbol":"0050","data":[]}"#.utf8), symbol:"0050"))
    }
    func testPricePerformanceUsesDrawdownsAndRealTimeInterval() throws {
        let h = PriceHistory(symbol:"0050",adjusted:true,points:[PricePoint(date:"2024-01-01",close:100),PricePoint(date:"2024-06-01",close:120),PricePoint(date:"2024-08-01",close:90),PricePoint(date:"2025-01-01",close:110)],fetchedDay:"2025-01-02",source:"test")
        let stats = try PerformanceStats(h)
        XCTAssertEqual(stats.change,0.1,accuracy:0.000001); XCTAssertEqual(stats.drawdown,0.25,accuracy:0.000001)
        XCTAssertEqual(stats.annualized!,pow(1.1,365.25/366)-1,accuracy:0.000001)
        XCTAssertNil(stats.volatility)
    }
    func testHistoryRejectsUnadjustedDataAndDuplicateDates() {
        XCTAssertThrowsError(try Fugle.decodeHistory(Data(#"{"symbol":"0050","timeframe":"D","data":[]}"#.utf8),symbol:"0050"))
        let h = PriceHistory(symbol:"0050",adjusted:true,points:[PricePoint(date:"2025-01-01",close:100),PricePoint(date:"2025-01-01",close:101)],fetchedDay:"2025-01-02",source:"test")
        XCTAssertThrowsError(try h.validate())
    }
    func testCSVQuotedCommasNewlinesAndTrailingLine() throws {
        let table = try CSVTable.parse(Data("代碼,名稱,股數,總成本\r\n0050,\"台灣,50\",1000,\"50,000\"\r\n".utf8))
        XCTAssertEqual(table.rows.count,1); XCTAssertEqual(table.rows[0][1],"台灣,50")
        let p = try BrokerPreview.make(table:table,mapping:BrokerMapping(symbol:0,name:1,shares:2,cost:3),broker:"測試券商",account:"主要",funds:Fund.starters)
        XCTAssertEqual(p.holdings[0].unitCost,50); XCTAssertEqual(p.totalCost,50000)
        XCTAssertThrowsError(try CSVTable.parse(Data("a,b\n\"bad,x".utf8)))
    }
    @MainActor func testBrokerReimportReplacesOnlySelectedAccount() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = PortfolioStore(url:dir.appendingPathComponent("p.json")); try store.save(Portfolio.demo.holdings[2])
        let table = try CSVTable.parse(Data("code,shares,cost\n0050,2,100000\n00878,1,20000".utf8))
        let mapping = BrokerMapping(symbol:0,name:-1,shares:1,cost:2,lots:true)
        let a = try BrokerPreview.make(table:table,mapping:mapping,broker:"A",account:"主",funds:Fund.starters)
        try store.importBroker(a,replaceAccount:false); try store.importBroker(a,replaceAccount:false)
        XCTAssertEqual(store.data.holdings.count,3); XCTAssertEqual(a.holdings[0].shares,2000)
        let b = try BrokerPreview.make(table:CSVTable.parse(Data("code,shares,cost\n0050,1,50000".utf8)),mapping:mapping,broker:"A",account:"主",funds:Fund.starters)
        try store.importBroker(b,replaceAccount:true)
        XCTAssertEqual(store.data.holdings.count,2); XCTAssertTrue(store.data.holdings.contains { $0.symbol == "00919" })
    }
    func testFeeRecordRequiresYearAndSource() {
        var fee = FeeRecord(symbol:"0050",effectiveDate:"2026-01-01",management:"級距費率",custody:"級距費率",annualExpensePercent:0.2,expenseYear:nil,sourceURL:"https://example.com",note:"")
        XCTAssertThrowsError(try fee.validate()); fee.expenseYear=2025; XCTAssertNoThrow(try fee.validate())
        fee.sourceURL="javascript:alert(1)"; XCTAssertThrowsError(try fee.validate())
    }
    func testSchemaOneStillDecodesWithoutNewFields() throws {
        let bytes = Data(#"{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}"#.utf8)
        let value=try Portfolio.decodeBackup(bytes); XCTAssertNil(value.components); XCTAssertTrue(value.holdings.isEmpty)
    }
}
