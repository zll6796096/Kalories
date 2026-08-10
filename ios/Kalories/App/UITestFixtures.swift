#if DEBUG
import Foundation
import UIKit

@MainActor
enum UITestFixtures {
    private enum Mode {
        case success
        case timeout
    }

    static var isActive: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && fixtureMode(in: arguments) != nil
    }

    static func environmentIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) throws -> AppEnvironment? {
        let adultAccessArguments = arguments.filter {
            $0.hasPrefix("--adult-access-") ||
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
        return AppEnvironment(
            flow: AppFlowModel(service: service, processor: ImageProcessor()),
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
            size: CGSize(width: 48, height: 48),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemGroupedBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 8, y: 12, width: 32, height: 24))
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
