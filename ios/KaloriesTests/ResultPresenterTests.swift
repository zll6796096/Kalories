import Foundation
import XCTest
@testable import Kalories

final class ResultPresenterTests: XCTestCase {
    func testCanonicalJapanesePresentationPreservesBackendResult() throws {
        let presentation = try presentCanonical(locale: .ja)

        XCTAssertEqual(presentation.foodName, "焼き鮭定食")
        XCTAssertEqual(presentation.overallConfidenceLabel, "高")
        XCTAssertEqual(presentation.score.valueText, "64")
        XCTAssertEqual(presentation.score.scaleText, "/ 100")
        XCTAssertEqual(presentation.score.displayText, "64 / 100")
        XCTAssertEqual(presentation.score.tierLabel, "おおむね良好")
        XCTAssertEqual(
            presentation.metrics.map(\.kind),
            [.calories, .protein, .carbs, .fat, .fiber, .sugar, .sodium, .portion]
        )
        XCTAssertEqual(
            presentation.metrics.map(\.valueText),
            ["640 kcal", "34 g", "68 g", "24 g", "8.4 g", "12 g", "980 mg", "420 g"]
        )
        XCTAssertEqual(
            presentation.metrics.map(\.confidenceLabel),
            ["高", "高", "中", "中", "中", "低", "低", "中"]
        )
        XCTAssertEqual(
            presentation.metrics.map { $0.status?.text },
            ["適量", "多め", "少なめ", "多め", "適量", "適量", "多め", nil]
        )
        XCTAssertEqual(
            presentation.metrics.map { $0.status?.symbolName },
            [
                "checkmark.circle",
                "arrow.up.circle",
                "arrow.down.circle",
                "arrow.up.circle",
                "checkmark.circle",
                "checkmark.circle",
                "arrow.up.circle",
                nil,
            ]
        )
        XCTAssertNil(presentation.metrics.last?.status)
        XCTAssertEqual(presentation.strongestPositive, "エネルギー · 適量")
        XCTAssertEqual(presentation.mainConcern, "ナトリウム · 多め")
        XCTAssertEqual(
            presentation.advice,
            [
                "ソースや汁を少なめにすると塩分を抑えられます。",
                "ご飯、パン、麺など主食の量を調整してみましょう。",
            ]
        )
        XCTAssertEqual(
            presentation.assumptions,
            [
                "写真に写っている量のみを推定しています。",
                "調味料の量を推定しています。",
            ]
        )
        XCTAssertEqual(
            presentation.disclaimer,
            "写真からの推定値です。1食の参考であり、医療上の診断ではありません。"
        )
        XCTAssertEqual(
            presentation.referenceBasis,
            "日本人の食事摂取基準（2025年版）とWHO指針を参考にしています。"
        )
    }

    func testMissingSugarUsesOnlyAnEmDash() throws {
        let canonical = try canonicalResult()
        let nutrients = NutrientValues(
            caloriesKcal: canonical.nutrients.caloriesKcal,
            proteinG: canonical.nutrients.proteinG,
            carbsG: canonical.nutrients.carbsG,
            fatG: canonical.nutrients.fatG,
            fiberG: canonical.nutrients.fiberG,
            sugarG: nil,
            sodiumMg: canonical.nutrients.sodiumMg
        )
        let statuses = NutrientStatuses(
            caloriesKcal: canonical.assessment.statuses.caloriesKcal,
            proteinG: canonical.assessment.statuses.proteinG,
            carbsG: canonical.assessment.statuses.carbsG,
            fatG: canonical.assessment.statuses.fatG,
            fiberG: canonical.assessment.statuses.fiberG,
            sugarG: .indeterminate,
            sodiumMg: canonical.assessment.statuses.sodiumMg
        )
        let result = replacing(canonical, nutrients: nutrients, statuses: statuses)

        let sugar = try XCTUnwrap(present(result, locale: .ja).metric(.sugar))

        XCTAssertEqual(sugar.valueText, "—")
        XCTAssertFalse(sugar.valueText.contains("0"))
        XCTAssertFalse(sugar.valueText.contains("g"))
        XCTAssertEqual(sugar.status?.text, "推定不可")
        XCTAssertEqual(sugar.status?.symbolName, "questionmark.circle")
    }

    func testUnavailableScoreHasNoScaleAndUsesIndeterminateTier() throws {
        let canonical = try canonicalResult()
        let statuses = NutrientStatuses(
            caloriesKcal: .appropriate,
            proteinG: .appropriate,
            carbsG: .appropriate,
            fatG: .appropriate,
            fiberG: .appropriate,
            sugarG: .appropriate,
            sodiumMg: .appropriate
        )
        let result = replacing(
            canonical,
            overallConfidence: .low,
            statuses: statuses,
            scoreState: .unavailable
        )

        let presentation = present(result, locale: .ja)

        XCTAssertEqual(presentation.score.valueText, "—")
        XCTAssertNil(presentation.score.scaleText)
        XCTAssertEqual(presentation.score.displayText, "—")
        XCTAssertFalse(presentation.score.displayText.contains("/100"))
        XCTAssertFalse(presentation.score.displayText.contains("/ 100"))
        XCTAssertEqual(presentation.score.tierLabel, "判定できません")
        XCTAssertEqual(presentation.mainConcern, "主な注目点を判断するには情報が足りません。")
    }

    func testStrongestPositiveUsesHighConfidenceBeforeStablePriority() throws {
        let canonical = try canonicalResult()
        let confidence = NutrientConfidence(
            caloriesKcal: .high,
            proteinG: .medium,
            carbsG: .medium,
            fatG: .high,
            fiberG: .high,
            sugarG: .medium,
            sodiumMg: .low
        )
        let statuses = NutrientStatuses(
            caloriesKcal: .appropriate,
            proteinG: .appropriate,
            carbsG: .appropriate,
            fatG: .appropriate,
            fiberG: .appropriate,
            sugarG: .appropriate,
            sodiumMg: .high
        )
        let result = replacing(
            canonical,
            nutrientConfidence: confidence,
            statuses: statuses,
            suggestionKeys: [.reduceSauce],
            scoringReasons: [.sodiumHigh]
        )

        let presentation = present(result, locale: .ja)

        XCTAssertEqual(presentation.strongestPositive, "脂質 · 適量")
        XCTAssertEqual(presentation.mainConcern, "ナトリウム · 多め")
    }

    func testFindingFallbacksRespectDataSufficiency() throws {
        let canonical = try canonicalResult()
        let allHigh = NutrientStatuses(
            caloriesKcal: .high,
            proteinG: .high,
            carbsG: .high,
            fatG: .high,
            fiberG: .high,
            sugarG: .high,
            sodiumMg: .high
        )
        let allAppropriate = NutrientStatuses(
            caloriesKcal: .appropriate,
            proteinG: .appropriate,
            carbsG: .appropriate,
            fatG: .appropriate,
            fiberG: .appropriate,
            sugarG: .appropriate,
            sodiumMg: .appropriate
        )

        let noPositive = replacing(
            canonical,
            statuses: allHigh,
            suggestionKeys: [.reduceSauce, .reducePortion],
            scoringReasons: [
                .caloriesHigh,
                .proteinHigh,
                .carbsHigh,
                .fatHigh,
                .sugarHigh,
                .sodiumHigh,
            ]
        )
        let noConcern = replacing(
            canonical,
            statuses: allAppropriate,
            suggestionKeys: [],
            scoringReasons: []
        )

        XCTAssertEqual(
            present(noPositive, locale: .ja).strongestPositive,
            "はっきりした良い点を判断できません。"
        )
        XCTAssertEqual(
            present(noConcern, locale: .ja).mainConcern,
            "大きな見直し点は見つかりませんでした。"
        )

        let insufficient = replacing(
            canonical,
            overallConfidence: .low,
            statuses: allAppropriate,
            scoreState: .unavailable
        )
        XCTAssertEqual(
            present(insufficient, locale: .ja).mainConcern,
            "主な注目点を判断するには情報が足りません。"
        )
    }

    func testAdviceIsCappedAtTwoKnownKeysInBackendOrder() throws {
        let canonical = try canonicalResult()
        let result = replacing(
            canonical,
            suggestionKeys: [
                .addVegetables,
                .reduceSauce,
                .reduceSweetItems,
                .reduceFat,
                .addProtein,
                .adjustStaple,
                .reducePortion,
            ]
        )

        XCTAssertEqual(
            present(result, locale: .en).advice,
            [
                "Consider adding vegetables, beans, or seaweed.",
                "Use less sauce or broth to reduce sodium.",
            ]
        )
    }

    func testChineseAndEnglishPresentLocalizedNamesLabelsAndDecimals() throws {
        let chinese = try presentCanonical(locale: .zh)
        let english = try presentCanonical(locale: .en)

        XCTAssertEqual(chinese.foodName, "烤鲑鱼套餐")
        XCTAssertEqual(chinese.metric(.calories)?.label, "热量")
        XCTAssertEqual(chinese.metric(.fiber)?.valueText, "8.4 g")
        XCTAssertEqual(chinese.score.tierLabel, "基本均衡")
        XCTAssertEqual(chinese.mainConcern, "钠 · 偏多")

        XCTAssertEqual(english.foodName, "Grilled salmon set")
        XCTAssertEqual(english.metric(.calories)?.label, "Calories")
        XCTAssertEqual(english.metric(.fiber)?.valueText, "8.4 g")
        XCTAssertEqual(english.score.tierLabel, "Mostly balanced")
        XCTAssertEqual(english.mainConcern, "Sodium · High")
    }

    private func presentCanonical(locale: AppLocale) throws -> ResultPresentation {
        present(try canonicalResult(), locale: locale)
    }

    private func present(_ result: AnalysisResult, locale: AppLocale) -> ResultPresentation {
        ResultPresenter(localizer: AppLocalizer(locale: locale)).present(result)
    }

    private func canonicalResult() throws -> AnalysisResult {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "canonical_analysis_result",
                withExtension: "json"
            )
        )
        return try StrictAnalysisDecoder().decode(Data(contentsOf: url))
    }

    private enum ScoreState {
        case canonical
        case unavailable
    }

    private func replacing(
        _ result: AnalysisResult,
        nutrients: NutrientValues? = nil,
        overallConfidence: ConfidenceLevel? = nil,
        nutrientConfidence: NutrientConfidence? = nil,
        statuses: NutrientStatuses? = nil,
        scoreState: ScoreState = .canonical,
        suggestionKeys: [SuggestionKey]? = nil,
        scoringReasons: [ScoringReason]? = nil
    ) -> AnalysisResult {
        let score: Int?
        let tier: AssessmentTier
        let insufficientData: Bool
        let defaultSuggestionKeys: [SuggestionKey]
        let defaultScoringReasons: [ScoringReason]
        switch scoreState {
        case .canonical:
            score = result.assessment.score
            tier = result.assessment.tier
            insufficientData = result.assessment.insufficientData
            defaultSuggestionKeys = result.assessment.suggestionKeys
            defaultScoringReasons = result.assessment.scoringReasons
        case .unavailable:
            score = nil
            tier = .indeterminate
            insufficientData = true
            defaultSuggestionKeys = []
            defaultScoringReasons = []
        }

        return AnalysisResult(
            foodDetected: result.foodDetected,
            foodNames: result.foodNames,
            portionGrams: result.portionGrams,
            nutrients: nutrients ?? result.nutrients,
            confidence: Confidence(
                overall: overallConfidence ?? result.confidence.overall,
                portion: result.confidence.portion,
                nutrients: nutrientConfidence ?? result.confidence.nutrients
            ),
            assumptionKeys: result.assumptionKeys,
            assessment: Assessment(
                score: score,
                tier: tier,
                statuses: statuses ?? result.assessment.statuses,
                suggestionKeys: suggestionKeys ?? defaultSuggestionKeys,
                scoringReasons: scoringReasons ?? defaultScoringReasons,
                insufficientData: insufficientData
            )
        )
    }
}

private extension ResultPresentation {
    func metric(_ kind: NutritionMetricKind) -> NutritionMetricPresentation? {
        metrics.first { $0.kind == kind }
    }
}
