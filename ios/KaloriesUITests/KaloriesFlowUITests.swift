import XCTest

@MainActor
final class KaloriesFlowUITests: XCTestCase {
    private let disclaimer = "写真からの推定値です。1食の参考であり、医療上の診断ではありません。"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSuccessFixtureCompletesNativeAnalysisFlowInJapanese() {
        let app = launchApp(fixture: "--fixture-success")

        let fixtureButton = app.buttons["capture.fixture"]
        XCTAssertTrue(fixtureButton.waitForExistence(timeout: 5))
        fixtureButton.tap()

        let analyzeButton = app.buttons["capture.analyze"]
        XCTAssertTrue(analyzeButton.waitForExistence(timeout: 5))
        analyzeButton.tap()

        let resultPage = element(in: app, identifier: "result.page")
        XCTAssertTrue(resultPage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["焼き鮭定食"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["64"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["おおむね良好"].waitForExistence(timeout: 2))

        let disclaimerText = app.staticTexts[disclaimer]
        scrollToDiscover(disclaimerText, in: app)

        let retakeButton = app.buttons["result.retake"]
        scrollToDiscover(retakeButton, in: app)
    }

    func testTimeoutFixtureRetriesThroughTheNormalFailureFlow() {
        let app = launchApp(fixture: "--fixture-timeout")

        let fixtureButton = app.buttons["capture.fixture"]
        XCTAssertTrue(fixtureButton.waitForExistence(timeout: 5))
        fixtureButton.tap()

        let analyzeButton = app.buttons["capture.analyze"]
        XCTAssertTrue(analyzeButton.waitForExistence(timeout: 5))
        analyzeButton.tap()

        let timeoutError = app.staticTexts["error.timeout"]
        XCTAssertTrue(timeoutError.waitForExistence(timeout: 5))

        let retryButton = app.buttons["error.retry"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: 2))
        retryButton.tap()

        XCTAssertTrue(
            element(in: app, identifier: "result.page").waitForExistence(timeout: 5)
        )
    }

    private func launchApp(fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            fixture,
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()
        return app
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func scrollToDiscover(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var attempts = 0
        while !element.isHittable, attempts < 10 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.exists, file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }
}
