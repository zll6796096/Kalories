import XCTest

@MainActor
final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCapturesFiveJapaneseAppStoreScreenshots() {
        let capture = launch(mode: "--fixture-screenshot-capture")
        XCTAssertTrue(capture.buttons["capture.camera"].waitForExistence(timeout: 5))
        attach(name: "app-store-01-capture")
        capture.terminate()

        let result = launch(mode: "--fixture-screenshot-result")
        XCTAssertTrue(element(in: result, id: "result.page").waitForExistence(timeout: 5))
        XCTAssertTrue(result.staticTexts["焼き鮭定食"].waitForExistence(timeout: 2))
        attach(name: "app-store-02-summary")

        let calories = result.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "エネルギー,")
        ).firstMatch
        scrollToDiscover(calories, in: result)
        attach(name: "app-store-03-nutrition")
        result.terminate()

        let preview = launch(mode: "--fixture-screenshot-preview")
        XCTAssertTrue(preview.buttons["capture.analyze"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            preview.staticTexts[
                "分析を開始すると、写真は今回の食事分析のために Kalories サービスと Gemini へ送信されます。"
            ].waitForExistence(timeout: 2)
        )
        attach(name: "app-store-04-consent")
        preview.terminate()

        let uncertainty = launch(mode: "--fixture-screenshot-result")
        let disclaimer = uncertainty.staticTexts[
            "写真からの推定値です。1食の参考であり、医療上の診断ではありません。"
        ]
        scrollToDiscover(disclaimer, in: uncertainty)
        attach(name: "app-store-05-uncertainty")
    }

    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--adult-access-confirmed",
            mode,
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
        ]
        app.launch()
        return app
    }

    private func element(in app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scrollToDiscover(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable, attempts < 10 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
    }

    private func attach(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
