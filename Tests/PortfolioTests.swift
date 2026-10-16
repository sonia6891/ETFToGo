import XCTest
@testable import ETFToGo

final class PortfolioTests: XCTestCase {
    func testNoMarketValueWithoutCompleteQuotes() {
        var data = Portfolio.demo
        XCTAssertEqual(data.marketValue, 348500)
        data.quotes.removeValue(forKey: "0050")
        XCTAssertNil(data.marketValue, "Missing prices must not silently use cost as market value")
    }
    func testProjectionZeroReturnAndMonthlyTiming() {
        XCTAssertEqual(Projection.value(initial: 100000, monthly: 5000, years: 10, annualPercent: 0), 700000, accuracy: 0.01)
        XCTAssertLessThan(Projection.value(initial: 100000, monthly: 0, years: 10, annualPercent: -5), 100000)
    }
    func testBackupRejectsInvalidData() throws {
        var data = Portfolio.demo
        data.holdings[0].shares = -1
        XCTAssertThrowsError(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
        data = .demo; data.schema = 99
        XCTAssertThrowsError(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
        data = .demo; data.holdings.append(data.holdings[0])
        XCTAssertThrowsError(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
    }
    @MainActor func testPersistenceAndImportIdempotence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: url)
        let holding = Portfolio.demo.holdings[0]
        try store.save(holding)
        let reopened = PortfolioStore(url: url)
        XCTAssertEqual(reopened.data.holdings.first?.shares, holding.shares)
        let bytes = try JSONEncoder().encode(Portfolio.demo)
        try reopened.importBackup(bytes)
        let count = reopened.data.holdings.count
        try reopened.importBackup(bytes)
        XCTAssertEqual(reopened.data.holdings.count, count)
        XCTAssertTrue(reopened.data.holdings.contains { $0.id == holding.id })
    }
    @MainActor func testTradeLogRecordsHoldingChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: url)
        var holding = Portfolio.demo.holdings[0]
        try store.save(holding); try store.save(holding)
        holding.shares += 1000; try store.save(holding)
        try store.remove(holding)
        XCTAssertEqual(store.data.trades?.map(\.action), [.buy, .adjust, .remove], "Saving unchanged values adds no entry")
        XCTAssertEqual(store.data.trades?.last?.shares, 3000)
        XCTAssertEqual(PortfolioStore(url: url).data.trades?.count, 3)
    }
    @MainActor func testBuyAndSellAdjustHolding() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("data.json")
        let store = PortfolioStore(url: url, demo: true)
        let before = store.data.holdings.count
        try store.applyTrade(.buy, symbol: "0056", date: Date(), shares: 1000, amount: 30000, broker: "測試")
        XCTAssertEqual(store.data.holdings.count, before + 1)
        try store.applyTrade(.buy, symbol: "0056", date: Date(), shares: 1000, amount: 40000, broker: "測試")
        let holding = try XCTUnwrap(store.data.holdings.first { $0.symbol == "0056" && $0.broker == "測試" })
        XCTAssertEqual(holding.shares, 2000); XCTAssertEqual(holding.unitCost, 35, accuracy: 0.0001)
        XCTAssertThrowsError(try store.applyTrade(.sell, symbol: "0056", date: Date(), shares: 5000, amount: 1, broker: "測試"), "Selling more than held is refused")
        try store.applyTrade(.sell, symbol: "0056", date: Date(), shares: 500, amount: 20000, broker: "測試")
        XCTAssertEqual(store.data.trades?.last?.realized, 2500)
        try store.applyTrade(.sell, symbol: "0056", date: Date(), shares: 1500, amount: 60000, broker: "測試")
        XCTAssertNil(store.data.holdings.first { $0.symbol == "0056" && $0.broker == "測試" }, "A holding sold down to zero is removed")
        XCTAssertEqual(store.data.trades?.suffix(4).map(\.action), [.buy, .buy, .sell, .sell])
    }
    func testOfficialDistributionHelpers() {
        XCTAssertEqual(OfficialDividends.rocDay("115年10月22日"), "2026-10-22")
        XCTAssertEqual(OfficialDividends.rocDay("1151016"), "2026-10-16")
        XCTAssertNil(OfficialDividends.rocDay("abc"))
        let days = (1...4).map { DataChecks.day(Calendar.current.date(byAdding: .month, value: -3 * $0 + 1, to: Date())!) }
        XCTAssertEqual(OfficialDividends.frequency(of: days.map { OfficialDistribution(ex: $0, pay: "", amount: 1) }), "季配")
        XCTAssertEqual(OfficialDividends.frequency(of: Array(days.prefix(2)).map { OfficialDistribution(ex: $0, pay: "", amount: 1) }), "半年配")
    }
    @MainActor func testMalformedFileIsNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = Data("invalid data".utf8)
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PortfolioStore(url: url)
        XCTAssertThrowsError(try store.save(Portfolio.demo.holdings[0]))
        XCTAssertEqual(try Data(contentsOf: url), original)
        let exported = try store.export()
        defer { try? FileManager.default.removeItem(at: exported) }
        XCTAssertEqual(try Data(contentsOf: exported), original)
    }
    /// Same numbers as the design: 300,000 now (stocks 120,000 / ETFs 180,000), 10,000 a month split 40/60, 5% a year.
    func testComboProjectionMatchesTemplate() {
        var settings = ComboSettings()
        settings.monthly = 10000; settings.stockReturn = 5; settings.etfReturn = 5
        for (years, expected) in [(3, 734180.51), (5, 1061021.85), (10, 2032300.0)] {
            let result = ComboMath.project(stockStart: 120000, etfStart: 180000, settings: settings, stockShare: 0.4, years: years, scenario: .base)
            XCTAssertEqual(result.end, expected, accuracy: 1)
            XCTAssertEqual(result.invested, 10000 * Double(years * 12), accuracy: 0.001)
        }
        XCTAssertEqual(ComboMath.project(stockStart: 120000, etfStart: 180000, settings: settings, stockShare: 0.4, years: 5, scenario: .stress).end, 908735.8, accuracy: 1)
        var flat = settings; flat.stockReturn = 0; flat.etfReturn = 0
        XCTAssertEqual(ComboMath.project(stockStart: 120000, etfStart: 180000, settings: flat, stockShare: 0.4, years: 10, scenario: .base).end, 1500000, accuracy: 0.01)
        var cash = settings; cash.reinvest = false; cash.stockYield = 2; cash.etfYield = 4
        XCTAssertEqual(ComboMath.project(stockStart: 120000, etfStart: 180000, settings: cash, stockShare: 0.4, years: 5, scenario: .base).end, 1050621.51, accuracy: 1)
        XCTAssertEqual(ComboScenario.conservative.rate(5), -2); XCTAssertEqual(ComboScenario.optimistic.rate(5), 8)
    }
    func testBundledStocksAndCloses() throws {
        let snapshot = try XCTUnwrap(StockSnapshot.bundled, "stock-data.json is bundled")
        XCTAssertEqual(snapshot.byID["2330"]?.market, "TWSE")
        XCTAssertEqual(snapshot.byID["6488"]?.market, "TPEx")
        XCTAssertGreaterThan(snapshot.stocks.count, 1500)
        let quote = try XCTUnwrap(snapshot.close("2330"))
        XCTAssertGreaterThan(quote.price, 0); XCTAssertEqual(quote.currency, "TWD"); XCTAssertTrue(quote.isValid)
        XCTAssertNotNil(snapshot.indices["taiex"]?.close)
        XCTAssertNotNil(snapshot.indices["tpex"]?.close)
    }
    @MainActor func testStockHoldingIsValuedAndComboPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: url)
        let holding = Holding(symbol: "2330", name: "台積電", shares: 10, unitCost: 100, broker: "", strategy: .unclassified)
        try store.save(holding)
        XCTAssertTrue(store.isStock("2330")); XCTAssertFalse(store.isStock("0050")); XCTAssertFalse(store.isStock("00878"))
        XCTAssertNotNil(store.marketValue(of: holding), "A stock without a Fugle quote is valued at the bundled close")
        XCTAssertNotNil(store.summary.marketValue)
        var combo = store.combo
        combo.source = 1; combo.simulated = [ComboItem(symbol: "2330", amount: 50000), ComboItem(symbol: "0050", amount: 30000)]; combo.years = 10
        store.saveCombo(combo)
        let reopened = PortfolioStore(url: url)
        XCTAssertEqual(reopened.combo, combo)
        XCTAssertEqual(reopened.comboStarts(reopened.combo).stock, 50000, accuracy: 0.001)
        XCTAssertEqual(reopened.comboStarts(reopened.combo).etf, 30000, accuracy: 0.001)
    }
    func testQuoteValidation() throws {
        let bytes = Data(#"{"symbol":"0050","date":"2026-10-15","closePrice":55.0,"changePercent":0.4}"#.utf8)
        XCTAssertEqual(try Fugle.decode(bytes, expectedSymbol: "0050").price, 55)
        XCTAssertThrowsError(try Fugle.decode(bytes, expectedSymbol: "00878"))
        XCTAssertThrowsError(try Fugle.decode(Data(#"{"symbol":"0050","date":"2026-10-15"}"#.utf8), expectedSymbol: "0050"))
    }
}
