import XCTest

@MainActor
final class AppLaunchTests: XCTestCase {
    func testAppLaunchesWithTitle() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["app.title"].waitForExistence(timeout: 5))
    }
}
