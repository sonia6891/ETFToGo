import XCTest
@testable import ETFCore

final class CoreTests: XCTestCase {
    func etf(_ name: String, code: String = "0050", index: String = "") -> ETF {
        ETF(code: code, name: name, fullName: name, fundType: "指數股票型基金", indexName: index, market: "TWSE", sourceDate: "2026-10-14", sourceURL: CatalogParser.twseURL)
    }
    func fixture(_ name: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures").appendingPathComponent(name + ".json")) }
    func testLegacyV150MigrationRetainsMoneyAndFavorites() throws {
        let d = try Backup.decode(fixture("legacy-v150"))
        XCTAssertEqual(d.planning.holdings.count, 1); XCTAssertEqual(d.planning.holdings[0].shares, 1000)
        XCTAssertEqual(d.planning.holdings[0].cost, 50000); XCTAssertEqual(d.planning.plan.monthly, 7000)
        XCTAssertEqual(d.favorites, ["00991A"]); XCTAssertEqual(d.comparison, ["00991A"])
        XCTAssertEqual(try Backup.decode(Backup.encode(d)), d)
    }
    func testPlainPlanningBackupMigration() throws {
        let source = try Backup.decode(fixture("legacy-v150"))
        let imported = try Backup.decode(JSONEncoder().encode(source.planning))
        XCTAssertEqual(imported.planning, source.planning)
    }
    func testLegacyPlanningWithoutOptionalPlanUsesDefaults() throws {
        let data = try Backup.decode(Data("{\"version\":2,\"holdings\":[],\"dividends\":[]}".utf8))
        XCTAssertEqual(data.planning.plan, Plan())
    }
    func testInvalidDates() {
        XCTAssertFalse(Validation.isDate("2026-02-29")); XCTAssertTrue(Validation.isDate("2024-02-29"))
        XCTAssertFalse(Validation.isDate("2026-04-31")); XCTAssertFalse(Validation.isDate("2026-1-01"))
        XCTAssertEqual(CatalogParser.rocDate("1151014"), "2026-10-14")
        XCTAssertNil(CatalogParser.rocDate("1150230"))
    }
    func testAllListedCoverageIncludesNonDomesticAndLeveraged() throws {
        let records = try CatalogParser.twse(fixture("twse-20261014"), today: "2026-10-15")
        XCTAssertEqual(records.count, 272)
        XCTAssertTrue(records.allSatisfy { $0.market == "TWSE" })
        XCTAssertNotNil(records.first { $0.code == "0050" })
        XCTAssertNotNil(records.first { $0.code == "00631L" })
        XCTAssertTrue(records.contains { $0.fundType.contains("國外") })
        XCTAssertEqual(Set(records.map(\.code)).count, records.count)
    }
    func testPiggyBankDoesNotMatchTaiwanAsAI() {
        let e = etf("元大台灣50", index: "FTSE Taiwan 50 Index")
        XCTAssertEqual(RoleClassifier.classify(e).role, .piggyBank)
    }
    func testLeveragedOverridesIncomeName() {
        XCTAssertEqual(RoleClassifier.classify(etf("高息正2", code: "00631L")).role, .slotMachine)
    }
    func testIndustryOverridesDividendName() {
        XCTAssertEqual(RoleClassifier.classify(etf("科技高息" )).role, .slotMachine)
    }
    func testDividendIsOnlyPrinterCandidate() {
        let r = RoleClassifier.classify(etf("元大高股息", code: "0056"))
        XCTAssertEqual(r.role, .printer); XCTAssertFalse(r.historyVerified); XCTAssertTrue(r.status.contains("候選"))
    }
    func testUnknownNotForcedIntoRole() { XCTAssertNil(RoleClassifier.classify(etf("未明策略")).role) }
    func testActiveNotAutomaticallySlotMachine() { XCTAssertNil(RoleClassifier.classify(etf("主動精選" )).role) }
    func testForeignShortTreasuryNotGuaranteedCapital() {
        let r = RoleClassifier.classify(etf("美國政府債券1-3年"))
        XCTAssertEqual(r.role, .piggyBank); XCTAssertTrue(r.risk.contains("匯率"))
    }
    func testLongBondNotAssumedStableIncome() { XCTAssertEqual(RoleClassifier.classify(etf("美國20年期公債" )).role, .slotMachine) }
    func testPartialValuationUsesOnlyPricedCost() {
        let hs = [Holding(code: "0050", name: "A", shares: 10, cost: 100, price: 12, priceDate: "2026-10-14"), Holding(code: "0056", name: "B", shares: 20, cost: 900, price: nil, priceDate: nil)]
        let s = Finance.summary(hs)
        XCTAssertEqual(s.cost, 1000); XCTAssertEqual(s.pricedCost, 100); XCTAssertEqual(s.value, 120); XCTAssertEqual(s.count, 1)
        XCTAssertNil(Finance.summary([]).value)
    }
    func testDividendActualOverridesEstimate() throws {
        let d = Dividend(code: "0050", name: "A", paymentDate: "2026-10-15", exDate: "2026-10-10", eligibleShares: 1000, perShare: 1.2, deductions: 10, status: .received, actualReceived: 1175, sourceUrl: "")
        try d.validate(); XCTAssertEqual(d.amount, 1175)
    }
    func testReceivedNeedsActualAndExDateOrder() {
        var d = Dividend(code: "0050", name: "A", paymentDate: "2026-10-15", exDate: nil, eligibleShares: 1, perShare: 1, deductions: 0, status: .received, actualReceived: nil, sourceUrl: "")
        XCTAssertThrowsError(try d.validate())
        d.actualReceived = 1; d.exDate = "2026-10-16"; XCTAssertThrowsError(try d.validate())
    }
    func testProjectionDoesNotDoubleCountReinvestedDistributions() throws {
        let p = Plan(principal: 1000, monthly: 0, years: 1, totalReturn: 0.1, distributionRate: 0.2, frequency: 4, reinvest: 1, deductionRate: 0)
        XCTAssertEqual(try XCTUnwrap(Finance.project(p).last).total, 1100, accuracy: 0.00001)
    }
    func testZeroReturnCashDistributionConservesTotal() throws {
        let p = Plan(principal: 1000, monthly: 0, years: 1, totalReturn: 0, distributionRate: 0.2, frequency: 1, reinvest: 0, deductionRate: 0)
        let end = try XCTUnwrap(Finance.project(p).last)
        XCTAssertEqual(end.invested, 800, accuracy: 0.00001); XCTAssertEqual(end.cash, 200, accuracy: 0.00001)
        XCTAssertEqual(end.total, 1000, accuracy: 0.00001)
    }
    func testContributionTimingAtZeroReturn() throws {
        let p = Plan(principal: 1000, monthly: 100, years: 1, totalReturn: 0, distributionRate: 0, frequency: 1, reinvest: 1, deductionRate: 0)
        XCTAssertEqual(try XCTUnwrap(Finance.project(p).last).total, 2200, accuracy: 0.00001)
    }
    func testInvalidProjectionRejected() {
        var p = Plan(); p.totalReturn = .nan; XCTAssertThrowsError(try Finance.project(p))
        p = Plan(); p.frequency = 3; XCTAssertThrowsError(try Finance.project(p))
    }
    func testInvalidBackupDoesNotOverwriteFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = DataRepository(url: folder.appendingPathComponent("data.json"))
        let valid = try Backup.decode(fixture("legacy-v150")); try repo.save(valid)
        let before = try Data(contentsOf: repo.url)
        var bad = valid; bad.planning.holdings.append(bad.planning.holdings[0])
        XCTAssertThrowsError(try repo.save(bad)); XCTAssertEqual(try Data(contentsOf: repo.url), before)
        XCTAssertEqual(try repo.load(), valid)
    }
    func testCorruptExistingDataThrowsInsteadOfResetting() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try DataRepository(url: url).load()); XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "broken")
    }
    func testForeignComponentSymbolAndPartialExposure() throws {
        let a = ComponentSnapshot(symbol: "0050", date: "2026-10-14", components: [FundComponent(symbol: "AAPL UQ", name: "Apple", weight: 30)], source: "test")
        try a.validate()
        let h = Holding(code: "0050", name: "A", shares: 100, cost: 1000, price: 20, priceDate: "2026-10-14")
        let values = ExposureCalculator.calculate(holdings: [h], snapshots: ["0050": a])
        XCTAssertEqual(values.count, 1); XCTAssertEqual(values[0].value, 600)
    }
    func testComponentsRejectWrongCodeAndOversizedWeight() throws {
        let a = ComponentSnapshot(symbol: "0050", date: "2026-10-14", components: [FundComponent(symbol: "2330", name: nil, weight: 120)], source: nil)
        XCTAssertThrowsError(try a.validate())
        XCTAssertThrowsError(try ComponentSnapshot.imported(JSONEncoder().encode(a), code: "0056"))
    }
    func testBackupPreservesComponentsAndNeverHasKeyField() throws {
        var d = UserData(); d.components = ["0050": ComponentSnapshot(symbol: "0050", date: "2026-10-14", components: [FundComponent(symbol: "2330", name: nil, weight: 60)], source: "test")]
        let bytes = try Backup.encode(d); XCTAssertEqual(try Backup.decode(bytes), d)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("apiKey"))
    }
}
