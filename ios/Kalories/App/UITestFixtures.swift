#if DEBUG
import Foundation
import UIKit

@MainActor
enum UITestFixtures {
    enum ResultScreenshotFrame: Equatable {
        case summary
        case nutrition
        case uncertainty
    }

    private enum Mode: Equatable {
        case success
        case timeout
        case screenshotCapture
        case screenshotPreview
        case screenshotSummary
        case screenshotNutrition
        case screenshotUncertainty

        var isScreenshot: Bool {
            switch self {
            case .screenshotCapture, .screenshotPreview, .screenshotSummary,
                 .screenshotNutrition, .screenshotUncertainty:
                true
            case .success, .timeout:
                false
            }
        }

        var resultScreenshotFrame: ResultScreenshotFrame? {
            switch self {
            case .screenshotSummary:
                .summary
            case .screenshotNutrition:
                .nutrition
            case .screenshotUncertainty:
                .uncertainty
            case .success, .timeout, .screenshotCapture, .screenshotPreview:
                nil
            }
        }
    }

    static var isActive: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && fixtureMode(in: arguments) != nil
    }

    static func isScreenshotMode(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        fixtureMode(in: arguments)?.isScreenshot == true
    }

    static func resultScreenshotFrame(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> ResultScreenshotFrame? {
        fixtureMode(in: arguments)?.resultScreenshotFrame
    }

    static func environmentIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) throws -> AppEnvironment? {
        let adultAccessArguments = arguments.filter {
            $0.hasPrefix("--adult-access") ||
                $0.hasPrefix("--reset-adult-access")
        }
        guard arguments.contains("--ui-testing") else {
            guard adultAccessArguments.isEmpty else {
                throw AppFailure.invalidConfiguration
            }
            return nil
        }
        let allowedAdultAccessArguments = [
            "--adult-access-confirmed",
            "--reset-adult-access",
        ]
        guard
            adultAccessArguments.count <= 1,
            adultAccessArguments.allSatisfy(allowedAdultAccessArguments.contains)
        else {
            throw AppFailure.invalidConfiguration
        }
        guard let mode = fixtureMode(in: arguments) else {
            throw AppFailure.invalidConfiguration
        }
        guard
            let privacyURL = URL(string: "https://kalories.invalid/privacy/"),
            let supportURL = URL(string: "https://kalories.invalid/support/")
        else {
            throw AppFailure.invalidConfiguration
        }

        let service = UITestAnalysisService(
            result: canonicalResult,
            failsOnceWithTimeout: mode == .timeout
        )
        let defaults = UserDefaults.standard
        if adultAccessArguments.contains("--reset-adult-access") {
            defaults.removeObject(forKey: AdultAccessPreference.storageKey)
        }
        let adultAccessPreference = AdultAccessPreference(defaults: defaults)
        if adultAccessArguments.contains("--adult-access-confirmed") {
            adultAccessPreference.confirm()
        }
        let flow = AppFlowModel(service: service, processor: ImageProcessor())
        switch mode {
        case .screenshotPreview:
            selectImage(into: flow)
        case .screenshotSummary, .screenshotNutrition, .screenshotUncertainty:
            selectImage(into: flow)
            flow.analyze()
        case .success, .timeout, .screenshotCapture:
            break
        }

        return AppEnvironment(
            flow: flow,
            adultAccess: AdultAccessModel(
                preference: adultAccessPreference
            ),
            localizer: AppLocalizer(locale: .ja),
            cameraPresentation: CameraPresentationController(
                authorization: CameraAuthorizationService()
            ),
            privacyURL: privacyURL,
            supportURL: supportURL
        )
    }

    static func selectImage(into flow: AppFlowModel) {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 960, height: 360),
            format: format
        )
        let image = renderer.image { context in
            let canvas = CGRect(x: 0, y: 0, width: 960, height: 360)
            UIColor(red: 0.91, green: 0.84, blue: 0.72, alpha: 1).setFill()
            context.fill(canvas)

            let graphics = context.cgContext
            graphics.saveGState()
            graphics.setShadow(
                offset: CGSize(width: 0, height: 12),
                blur: 18,
                color: UIColor.black.withAlphaComponent(0.16).cgColor
            )
            UIColor(red: 0.83, green: 0.80, blue: 0.72, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 32, y: 24, width: 700, height: 312)).fill()
            graphics.restoreGState()

            UIColor(red: 0.98, green: 0.97, blue: 0.92, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 48, y: 36, width: 668, height: 284)).fill()

            UIColor(red: 0.96, green: 0.95, blue: 0.88, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 80, y: 74, width: 206, height: 174)).fill()
            UIColor(red: 1, green: 0.99, blue: 0.94, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 98, y: 58, width: 170, height: 150)).fill()
            for grain in [
                CGRect(x: 122, y: 88, width: 44, height: 22),
                CGRect(x: 170, y: 76, width: 46, height: 22),
                CGRect(x: 204, y: 108, width: 42, height: 20),
                CGRect(x: 138, y: 130, width: 46, height: 22),
                CGRect(x: 188, y: 146, width: 42, height: 20),
            ] {
                UIBezierPath(ovalIn: grain).fill()
            }

            UIColor(red: 0.93, green: 0.39, blue: 0.25, alpha: 1).setFill()
            UIBezierPath(
                roundedRect: CGRect(x: 288, y: 82, width: 286, height: 136),
                cornerRadius: 48
            ).fill()
            UIColor(red: 1, green: 0.60, blue: 0.42, alpha: 1).setFill()
            UIBezierPath(
                roundedRect: CGRect(x: 304, y: 94, width: 254, height: 100),
                cornerRadius: 38
            ).fill()

            graphics.setStrokeColor(
                UIColor(red: 0.48, green: 0.24, blue: 0.14, alpha: 0.72).cgColor
            )
            graphics.setLineWidth(10)
            graphics.setLineCap(.round)
            for startX in stride(from: 326.0, through: 510.0, by: 46.0) {
                graphics.move(to: CGPoint(x: startX, y: 112))
                graphics.addLine(to: CGPoint(x: startX + 24, y: 174))
                graphics.strokePath()
            }

            UIColor(red: 0.20, green: 0.55, blue: 0.24, alpha: 1).setFill()
            for broccoli in [
                CGRect(x: 528, y: 218, width: 70, height: 58),
                CGRect(x: 574, y: 202, width: 72, height: 62),
                CGRect(x: 616, y: 226, width: 66, height: 54),
            ] {
                UIBezierPath(ovalIn: broccoli).fill()
            }
            UIColor(red: 0.11, green: 0.38, blue: 0.16, alpha: 1).setFill()
            context.fill(CGRect(x: 586, y: 250, width: 22, height: 44))

            UIColor(red: 0.91, green: 0.20, blue: 0.18, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 470, y: 226, width: 62, height: 62)).fill()
            UIColor(red: 1, green: 0.86, blue: 0.28, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 594, y: 76, width: 88, height: 88)).fill()
            UIColor(red: 1, green: 0.97, blue: 0.63, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 606, y: 88, width: 64, height: 64)).fill()

            graphics.saveGState()
            graphics.setShadow(
                offset: CGSize(width: 0, height: 10),
                blur: 14,
                color: UIColor.black.withAlphaComponent(0.18).cgColor
            )
            UIColor(red: 0.22, green: 0.18, blue: 0.15, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 758, y: 70, width: 164, height: 226)).fill()
            graphics.restoreGState()
            UIColor(red: 0.45, green: 0.25, blue: 0.14, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 774, y: 86, width: 132, height: 164)).fill()
            UIColor(red: 0.91, green: 0.84, blue: 0.62, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 798, y: 116, width: 42, height: 24)).fill()
            UIColor(red: 0.18, green: 0.43, blue: 0.20, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 848, y: 156, width: 34, height: 22)).fill()
        }
        flow.select(image)
    }

    private static func fixtureMode(in arguments: [String]) -> Mode? {
        let fixtureArguments = arguments.filter { $0.hasPrefix("--fixture-") }
        guard fixtureArguments.count == 1 else {
            return nil
        }
        switch fixtureArguments[0] {
        case "--fixture-success":
            return .success
        case "--fixture-timeout":
            return .timeout
        case "--fixture-screenshot-capture":
            return .screenshotCapture
        case "--fixture-screenshot-preview":
            return .screenshotPreview
        case "--fixture-screenshot-summary":
            return .screenshotSummary
        case "--fixture-screenshot-nutrition":
            return .screenshotNutrition
        case "--fixture-screenshot-uncertainty":
            return .screenshotUncertainty
        default:
            return nil
        }
    }

    private static let canonicalResult = AnalysisResult(
        foodDetected: true,
        foodNames: FoodNames(
            zh: "烤鲑鱼套餐",
            ja: "焼き鮭定食",
            en: "Grilled salmon set"
        ),
        portionGrams: 420,
        nutrients: NutrientValues(
            caloriesKcal: 640,
            proteinG: 34,
            carbsG: 68,
            fatG: 24,
            fiberG: 8.4,
            sugarG: 12,
            sodiumMg: 980
        ),
        confidence: Confidence(
            overall: .high,
            portion: .medium,
            nutrients: NutrientConfidence(
                caloriesKcal: .high,
                proteinG: .high,
                carbsG: .medium,
                fatG: .medium,
                fiberG: .medium,
                sugarG: .low,
                sodiumMg: .low
            )
        ),
        assumptionKeys: [.visiblePortionOnly, .seasoningEstimated],
        assessment: Assessment(
            score: 64,
            tier: .mostlyBalanced,
            statuses: NutrientStatuses(
                caloriesKcal: .appropriate,
                proteinG: .high,
                carbsG: .low,
                fatG: .high,
                fiberG: .appropriate,
                sugarG: .appropriate,
                sodiumMg: .high
            ),
            suggestionKeys: [.reduceSauce, .adjustStaple],
            scoringReasons: [.proteinHigh, .fatHigh, .carbsLow, .sodiumHigh],
            insufficientData: false
        )
    )
}

private actor UITestAnalysisService: AnalysisServing {
    private let result: AnalysisResult
    private let failsOnceWithTimeout: Bool
    private var attempts = 0

    init(result: AnalysisResult, failsOnceWithTimeout: Bool) {
        self.result = result
        self.failsOnceWithTimeout = failsOnceWithTimeout
    }

    func analyze(dataURI: String) async throws -> AnalysisResult {
        defer { attempts += 1 }
        if failsOnceWithTimeout, attempts == 0 {
            throw AppFailure.timeout
        }
        return result
    }
}
#endif
