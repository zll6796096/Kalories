import XCTest

@MainActor
final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCapturesFiveJapaneseAppStoreScreenshots() throws {
        let capture = launch(mode: "--fixture-screenshot-capture")
        XCTAssertTrue(capture.buttons["capture.camera"].waitForExistence(timeout: 5))
        let targetSize = CGSize(width: 440, height: 956)
        guard capture.frame.size == targetSize else {
            let actualSize = capture.frame.size
            capture.terminate()
            throw XCTSkip(
                "App Store assets require the iPhone 17 Pro Max logical size "
                    + "\(targetSize); current destination is \(actualSize)."
            )
        }
        attach(name: "app-store-01-capture")
        capture.terminate()

        let result = launch(mode: "--fixture-screenshot-result")
        XCTAssertTrue(element(in: result, id: "result.page").waitForExistence(timeout: 5))
        let mealName = result.staticTexts["焼き鮭定食"]
        let score = result.staticTexts["64"]
        let overallConfidence = result.staticTexts["推定精度: 高"].firstMatch
        let mainConclusion = result.staticTexts["ナトリウム · 多め"]
        let energy = element(in: result, labelPrefix: "エネルギー,")
        let carbs = element(in: result, labelPrefix: "炭水化物,")
        XCTAssertTrue(mealName.waitForExistence(timeout: 2))
        XCTAssertTrue(score.waitForExistence(timeout: 2))
        XCTAssertTrue(overallConfidence.waitForExistence(timeout: 2))
        XCTAssertTrue(mainConclusion.waitForExistence(timeout: 2))
        XCTAssertTrue(energy.waitForExistence(timeout: 2))
        assertFullyVisible(
            [mealName, score, overallConfidence, mainConclusion, energy],
            in: result
        )
        assertFullyVisibleOrOutsideScreen(carbs, in: result)
        revealSystemChrome(in: result)
        let summaryEnergyY = energy.frame.minY
        let summaryPNG = attach(name: "app-store-02-summary")

        let protein = element(in: result, labelPrefix: "たんぱく質,")
        let fat = element(in: result, labelPrefix: "脂質,")
        alignLastVisibleCardOnScreen(carbs, in: result)
        settleSystemChrome(for: 3)
        assertFullyVisible([mealName, energy, protein, carbs], in: result)
        assertFullyVisibleOrOutsideScreen(fat, in: result)
        XCTAssertGreaterThanOrEqual(
            summaryEnergyY - energy.frame.minY,
            30,
            "The nutrition screenshot must be materially scrolled beyond the summary state"
        )
        let nutritionPNG = attach(name: "app-store-03-nutrition")
        XCTAssertNotEqual(
            nutritionPNG,
            summaryPNG,
            "Summary and nutrition App Store assets must not be duplicate images"
        )
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
        let sodium = element(in: uncertainty, labelPrefix: "ナトリウム,")
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
        alignFirstVisibleCard(portion, targetTop: 68, in: uncertainty)
        revealSystemChrome(in: uncertainty, distance: 100)
        assertEndsAboveTopViewport(sodium, in: uncertainty)
        assertStartsBelowTopViewport(portion, in: uncertainty)
        assertFullyVisible([portion], in: uncertainty)
        assertFullyVisible(uncertaintyElements, in: uncertainty)
        assertFullyVisibleOrOutsideScreen(
            uncertainty.buttons["result.retake"],
            in: uncertainty
        )
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

    private func alignFirstVisibleCard(
        _ element: XCUIElement,
        targetTop: CGFloat,
        in app: XCUIApplication
    ) {
        for _ in 0..<12 {
            settleSystemChrome()
            let delta = element.frame.minY - targetTop
            guard delta > 2 else {
                return
            }
            let normalizedOffset = min((delta + 8) / app.frame.height, 0.30)
            let startY = 0.65
            let endY = startY - normalizedOffset
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                .press(
                    forDuration: 0.01,
                    thenDragTo: app.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: endY)
                    ),
                    withVelocity: .slow,
                    thenHoldForDuration: 0
                )
        }
    }

    private func alignLastVisibleCardOnScreen(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) {
        guard element.exists else {
            return
        }
        let startY = 0.62
        let normalizedOffset = 310 / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            .press(
                forDuration: 0.01,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: startY - normalizedOffset)
                ),
                withVelocity: .slow,
                thenHoldForDuration: 0
            )
        settleSystemChrome()

        let restoreOffset = 100 / app.frame.height
        let restoreStartY = 0.40
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: restoreStartY))
            .press(
                forDuration: 0.01,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(
                        dx: 0.5,
                        dy: restoreStartY + restoreOffset
                    )
                ),
                withVelocity: .slow,
                thenHoldForDuration: 0
            )
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
        let safeTop = app.frame.minY + 72
        let safeBottom = app.frame.maxY - 24
        let frame = element.frame
        return frame.minY >= safeTop && frame.maxY <= safeBottom
    }

    private func assertEndsAboveTopViewport(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, file: file, line: line)
        XCTAssertLessThanOrEqual(
            element.frame.maxY,
            app.frame.minY + 68,
            "The preceding card must be fully outside the screenshot viewport",
            file: file,
            line: line
        )
    }

    private func assertStartsBelowTopViewport(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            element.frame.minY,
            app.frame.minY + 96,
            "The first visible card must start below the protected top viewport",
            file: file,
            line: line
        )
    }

    private func assertFullyVisibleOrOutsideScreen(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, file: file, line: line)
        let frame = element.frame
        let isFullyVisibleOnScreen =
            frame.minY >= app.frame.minY + 72
            && frame.maxY <= app.frame.maxY
        let isOutsideScreen = frame.maxY <= app.frame.minY || frame.minY >= app.frame.maxY
        XCTAssertTrue(
            isFullyVisibleOnScreen || isOutsideScreen,
            "Adjacent element must be fully visible or outside the screenshot: \(frame)",
            file: file,
            line: line
        )
    }

    private func settleSystemChrome(for duration: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: duration))
    }

    private func revealSystemChrome(
        in app: XCUIApplication,
        distance: CGFloat = 20
    ) {
        let startY = 0.40
        let revealOffset = distance / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            .press(
                forDuration: 0.01,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: startY + revealOffset)
                ),
                withVelocity: .slow,
                thenHoldForDuration: 0
            )
        settleSystemChrome(for: 3)
    }

    @discardableResult
    private func attach(name: String) -> Data {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return screenshot.pngRepresentation
    }
}
