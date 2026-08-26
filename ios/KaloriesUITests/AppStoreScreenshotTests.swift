import XCTest
import UIKit

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
        XCTAssertTrue(capture.staticTexts["カロスキャン"].exists)
        let capturePNG = attach(name: "app-store-01-capture")
        assertCleanSystemEdges(in: capturePNG, name: "app-store-01-capture")
        capture.terminate()

        let summary = launch(mode: "--fixture-screenshot-summary")
        waitForResultFrame(in: summary)
        let summaryElements = [
            summary.staticTexts["焼き鮭定食"],
            summary.staticTexts["64"],
            summary.staticTexts["推定精度: 高"].firstMatch,
            summary.staticTexts["ナトリウム · 多め"],
            element(in: summary, labelPrefix: "エネルギー,"),
        ]
        assertFullyVisible(summaryElements, in: summary)
        let summaryPNG = attach(name: "app-store-02-summary")
        assertCleanSystemEdges(in: summaryPNG, name: "app-store-02-summary")
        summary.terminate()

        let nutrition = launch(mode: "--fixture-screenshot-nutrition")
        waitForResultFrame(in: nutrition)
        let nutritionElements = [
            nutrition.staticTexts["焼き鮭定食"],
            element(in: nutrition, labelPrefix: "エネルギー,"),
            element(in: nutrition, labelPrefix: "たんぱく質,"),
        ]
        assertFullyVisible(nutritionElements, in: nutrition)
        let nutritionPNG = attach(name: "app-store-03-nutrition")
        assertCleanSystemEdges(in: nutritionPNG, name: "app-store-03-nutrition")
        nutrition.terminate()

        let preview = launch(mode: "--fixture-screenshot-preview")
        let analyze = preview.buttons["capture.analyze"]
        let appTitle = preview.staticTexts["カロスキャン"]
        let consent = preview.staticTexts[
            "分析を開始すると、写真は今回の食事分析のために Kalories サービスと Gemini へ送信されます。"
        ]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        assertFullyVisible([appTitle, consent, analyze], in: preview)
        let previewPNG = attach(name: "app-store-04-consent")
        assertCleanSystemEdges(in: previewPNG, name: "app-store-04-consent")
        preview.terminate()

        let uncertainty = launch(mode: "--fixture-screenshot-uncertainty")
        waitForResultFrame(in: uncertainty)
        let uncertaintyElements = [
            element(in: uncertainty, labelPrefix: "推定量,"),
            uncertainty.staticTexts["推定の前提"],
            uncertainty.staticTexts["写真に写っている量のみを推定しています。"],
            uncertainty.staticTexts["調味料の量を推定しています。"],
            uncertainty.staticTexts[
                "写真からの推定値です。1食の参考であり、医療上の診断ではありません。"
            ],
            uncertainty.buttons["result.retake"],
        ]
        assertFullyVisible(uncertaintyElements, in: uncertainty)
        let uncertaintyPNG = attach(name: "app-store-05-uncertainty")
        assertCleanSystemEdges(in: uncertaintyPNG, name: "app-store-05-uncertainty")

        XCTAssertEqual(Set([
            capturePNG,
            summaryPNG,
            nutritionPNG,
            previewPNG,
            uncertaintyPNG,
        ]).count, 5, "Every App Store screenshot must be a distinct content state")
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

    private func waitForResultFrame(in app: XCUIApplication) {
        XCTAssertTrue(
            element(in: app, id: "result.screenshot.ready").waitForExistence(timeout: 5),
            "The DEBUG screenshot frame must finish before UI assertions or capture"
        )
    }

    private func element(in app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func element(in app: XCUIApplication, labelPrefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", labelPrefix)
        ).firstMatch
    }

    private func assertFullyVisible(
        _ elements: [XCUIElement],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let safeFrame = CGRect(
            x: app.frame.minX,
            y: app.frame.minY + 60,
            width: app.frame.width,
            height: app.frame.height - 84
        )
        for element in elements {
            XCTAssertTrue(element.exists, file: file, line: line)
            XCTAssertTrue(
                safeFrame.contains(element.frame),
                "Element is outside the safe screenshot frame: \(element.frame)",
                file: file,
                line: line
            )
        }
    }

    private func assertCleanSystemEdges(
        in png: Data,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let image = UIImage(data: png)?.cgImage,
              let pixels = rgbaPixels(from: image) else {
            XCTFail("Could not decode screenshot pixels for \(name)", file: file, line: line)
            return
        }

        let width = image.width
        let height = image.height
        let statusRange = Int(Double(height) * 0.01)..<Int(Double(height) * 0.04)
        var darkStatusPixels = 0
        for y in statusRange {
            for x in 0..<width {
                let offset = ((y * width) + x) * 4
                if pixels[offset] < 80,
                   pixels[offset + 1] < 80,
                   pixels[offset + 2] < 80,
                   pixels[offset + 3] > 200 {
                    darkStatusPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(
            darkStatusPixels,
            100,
            "\(name) must retain visible status-bar icons",
            file: file,
            line: line
        )

        let bottomStart = height - max(24, height / 100)
        let horizontalInset = width / 20
        let referenceOffset = (((height - 1) * width) + (width / 2)) * 4
        let reference = Array(pixels[referenceOffset..<(referenceOffset + 3)])
        var backgroundPixels = 0
        var sampledPixels = 0
        for y in bottomStart..<height {
            for x in horizontalInset..<(width - horizontalInset) {
                let offset = ((y * width) + x) * 4
                sampledPixels += 1
                if zip(pixels[offset..<(offset + 3)], reference).allSatisfy({
                    abs(Int($0.0) - Int($0.1)) <= 2
                }) {
                    backgroundPixels += 1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(
            Double(backgroundPixels) / Double(sampledPixels),
            0.99,
            "\(name) must end on a clean background, not a clipped adjacent card or control",
            file: file,
            line: line
        )
    }

    private func rgbaPixels(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
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
