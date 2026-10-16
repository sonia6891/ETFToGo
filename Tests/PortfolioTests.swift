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
    func testExchangeLiveQuotes() throws {
        // Shape of mis.twse.com.tw getStockInfo.jsp on 2026-10-16: an index, a share with a trade in the current
        // tick, one without (last trade under "trade"), one with no trade today, and an unknown code.
        let bytes = Data(#"""
        {"rtcode":"0000","rtmessage":"OK","msgArray":[
         {"c":"t00","ex":"tse","d":"20261016","z":"47268.85","y":"46969.87","o":"46995.03","h":"47520.60","l":"46995.03"},
         {"c":"0050","ex":"tse","d":"20261016","z":"109.3000","y":"108.9000","o":"109.4500","h":"109.7000","l":"108.9000","v":"85139","trade":{"t":"12:04:04","v":13,"z":"109.3000"}},
         {"c":"6488","ex":"otc","d":"20261016","z":"-","y":"923.0000","o":"936.0000","h":"936.0000","l":"890.0000","v":"11007","trade":{"t":"12:03:40","v":2,"z":"905.0000"}},
         {"c":"00679B","ex":"otc","d":"20261016","z":"-","y":"25.5600","o":"-","h":"-","l":"-","v":"0"},
         {"tv":"-","s":"-","c":"","z":"-"}]}
        """#.utf8)
        let quotes = try ExchangeLive.decode(bytes)
        XCTAssertEqual(Set(quotes.keys), ["t00", "0050", "6488"])
        let etf = try XCTUnwrap(quotes["0050"])
        XCTAssertEqual(etf.price, 109.3); XCTAssertEqual(etf.change ?? 0, 0.4, accuracy: 0.0001); XCTAssertEqual(etf.changePercent ?? 0, 0.37, accuracy: 0.001)
        XCTAssertEqual(etf.date, "2026-10-16"); XCTAssertEqual(etf.volume, 85139); XCTAssertTrue(etf.isTWD); XCTAssertTrue(etf.isExchangeLive)
        XCTAssertEqual(quotes["6488"]?.price, 905, "Without a trade in the current tick, the last trade is used")
        XCTAssertEqual(quotes["t00"]?.change ?? 0, 298.98, accuracy: 0.001)
        XCTAssertThrowsError(try ExchangeLive.decode(Data(#"{"rtcode":"5001","msgArray":[]}"#.utf8)))
    }
    func testLiveProtocolMessages() throws {
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"authenticated","data":{"message":"Authenticated successfully"}}"#), .authenticated)
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"subscribed","data":{"id":"abc","channel":"aggregates","symbol":"2330"}}"#), .subscribed(["2330": "abc"]))
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"subscribed","data":[{"id":"a","channel":"aggregates","symbol":"2330"},{"id":"b","channel":"aggregates","symbol":"0050"}]}"#), .subscribed(["2330": "a", "0050": "b"]))
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"error","data":{"code":1001,"message":"Subscription limit exceeded"}}"#), .error(code: 1001, message: "Subscription limit exceeded"))
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"heartbeat","data":{"time":1}}"#), .heartbeat)
        XCTAssertEqual(LiveProtocol.parse("not json"), .other)
        let push = #"{"event":"data","channel":"aggregates","data":{"date":"2026-10-16","symbol":"2330","openPrice":1450,"highPrice":1465,"lowPrice":1445,"closePrice":1460,"lastPrice":1460,"change":15,"changePercent":1.04,"total":{"tradeVolume":21034},"isTrial":false}}"#
        guard case .tick(let tick) = LiveProtocol.parse(push) else { return XCTFail("aggregates push") }
        XCTAssertEqual(tick.price, 1460); XCTAssertEqual(tick.volume, 21034); XCTAssertEqual(tick.date, "2026-10-16"); XCTAssertFalse(tick.trial)
        let trial = #"{"event":"data","channel":"aggregates","data":{"symbol":"2330","lastPrice":1455,"closePrice":1440,"isTrial":true}}"#
        guard case .tick(let early) = LiveProtocol.parse(trial) else { return XCTFail("trial push") }
        XCTAssertEqual(early.price, 1455, "During the trial match the matched price is shown"); XCTAssertTrue(early.trial)
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"data","channel":"aggregates","data":{"symbol":"../x","closePrice":1}}"#), .other)
        // The key only ever travels in the auth message, never in the address.
        let auth = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LiveProtocol.auth(key: "k-123").utf8)) as? [String: Any])
        XCTAssertEqual((auth["data"] as? [String: String])?["apikey"], "k-123")
        XCTAssertFalse(LiveProtocol.endpoint.absoluteString.contains("k-123"))
        XCTAssertEqual(LiveProtocol.backoff(attempt: 1, random: 0), 0.5)
        XCTAssertEqual(LiveProtocol.backoff(attempt: 20, random: 1), 60)
        // JSONSerialization's 0 and 1 bridge to Bool; they are still numbers.
        let flat = #"{"event":"data","channel":"aggregates","data":{"date":"2026-10-16","symbol":"0050","closePrice":109,"change":0,"changePercent":0,"total":{"tradeVolume":1},"isTrial":false}}"#
        guard case .tick(let even) = LiveProtocol.parse(flat) else { return XCTFail("flat push") }
        XCTAssertEqual(even.change, 0); XCTAssertEqual(even.changePercent, 0); XCTAssertEqual(even.volume, 1)
        guard case .tick(let up) = LiveProtocol.parse(#"{"event":"data","channel":"aggregates","data":{"symbol":"0050","closePrice":110,"change":1}}"#) else { return XCTFail("up push") }
        XCTAssertEqual(up.change, 1)
        let saved = Quote(symbol: "0050", price: 108, changePercent: 1.2, date: "2026-10-16", fetchedAt: .distantPast, currency: "TWD", change: 1.3)
        XCTAssertEqual(LiveProtocol.merge(saved, even).change, 0, "A flat stock shows no change, not the previous one")
        XCTAssertEqual(LiveProtocol.parse(#"{"event":"subscribed","data":{"id":1,"channel":"aggregates","symbol":"0050"}}"#), .subscribed(["0050": "1"]))
    }
    func testFugleTrialMatchQuote() throws {
        let bytes = Data(#"{"date":"2026-10-16","symbol":"2330","lastPrice":1455,"changePercent":0.69,"isTrial":true}"#.utf8)
        let quote = try Fugle.decode(bytes, expectedSymbol: "2330")
        XCTAssertEqual(quote.price, 1455); XCTAssertEqual(quote.trial, true)
        let trade = try Fugle.decode(Data(#"{"date":"2026-10-16","symbol":"2330","closePrice":1460,"lastPrice":1460,"isTrial":false}"#.utf8), expectedSymbol: "2330")
        XCTAssertEqual(trade.price, 1460); XCTAssertNil(trade.trial)
    }
    func testRequestPaceKeepsWithinLimit() async {
        let start = ContinuousClock.now
        func at(_ seconds: Int) -> ContinuousClock.Instant { start + .seconds(seconds) }
        let exchange = RequestPace(limit: 1, window: 5)
        let first = await exchange.take(now: at(0))
        let second = await exchange.take(now: at(0))
        let third = await exchange.take(now: at(1))
        let fourth = await exchange.take(now: at(5))
        XCTAssertEqual(first, 0); XCTAssertEqual(second, 5, accuracy: 0.001)
        XCTAssertEqual(third, 4, accuracy: 0.001, "A caller that waited and gave up took no turn")
        XCTAssertEqual(fourth, 0)
        let fugle = RequestPace(limit: 3, window: 60)
        var waits: [TimeInterval] = []
        for _ in 0..<4 { waits.append(await fugle.take(now: at(0))) }
        XCTAssertEqual(Array(waits.prefix(3)), [0, 0, 0]); XCTAssertEqual(waits[3], 60, accuracy: 0.001)
        let later = await fugle.take(now: at(60))
        XCTAssertEqual(later, 0, "Old requests leave the window")
    }
    func testRealTradeBehindTrialMatch() throws {
        let tick = LiveTick(symbol: "2330", price: 1455, change: 15, changePercent: 1.04, open: nil, high: nil, low: nil, volume: nil, date: "2026-10-16", trial: true, lastTrade: 1460)
        let shown = LiveProtocol.merge(nil, tick)
        XCTAssertEqual(shown.price, 1455); XCTAssertEqual(shown.trial, true)
        let rebuilt = try XCTUnwrap(LiveProtocol.realTrade(shown, tick, known: nil))
        XCTAssertEqual(rebuilt.price, 1460); XCTAssertNil(rebuilt.trial)
        XCTAssertEqual(rebuilt.change ?? 0, 20, accuracy: 0.0001); XCTAssertEqual(rebuilt.changePercent ?? 0, 1.39, accuracy: 0.001)
        let earlier = Quote(symbol: "2330", price: 1458, changePercent: 1.25, date: "2026-10-16", fetchedAt: Date(), currency: "TWD", change: 18)
        XCTAssertEqual(LiveProtocol.realTrade(shown, tick, known: earlier)?.price, 1458, "The day's earlier real trade is kept")
        var trade = tick; trade.trial = false; trade.lastTrade = nil
        XCTAssertEqual(LiveProtocol.realTrade(LiveProtocol.merge(nil, trade), trade, known: earlier)?.price, 1455)
        guard case .tick(let parsed) = LiveProtocol.parse(#"{"event":"data","channel":"aggregates","data":{"symbol":"2330","lastPrice":1455,"closePrice":1460,"isTrial":true}}"#) else { return XCTFail("trial push") }
        XCTAssertEqual(parsed.lastTrade, 1460)
    }
    func testLiveMergeKeepsMissingFields() {
        let saved = Quote(symbol: "0050", price: 100, changePercent: 1, date: "2026-10-16", fetchedAt: Date(timeIntervalSince1970: 0), currency: "TWD", change: 1, open: 99, high: 101, low: 98, volume: 5000, source: ExchangeLive.source)
        let now = Date()
        let tick = LiveTick(symbol: "0050", price: 102, change: 2, changePercent: 2, open: nil, high: 102, low: nil, volume: nil, date: "2026-10-16", trial: false)
        let merged = LiveProtocol.merge(saved, tick, now: now)
        XCTAssertEqual(merged.price, 102); XCTAssertEqual(merged.open, 99); XCTAssertEqual(merged.high, 102); XCTAssertEqual(merged.volume, 5000)
        XCTAssertEqual(merged.date, "2026-10-16"); XCTAssertEqual(merged.fetchedAt, now); XCTAssertNil(merged.trial); XCTAssertFalse(merged.isExchangeLive); XCTAssertEqual(merged.currency, "TWD")
        var yesterday = saved; yesterday.date = "2026-10-15"
        let fresh = LiveProtocol.merge(yesterday, tick, now: now)
        XCTAssertNil(fresh.open, "Yesterday's open, low and volume do not carry into today"); XCTAssertNil(fresh.low); XCTAssertNil(fresh.volume)
        XCTAssertEqual(fresh.high, 102); XCTAssertEqual(fresh.currency, "TWD"); XCTAssertEqual(fresh.date, "2026-10-16")
        let foreign = LiveProtocol.merge(nil, LiveTick(symbol: "00953K", price: 10, change: nil, changePercent: nil, open: nil, high: nil, low: nil, volume: nil, date: nil, trial: true))
        XCTAssertEqual(foreign.currency, "UNKNOWN"); XCTAssertEqual(foreign.trial, true)
    }
    func testTaiwanTradingHours() {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HH:mm"; format.timeZone = TaiwanMarket.zone; format.locale = Locale(identifier: "en_US_POSIX")
        func at(_ text: String) -> Date { format.date(from: text)! }
        XCTAssertFalse(TaiwanMarket.isOpen(at("2026-10-16 08:54")))
        XCTAssertTrue(TaiwanMarket.isOpen(at("2026-10-16 08:55")), "Friday, opening trial match")
        XCTAssertTrue(TaiwanMarket.isOpen(at("2026-10-16 13:40")))
        XCTAssertFalse(TaiwanMarket.isOpen(at("2026-10-16 13:41")))
        XCTAssertFalse(TaiwanMarket.isOpen(at("2026-10-17 10:00")), "Saturday")
    }
    @MainActor func testLiveQuotesWinWhenFresherAndAreKept() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PortfolioStore(url: url)
        try store.save(Holding(symbol: "2330", name: "台積電", shares: 10, unitCost: 100, broker: "", strategy: .unclassified))
        let close = try XCTUnwrap(StockSnapshot.bundled?.close("2330"))
        XCTAssertEqual(store.quote("2330")?.price, close.price)
        store.liveQuotes["2330"] = Quote(symbol: "2330", price: close.price + 5, changePercent: 0.3, date: DataChecks.day(), fetchedAt: Date(), currency: "TWD")
        XCTAssertEqual(store.quote("2330")?.price, close.price + 5, "A pushed price newer than the bundled close is shown")
        store.favorite("0050")
        store.liveQuotes["0050"] = Quote(symbol: "0050", price: 99, changePercent: 0.1, date: DataChecks.day(), fetchedAt: Date(), currency: "TWD", trial: true)
        store.liveQuotes["9999"] = Quote(symbol: "9999", price: 1, changePercent: nil, date: "2020-01-02", fetchedAt: .distantPast)
        store.live.stop()
        let reopened = PortfolioStore(url: url)
        let kept = try XCTUnwrap(reopened.data.quotes["2330"], "Holdings keep their last live price")
        XCTAssertEqual(kept.price, close.price + 5); XCTAssertNil(kept.trial)
        XCTAssertNil(reopened.data.quotes["0050"], "A trial-match price is not saved as the day's price")
        XCTAssertNil(reopened.data.quotes["9999"], "Only holdings and the watchlist are saved")
    }
}
