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
    @MainActor func testMalformedFileIsNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = Data("invalid data".utf8)
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PortfolioStore(url: url)
        XCTAssertThrowsError(try store.save(Portfolio.demo.holdings[0]))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testQuoteValidation() throws {
        let bytes = Data(#"{"symbol":"0050","date":"2026-10-15","closePrice":55.0,"changePercent":0.4}"#.utf8)
        XCTAssertEqual(try Fugle.decode(bytes, expectedSymbol: "0050").price, 55)
        XCTAssertThrowsError(try Fugle.decode(bytes, expectedSymbol: "00878"))
        XCTAssertThrowsError(try Fugle.decode(Data(#"{"symbol":"0050","date":"2026-10-15"}"#.utf8), expectedSymbol: "0050"))
    }
}
