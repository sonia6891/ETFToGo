import XCTest

final class ETFToGoUITests: XCTestCase {
    func testOTCCatalogAndRestoredResearchNavigation() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset", "--tab", "1"]; app.launch()
        let search = app.textFields["fund-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("00679B\n")
        let fund = app.staticTexts["元大美債20年"]; XCTAssertTrue(fund.waitForExistence(timeout: 5)); fund.tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["成分股與權重"].waitForExistence(timeout: 5))
        app.buttons["成分股與權重"].tap()
        XCTAssertTrue(app.buttons["更新成分股"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["尚無成分資料"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "restored-components"; attachment.lifetime = .keepAlways; add(attachment)
        app.tabBars.buttons["工具"].tap(); app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "券商持有資料")).firstMatch.tap()
        XCTAssertTrue(app.textFields["broker-import-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["選擇庫存 CSV"].exists)
    }
    func testAllTabsAndSearch() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["home-add-holding"].waitForExistence(timeout: 10))
        app.tabBars.buttons["找 ETF"].tap()
        let search = app.textFields["fund-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("0050\n")
        XCTAssertTrue(app.staticTexts["元大台灣50"].exists)
        XCTAssertFalse(app.staticTexts["國泰永續高股息"].exists)
        app.tabBars.buttons["我的持有"].tap()
        XCTAssertTrue(app.buttons["add-holding"].waitForExistence(timeout: 5))
        app.tabBars.buttons["配息"].tap()
        XCTAssertTrue(app.buttons["記錄一筆配息"].waitForExistence(timeout: 5))
        app.tabBars.buttons["工具"].tap()
        XCTAssertTrue(app.staticTexts["富果行情連線"].waitForExistence(timeout: 5))
    }
    func testHoldingSurvivesRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset"]; app.launch()
        app.buttons["home-add-holding"].tap()
        app.textFields["holding-symbol"].tap(); app.textFields["holding-symbol"].typeText("0050")
        let name = app.textFields["holding-name"]
        if (name.value as? String) == "ETF 名稱" { name.tap(); name.typeText("Test ETF") }
        app.textFields["holding-shares"].tap(); app.textFields["holding-shares"].typeText("1000")
        app.textFields["holding-cost"].tap(); app.textFields["holding-cost"].typeText("50")
        app.textFields["holding-broker"].tap(); app.textFields["holding-broker"].typeText("Test Broker")
        app.buttons["save-holding"].tap()
        XCTAssertTrue(app.buttons["home-add-holding"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing", "--tab", "2"]; app.launch()
        XCTAssertTrue(app.staticTexts["Test Broker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["0050"].exists)
    }
}
