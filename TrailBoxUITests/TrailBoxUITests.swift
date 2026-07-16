import XCTest

final class TrailBoxUITests: XCTestCase {
    private func launch(
        consent: String,
        authenticated: Bool = false,
        expiredSession: Bool = false,
        reset: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-trailboxUITestMode", "-trailboxUITestConsent", consent]
        if reset { app.launchArguments.append("-trailboxUITestReset") }
        if authenticated { app.launchArguments.append("-trailboxUITestAuthenticated") }
        if expiredSession { app.launchArguments.append("-trailboxUITestExpiredSession") }
        app.launch()
        return app
    }

    func testGuestTabsRequireAuthenticationWithoutLeavingLoadingPage() {
        let app = launch(consent: "disabled")
        app.tabBars.buttons["运动记录"].tap()
        XCTAssertTrue(app.staticTexts["欢迎回到小野box"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["探索路线"].waitForExistence(timeout: 2))

        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["欢迎回到小野box"].waitForExistence(timeout: 3))
    }

    func testConsentAcceptDeclineAndSettingsDisable() {
        var app = launch(consent: "unknown")
        XCTAssertTrue(app.staticTexts["帮助改进小野box"].waitForExistence(timeout: 3))
        app.buttons["暂不"].tap()
        XCTAssertFalse(app.staticTexts["帮助改进小野box"].waitForExistence(timeout: 1))
        app.terminate()

        app = launch(consent: "unknown", authenticated: true)
        XCTAssertTrue(app.buttons["同意并继续"].waitForExistence(timeout: 3))
        app.buttons["同意并继续"].tap()
        app.tabBars.buttons["我的"].tap()
        app.buttons["设置"].tap()
        let toggle = app.switches["telemetry-consent-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let disabled = NSPredicate(format: "value == '0'")
        expectation(for: disabled, evaluatedWith: toggle)
        waitForExpectations(timeout: 3)
    }

    func testAuthenticatedRouteFavoriteDepartureAndShareEntry() {
        let app = launch(consent: "disabled", authenticated: true)
        XCTAssertTrue(app.staticTexts["北京西山测试环线"].waitForExistence(timeout: 5))
        app.staticTexts["北京西山测试环线"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["轨迹详情"].waitForExistence(timeout: 5))
        let favorite = app.buttons["收藏路线"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 3))
        favorite.tap()
        XCTAssertTrue(app.buttons["取消收藏路线"].waitForExistence(timeout: 3))

        let departure = app.buttons["route-departure-button"]
        XCTAssertTrue(departure.waitForExistence(timeout: 3))
        departure.tap()
        XCTAssertTrue(app.staticTexts["准备出发"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["导航到起点"].exists)
        XCTAssertTrue(app.staticTexts["导出 GPX"].exists)
        app.swipeDown()

        XCTAssertTrue(app.buttons["route-share-button"].waitForExistence(timeout: 3))
    }

    func testExpiredRestoredSessionReturnsToAuthentication() {
        let app = launch(consent: "disabled", authenticated: true, expiredSession: true)

        XCTAssertTrue(app.staticTexts["欢迎回到小野box"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["登录已过期，请重新登录"].exists)
        XCTAssertFalse(app.alerts["收藏路线"].exists)

        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["探索路线"].waitForExistence(timeout: 3))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["欢迎回到小野box"].waitForExistence(timeout: 3))
    }
}
