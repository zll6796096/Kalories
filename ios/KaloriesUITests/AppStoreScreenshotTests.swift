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
        let mealName = result.staticTexts["焼き鮭定食"]
        let score = result.staticTexts["64"]
        let overallConfidence = result.staticTexts["推定精度: 高"].firstMatch
        let mainConclusion = result.staticTexts["ナトリウム · 多め"]
        let energy = element(in: result, labelPrefix: "エネルギー,")
        XCTAssertTrue(mealName.waitForExistence(timeout: 2))
        XCTAssertTrue(score.waitForExistence(timeout: 2))
        XCTAssertTrue(overallConfidence.waitForExistence(timeout: 2))
        XCTAssertTrue(mainConclusion.waitForExistence(timeout: 2))
        XCTAssertTrue(energy.waitForExistence(timeout: 2))
        assertFullyVisible(
            [mealName, score, overallConfidence, mainConclusion, energy],
            in: result
        )
        attach(name: "app-store-02-summary")

        let protein = element(in: result, labelPrefix: "たんぱく質,")
        scrollToShowAll([mealName, energy, protein], in: result)
        assertFullyVisible([mealName, energy, protein], in: result)
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
        XCTAssertTrue(element(in: uncertainty, id: "result.page").waitForExistence(timeout: 5))
        let fat = element(in: uncertainty, labelPrefix: "脂質,")
        let fiber = element(in: uncertainty, labelPrefix: "食物繊維,")
        let portion = element(in: uncertainty, labelPrefix: "推定量,")
        let assumptionsTitle = uncertainty.staticTexts["推定の前提"]
        let visiblePortionAssumption = uncertainty.staticTexts[
            "写真に写っている量のみを推定しています。"
        ]
        let seasoningAssumption = uncertainty.staticTexts[
            "調味料の量を推定しています。"
        ]
        let disclaimer = uncertainty.staticTexts[
            "写真からの推定値です。1食の参考であり、医療上の診断ではありません。"
        ]
        let uncertaintyElements = [
            portion,
            assumptionsTitle,
            visiblePortionAssumption,
            seasoningAssumption,
            disclaimer,
        ]
        scrollToShowAll(uncertaintyElements, in: uncertainty)
        alignAboveSafeTop(fat, in: uncertainty)
        assertAboveSafeTop(fat, in: uncertainty)
        assertFullyVisible([fiber], in: uncertainty)
        assertFullyVisible(uncertaintyElements, in: uncertainty)
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

    private func element(in app: XCUIApplication, labelPrefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", labelPrefix)
        ).firstMatch
    }

    private func scrollToShowAll(
        _ elements: [XCUIElement],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var attempts = 0
        while !elements.allSatisfy({ isFullyVisible($0, in: app) }), attempts < 36 {
            scroll(up: true, in: app)
            attempts += 1
        }
        assertFullyVisible(elements, in: app, file: file, line: line)
    }

    private func scroll(up: Bool, in app: XCUIApplication) {
        let startY = up ? 0.66 : 0.48
        let endY = up ? 0.58 : 0.56
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            .press(
                forDuration: 0.01,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: endY)
                )
            )
    }

    private func alignAboveSafeTop(_ element: XCUIElement, in app: XCUIApplication) {
        let safeTop = app.frame.minY + 64
        var attempts = 0
        while element.exists, element.frame.maxY > safeTop, attempts < 4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
                .press(
                    forDuration: 0.01,
                    thenDragTo: app.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)
                    ),
                    withVelocity: .slow,
                    thenHoldForDuration: 0
                )
            attempts += 1
        }
    }

    private func assertFullyVisible(
        _ elements: [XCUIElement],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for element in elements {
            XCTAssertTrue(element.exists, file: file, line: line)
            XCTAssertTrue(
                isFullyVisible(element, in: app),
                "Element \(element) is outside the safe screenshot frame: \(element.frame)",
                file: file,
                line: line
            )
        }
    }

    private func isFullyVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else {
            return false
        }
        let safeTop = app.frame.minY + 64
        let safeBottom = app.frame.maxY - 24
        let frame = element.frame
        return frame.minY >= safeTop && frame.maxY <= safeBottom
    }

    private func assertAboveSafeTop(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, file: file, line: line)
        XCTAssertLessThanOrEqual(
            element.frame.maxY,
            app.frame.minY + 64,
            "The preceding card must not enter the status-bar safe area",
            file: file,
            line: line
        )
    }

    private func attach(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
