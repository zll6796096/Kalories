import XCTest

@MainActor
final class AdultAccessUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConfirmationGatesCaptureAndPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--fixture-success",
            "--reset-adult-access",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["adult-access.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture.camera"].exists)
        XCTAssertFalse(app.buttons["capture.library"].exists)
        XCTAssertFalse(app.buttons["capture.fixture"].exists)
        XCTAssertFalse(app.buttons["capture.analyze"].exists)

        let confirm = app.buttons["adult-access.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.tap()
        XCTAssertTrue(app.buttons["capture.fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["adult-access.title"].exists)

        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--fixture-success",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["capture.fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["adult-access.title"].exists)
    }
}
