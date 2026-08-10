import Foundation

enum ConfidenceLevel: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

enum NutrientStatus: String, Codable, CaseIterable, Sendable {
    case low
    case appropriate
    case high
    case indeterminate
}

enum AssessmentTier: String, Codable, CaseIterable, Sendable {
    case balanced
    case mostlyBalanced = "mostly_balanced"
    case needsAttention = "needs_attention"
    case indeterminate
}

enum AssumptionKey: String, Codable, CaseIterable, Sendable {
    case visiblePortionOnly = "visible_portion_only"
    case portionEstimated = "portion_estimated"
    case seasoningEstimated = "seasoning_estimated"
    case hiddenIngredientsPossible = "hidden_ingredients_possible"
}

enum SuggestionKey: String, Codable, CaseIterable, Sendable {
    case addVegetables = "add_vegetables"
    case reduceSauce = "reduce_sauce"
    case reduceSweetItems = "reduce_sweet_items"
    case reduceFat = "reduce_fat"
    case addProtein = "add_protein"
    case adjustStaple = "adjust_staple"
    case reducePortion = "reduce_portion"
}

enum ScoringReason: String, Codable, CaseIterable, Sendable {
    case caloriesLow = "calories_low"
    case caloriesHigh = "calories_high"
    case proteinLow = "protein_g_low"
    case proteinHigh = "protein_g_high"
    case carbsLow = "carbs_g_low"
    case carbsHigh = "carbs_g_high"
    case fatLow = "fat_g_low"
    case fatHigh = "fat_g_high"
    case fiberLow = "fiber_low"
    case sugarHigh = "sugar_high"
    case sodiumElevated = "sodium_elevated"
    case sodiumHigh = "sodium_high"
}

enum NutrientKey: String, Codable, CaseIterable, Sendable {
    case caloriesKcal = "calories_kcal"
    case proteinG = "protein_g"
    case carbsG = "carbs_g"
    case fatG = "fat_g"
    case fiberG = "fiber_g"
    case sugarG = "sugar_g"
    case sodiumMg = "sodium_mg"
}

struct FoodNames: Codable, Equatable, Sendable {
    let zh: String
    let ja: String
    let en: String
}

struct NutrientValues: Codable, Equatable, Sendable {
    let caloriesKcal: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    let sugarG: Double?
    let sodiumMg: Double?

    subscript(key: NutrientKey) -> Double? {
        switch key {
        case .caloriesKcal: caloriesKcal
        case .proteinG: proteinG
        case .carbsG: carbsG
        case .fatG: fatG
        case .fiberG: fiberG
        case .sugarG: sugarG
        case .sodiumMg: sodiumMg
        }
    }

    enum CodingKeys: String, CodingKey {
        case caloriesKcal = "calories_kcal"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case sodiumMg = "sodium_mg"
    }
}

struct NutrientConfidence: Codable, Equatable, Sendable {
    let caloriesKcal: ConfidenceLevel
    let proteinG: ConfidenceLevel
    let carbsG: ConfidenceLevel
    let fatG: ConfidenceLevel
    let fiberG: ConfidenceLevel
    let sugarG: ConfidenceLevel
    let sodiumMg: ConfidenceLevel

    enum CodingKeys: String, CodingKey {
        case caloriesKcal = "calories_kcal"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case sodiumMg = "sodium_mg"
    }
}

struct Confidence: Codable, Equatable, Sendable {
    let overall: ConfidenceLevel
    let portion: ConfidenceLevel
    let nutrients: NutrientConfidence
}

struct NutrientStatuses: Codable, Equatable, Sendable {
    let caloriesKcal: NutrientStatus
    let proteinG: NutrientStatus
    let carbsG: NutrientStatus
    let fatG: NutrientStatus
    let fiberG: NutrientStatus
    let sugarG: NutrientStatus
    let sodiumMg: NutrientStatus

    subscript(key: NutrientKey) -> NutrientStatus {
        switch key {
        case .caloriesKcal: caloriesKcal
        case .proteinG: proteinG
        case .carbsG: carbsG
        case .fatG: fatG
        case .fiberG: fiberG
        case .sugarG: sugarG
        case .sodiumMg: sodiumMg
        }
    }

    enum CodingKeys: String, CodingKey {
        case caloriesKcal = "calories_kcal"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case sodiumMg = "sodium_mg"
    }
}

struct Assessment: Codable, Equatable, Sendable {
    let score: Int?
    let tier: AssessmentTier
    let statuses: NutrientStatuses
    let suggestionKeys: [SuggestionKey]
    let scoringReasons: [ScoringReason]
    let insufficientData: Bool

    enum CodingKeys: String, CodingKey {
        case score
        case tier
        case statuses
        case suggestionKeys = "suggestion_keys"
        case scoringReasons = "scoring_reasons"
        case insufficientData = "insufficient_data"
    }
}

struct AnalysisResult: Codable, Equatable, Sendable {
    let foodDetected: Bool
    let foodNames: FoodNames?
    let portionGrams: Double?
    let nutrients: NutrientValues
    let confidence: Confidence
    let assumptionKeys: [AssumptionKey]
    let assessment: Assessment

    enum CodingKeys: String, CodingKey {
        case foodDetected = "food_detected"
        case foodNames = "food_names"
        case portionGrams = "portion_grams"
        case nutrients
        case confidence
        case assumptionKeys = "assumption_keys"
        case assessment
    }
}
