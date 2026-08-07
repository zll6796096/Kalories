import Foundation

enum AnalysisContractError: Error, Equatable {
    case notJSONObject
    case unexpectedKeys
    case invalidValue
    case incoherentAssessment
}

struct StrictAnalysisDecoder: Sendable {
    private typealias JSONObject = [String: Any]

    private static let rootKeys: Set<String> = [
        "food_detected",
        "food_names",
        "portion_grams",
        "nutrients",
        "confidence",
        "assumption_keys",
        "assessment",
    ]
    private static let foodNameKeys: Set<String> = ["zh", "ja", "en"]
    private static let nutrientKeys = Set(NutrientKey.allCases.map(\.rawValue))
    private static let confidenceKeys: Set<String> = ["overall", "portion", "nutrients"]
    private static let assessmentKeys: Set<String> = [
        "score",
        "tier",
        "statuses",
        "suggestion_keys",
        "scoring_reasons",
        "insufficient_data",
    ]
    private static let gramNutrientKeys: [NutrientKey] = [
        .proteinG,
        .carbsG,
        .fatG,
        .fiberG,
        .sugarG,
    ]
    private static let macroKeys: [NutrientKey] = [.proteinG, .carbsG, .fatG]
    private static let directStatusKeys: [NutrientKey] = [
        .caloriesKcal,
        .fiberG,
        .sugarG,
        .sodiumMg,
    ]

    func decode(_ data: Data) throws -> AnalysisResult {
        let serialized: Any
        do {
            serialized = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw AnalysisContractError.invalidValue
        }

        guard let root = serialized as? JSONObject else {
            throw AnalysisContractError.notJSONObject
        }
        try Self.validateObjectKeys(root)

        let result: AnalysisResult
        do {
            result = try JSONDecoder().decode(AnalysisResult.self, from: data)
        } catch {
            throw AnalysisContractError.invalidValue
        }

        try Self.validateValues(result)
        try Self.validateCoherence(result)
        return result
    }

    private static func validateObjectKeys(_ root: JSONObject) throws {
        try requireExactKeys(root, expected: rootKeys)

        if !(root["food_names"] is NSNull) {
            let foodNames = try requireObject(root["food_names"])
            try requireExactKeys(foodNames, expected: foodNameKeys)
        }

        let nutrients = try requireObject(root["nutrients"])
        try requireExactKeys(nutrients, expected: nutrientKeys)

        let confidence = try requireObject(root["confidence"])
        try requireExactKeys(confidence, expected: confidenceKeys)
        let nutrientConfidence = try requireObject(confidence["nutrients"])
        try requireExactKeys(nutrientConfidence, expected: nutrientKeys)

        let assessment = try requireObject(root["assessment"])
        try requireExactKeys(assessment, expected: assessmentKeys)
        let statuses = try requireObject(assessment["statuses"])
        try requireExactKeys(statuses, expected: nutrientKeys)
    }

    private static func requireObject(_ value: Any?) throws -> JSONObject {
        guard let object = value as? JSONObject else {
            throw AnalysisContractError.invalidValue
        }
        return object
    }

    private static func requireExactKeys(
        _ object: JSONObject,
        expected: Set<String>
    ) throws {
        guard Set(object.keys) == expected else {
            throw AnalysisContractError.unexpectedKeys
        }
    }

    private static func validateValues(_ result: AnalysisResult) throws {
        try requireBounded(result.portionGrams, maximum: 10_000)
        try requireBounded(result.nutrients.caloriesKcal, maximum: 10_000)
        for key in gramNutrientKeys {
            try requireBounded(result.nutrients[key], maximum: 2_000)
        }
        try requireBounded(result.nutrients.sodiumMg, maximum: 100_000)

        if let foodNames = result.foodNames {
            try requireNormalizedName(foodNames.zh)
            try requireNormalizedName(foodNames.ja)
            try requireNormalizedName(foodNames.en)
        }

        guard uniqueCount(result.assumptionKeys) == result.assumptionKeys.count,
              result.assumptionKeys.count <= 4,
              uniqueCount(result.assessment.suggestionKeys) == result.assessment.suggestionKeys.count,
              result.assessment.suggestionKeys.count <= 2,
              uniqueCount(result.assessment.scoringReasons) == result.assessment.scoringReasons.count,
              result.assessment.scoringReasons.count <= 7
        else {
            throw AnalysisContractError.invalidValue
        }

        if let score = result.assessment.score,
           !(0 ... 100).contains(score) {
            throw AnalysisContractError.invalidValue
        }
    }

    private static func requireBounded(_ value: Double?, maximum: Double) throws {
        guard let value else { return }
        guard value.isFinite, value >= 0, value <= maximum else {
            throw AnalysisContractError.invalidValue
        }
    }

    private static func requireNormalizedName(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == trimmed, (1 ... 120).contains(value.unicodeScalars.count) else {
            throw AnalysisContractError.invalidValue
        }
    }

    private static func uniqueCount<Value: Hashable>(_ values: [Value]) -> Int {
        Set(values).count
    }

    private static func validateCoherence(_ result: AnalysisResult) throws {
        if result.foodDetected {
            try validateFoodAnalysis(result)
        } else {
            try validateNoFoodAnalysis(result)
        }
    }

    private static func validateNoFoodAnalysis(_ result: AnalysisResult) throws {
        let normalized = result.foodNames == nil
            && result.portionGrams == nil
            && NutrientKey.allCases.allSatisfy { result.nutrients[$0] == nil }
            && result.assessment.score == nil
            && result.assessment.tier == .indeterminate
            && NutrientKey.allCases.allSatisfy { result.assessment.statuses[$0] == .indeterminate }
            && result.assessment.suggestionKeys.isEmpty
            && result.assessment.scoringReasons.isEmpty
            && result.assessment.insufficientData

        guard normalized else {
            throw AnalysisContractError.incoherentAssessment
        }
    }

    private static func validateFoodAnalysis(_ result: AnalysisResult) throws {
        guard result.foodNames != nil else {
            throw AnalysisContractError.incoherentAssessment
        }
        try validateStatusCoherence(result)

        let available = scoreIsAvailable(result)
        guard result.assessment.insufficientData == !available else {
            throw AnalysisContractError.incoherentAssessment
        }

        guard available else {
            guard result.assessment.score == nil,
                  result.assessment.tier == .indeterminate
            else {
                throw AnalysisContractError.incoherentAssessment
            }
            return
        }

        guard let score = result.assessment.score,
              result.assessment.tier == expectedTier(for: score)
        else {
            throw AnalysisContractError.incoherentAssessment
        }

        if score == 100,
           !(result.assessment.suggestionKeys.isEmpty && result.assessment.scoringReasons.isEmpty) {
            throw AnalysisContractError.incoherentAssessment
        }
    }

    private static func validateStatusCoherence(_ result: AnalysisResult) throws {
        for key in directStatusKeys {
            let valueIsMissing = result.nutrients[key] == nil
            let statusIsIndeterminate = result.assessment.statuses[key] == .indeterminate
            guard valueIsMissing == statusIsIndeterminate else {
                throw AnalysisContractError.incoherentAssessment
            }
        }

        let macrosAreDeterminate = macroValues(in: result).allSatisfy { $0 != nil }
            && macroEnergy(in: result) > 0
        for key in macroKeys {
            let statusIsDeterminate = result.assessment.statuses[key] != .indeterminate
            guard statusIsDeterminate == macrosAreDeterminate else {
                throw AnalysisContractError.incoherentAssessment
            }
        }
    }

    private static func scoreIsAvailable(_ result: AnalysisResult) -> Bool {
        result.nutrients.caloriesKcal != nil
            && macroValues(in: result).allSatisfy { $0 != nil }
            && macroEnergy(in: result) > 0
            && (result.confidence.overall == .medium || result.confidence.overall == .high)
    }

    private static func macroValues(in result: AnalysisResult) -> [Double?] {
        macroKeys.map { result.nutrients[$0] }
    }

    private static func macroEnergy(in result: AnalysisResult) -> Double {
        (result.nutrients.proteinG ?? 0) * 4
            + (result.nutrients.carbsG ?? 0) * 4
            + (result.nutrients.fatG ?? 0) * 9
    }

    private static func expectedTier(for score: Int) -> AssessmentTier {
        if score >= 80 {
            .balanced
        } else if score >= 60 {
            .mostlyBalanced
        } else {
            .needsAttention
        }
    }
}
