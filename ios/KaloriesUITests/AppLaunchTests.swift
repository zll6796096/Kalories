import XCTest

@MainActor
final class AppLaunchTests: XCTestCase {
    func testAppLaunchesWithTitle() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--fixture-success",
            "--reset-adult-access",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["app.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["adult-access.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture.camera"].exists)
        XCTAssertFalse(app.buttons["capture.library"].exists)
        XCTAssertFalse(app.buttons["capture.fixture"].exists)
        XCTAssertFalse(app.buttons["capture.analyze"].exists)
    }
}
