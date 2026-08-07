import Foundation

enum NutritionMetricKind: String, Equatable, Hashable, Sendable {
    case calories
    case protein
    case carbs
    case fat
    case fiber
    case sugar
    case sodium
    case portion
}

enum NutritionStatusStyle: Equatable, Sendable {
    case low
    case appropriate
    case high
    case indeterminate
}

struct NutritionStatusPresentation: Equatable, Sendable {
    let text: String
    let symbolName: String
    let style: NutritionStatusStyle
}

struct NutritionMetricPresentation: Equatable, Sendable {
    let kind: NutritionMetricKind
    let label: String
    let valueText: String
    let confidenceLabel: String
    let status: NutritionStatusPresentation?
}

struct ScorePresentation: Equatable, Sendable {
    let valueText: String
    let scaleText: String?
    let tierLabel: String

    var displayText: String {
        guard let scaleText else {
            return valueText
        }
        return "\(valueText) \(scaleText)"
    }
}

struct ResultPresentation: Equatable, Sendable {
    let foodName: String
    let overallConfidenceLabel: String
    let score: ScorePresentation
    let strongestPositive: String
    let mainConcern: String
    let metrics: [NutritionMetricPresentation]
    let advice: [String]
    let assumptions: [String]
    let disclaimer: String
    let referenceBasis: String
}

struct ResultPresenter: Sendable {
    private let localizer: AppLocalizer

    private let positivePriority: [NutrientKey] = [
        .proteinG,
        .carbsG,
        .fatG,
        .fiberG,
        .caloriesKcal,
        .sugarG,
        .sodiumMg,
    ]

    private let concernPriority: [NutrientKey] = [
        .sodiumMg,
        .sugarG,
        .caloriesKcal,
        .proteinG,
        .carbsG,
        .fatG,
        .fiberG,
    ]

    init(localizer: AppLocalizer) {
        self.localizer = localizer
    }

    func present(_ result: AnalysisResult) -> ResultPresentation {
        ResultPresentation(
            foodName: foodName(from: result.foodNames),
            overallConfidenceLabel: confidenceLabel(result.confidence.overall),
            score: scorePresentation(result.assessment),
            strongestPositive: strongestPositive(in: result),
            mainConcern: mainConcern(in: result),
            metrics: metricPresentations(for: result),
            advice: Array(result.assessment.suggestionKeys.prefix(2)).map(suggestionText),
            assumptions: result.assumptionKeys.map(assumptionText),
            disclaimer: localizer.text("disclaimer"),
            referenceBasis: localizer.text("referenceBasis")
        )
    }

    private func foodName(from names: FoodNames?) -> String {
        guard let names else {
            return localizer.text("detectedFood")
        }

        switch localizer.locale {
        case .ja:
            return names.ja
        case .zh:
            return names.zh
        case .en:
            return names.en
        }
    }

    private func scorePresentation(_ assessment: Assessment) -> ScorePresentation {
        let score = assessment.tier != .indeterminate && !assessment.insufficientData
            ? assessment.score
            : nil

        return ScorePresentation(
            valueText: score.map(String.init) ?? "—",
            scaleText: score == nil ? nil : "/ 100",
            tierLabel: tierLabel(assessment.tier)
        )
    }

    private func strongestPositive(in result: AnalysisResult) -> String {
        for confidence in [ConfidenceLevel.high, .medium] {
            if let nutrient = positivePriority.first(where: {
                result.assessment.statuses[$0] == .appropriate
                    && nutrientConfidence(result.confidence.nutrients, for: $0) == confidence
            }) {
                return localizedStatus(for: nutrient, status: .appropriate)
            }
        }
        return localizer.text("noClearPositive")
    }

    private func mainConcern(in result: AnalysisResult) -> String {
        if let nutrient = concernPriority.first(where: {
            let status = result.assessment.statuses[$0]
            return status == .low || status == .high
        }) {
            return localizedStatus(
                for: nutrient,
                status: result.assessment.statuses[nutrient]
            )
        }

        return localizer.text(
            result.assessment.insufficientData ? "noClearConcern" : "noMajorConcern"
        )
    }

    private func metricPresentations(for result: AnalysisResult) -> [NutritionMetricPresentation] {
        let nutrients: [(NutritionMetricKind, NutrientKey, String)] = [
            (.calories, .caloriesKcal, "kcal"),
            (.protein, .proteinG, "g"),
            (.carbs, .carbsG, "g"),
            (.fat, .fatG, "g"),
            (.fiber, .fiberG, "g"),
            (.sugar, .sugarG, "g"),
            (.sodium, .sodiumMg, "mg"),
        ]

        var metrics = nutrients.map { kind, key, unit in
            NutritionMetricPresentation(
                kind: kind,
                label: nutrientLabel(key),
                valueText: formatted(result.nutrients[key], unit: unit),
                confidenceLabel: confidenceLabel(
                    nutrientConfidence(result.confidence.nutrients, for: key)
                ),
                status: statusPresentation(
                    nutrient: key,
                    status: result.assessment.statuses[key]
                )
            )
        }
        metrics.append(
            NutritionMetricPresentation(
                kind: .portion,
                label: localizer.text("portion"),
                valueText: formatted(result.portionGrams, unit: "g"),
                confidenceLabel: confidenceLabel(result.confidence.portion),
                status: nil
            )
        )
        return metrics
    }

    private func formatted(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite else {
            return "—"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = numberLocale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false

        guard let number = formatter.string(from: NSNumber(value: value)) else {
            return "—"
        }
        return "\(number) \(unit)"
    }

    private var numberLocale: Locale {
        switch localizer.locale {
        case .ja:
            Locale(identifier: "ja_JP")
        case .zh:
            Locale(identifier: "zh_CN")
        case .en:
            Locale(identifier: "en_US")
        }
    }

    private func confidenceLabel(_ confidence: ConfidenceLevel) -> String {
        switch confidence {
        case .low:
            localizer.text("confidenceLow")
        case .medium:
            localizer.text("confidenceMedium")
        case .high:
            localizer.text("confidenceHigh")
        }
    }

    private func tierLabel(_ tier: AssessmentTier) -> String {
        switch tier {
        case .balanced:
            localizer.text("tierBalanced")
        case .mostlyBalanced:
            localizer.text("tierMostlyBalanced")
        case .needsAttention:
            localizer.text("tierNeedsAttention")
        case .indeterminate:
            localizer.text("tierIndeterminate")
        }
    }

    private func nutrientLabel(_ nutrient: NutrientKey) -> String {
        switch nutrient {
        case .caloriesKcal:
            localizer.text("calories")
        case .proteinG:
            localizer.text("protein")
        case .carbsG:
            localizer.text("carbs")
        case .fatG:
            localizer.text("fat")
        case .fiberG:
            localizer.text("fiber")
        case .sugarG:
            localizer.text("sugar")
        case .sodiumMg:
            localizer.text("sodium")
        }
    }

    private func nutrientConfidence(
        _ confidence: NutrientConfidence,
        for nutrient: NutrientKey
    ) -> ConfidenceLevel {
        switch nutrient {
        case .caloriesKcal:
            confidence.caloriesKcal
        case .proteinG:
            confidence.proteinG
        case .carbsG:
            confidence.carbsG
        case .fatG:
            confidence.fatG
        case .fiberG:
            confidence.fiberG
        case .sugarG:
            confidence.sugarG
        case .sodiumMg:
            confidence.sodiumMg
        }
    }

    private func localizedStatus(for nutrient: NutrientKey, status: NutrientStatus) -> String {
        "\(nutrientLabel(nutrient)) · \(statusText(nutrient: nutrient, status: status))"
    }

    private func statusPresentation(
        nutrient: NutrientKey,
        status: NutrientStatus
    ) -> NutritionStatusPresentation {
        switch status {
        case .low:
            NutritionStatusPresentation(
                text: statusText(nutrient: nutrient, status: status),
                symbolName: "arrow.down.circle",
                style: .low
            )
        case .appropriate:
            NutritionStatusPresentation(
                text: statusText(nutrient: nutrient, status: status),
                symbolName: "checkmark.circle",
                style: .appropriate
            )
        case .high:
            NutritionStatusPresentation(
                text: statusText(nutrient: nutrient, status: status),
                symbolName: "arrow.up.circle",
                style: .high
            )
        case .indeterminate:
            NutritionStatusPresentation(
                text: statusText(nutrient: nutrient, status: status),
                symbolName: "questionmark.circle",
                style: .indeterminate
            )
        }
    }

    private func statusText(nutrient: NutrientKey, status: NutrientStatus) -> String {
        switch status {
        case .low:
            localizer.text(nutrient == .sugarG ? "sugarLow" : "statusLow")
        case .appropriate:
            localizer.text("statusAppropriate")
        case .high:
            localizer.text("statusHigh")
        case .indeterminate:
            localizer.text("statusIndeterminate")
        }
    }

    private func suggestionText(_ suggestion: SuggestionKey) -> String {
        switch suggestion {
        case .addVegetables:
            localizer.text("suggestionAddVegetables")
        case .reduceSauce:
            localizer.text("suggestionReduceSauce")
        case .reduceSweetItems:
            localizer.text("suggestionReduceSweetItems")
        case .reduceFat:
            localizer.text("suggestionReduceFat")
        case .addProtein:
            localizer.text("suggestionAddProtein")
        case .adjustStaple:
            localizer.text("suggestionAdjustStaple")
        case .reducePortion:
            localizer.text("suggestionReducePortion")
        }
    }

    private func assumptionText(_ assumption: AssumptionKey) -> String {
        switch assumption {
        case .visiblePortionOnly:
            localizer.text("assumptionVisiblePortionOnly")
        case .portionEstimated:
            localizer.text("assumptionPortionEstimated")
        case .seasoningEstimated:
            localizer.text("assumptionSeasoningEstimated")
        case .hiddenIngredientsPossible:
            localizer.text("assumptionHiddenIngredientsPossible")
        }
    }
}
