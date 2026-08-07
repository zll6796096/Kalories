import Foundation
import XCTest
@testable import Kalories

final class AnalysisContractTests: XCTestCase {
    private typealias JSONObject = [String: Any]
    private typealias Mutation = (inout JSONObject) -> Void

    func testDecodesCanonicalAnalysisFixture() throws {
        let result = try StrictAnalysisDecoder().decode(canonicalData())

        XCTAssertTrue(result.foodDetected)
        XCTAssertEqual(result.foodNames?.ja, "焼き鮭定食")
        XCTAssertEqual(result.assessment.score, 64)
        XCTAssertEqual(result.assessment.tier, .mostlyBalanced)
        XCTAssertEqual(result.assessment.suggestionKeys, [.reduceSauce, .adjustStaple])
        XCTAssertEqual(result.nutrients.sodiumMg, 980)
    }

    func testNutrientSubscriptsCoverEveryKey() throws {
        let result = try StrictAnalysisDecoder().decode(canonicalData())
        let expectedValues: [NutrientKey: Double] = [
            .caloriesKcal: 640,
            .proteinG: 34,
            .carbsG: 68,
            .fatG: 24,
            .fiberG: 8.4,
            .sugarG: 12,
            .sodiumMg: 980,
        ]
        let expectedStatuses: [NutrientKey: NutrientStatus] = [
            .caloriesKcal: .appropriate,
            .proteinG: .high,
            .carbsG: .low,
            .fatG: .high,
            .fiberG: .appropriate,
            .sugarG: .appropriate,
            .sodiumMg: .high,
        ]

        XCTAssertEqual(Set(NutrientKey.allCases), Set(expectedValues.keys))
        for key in NutrientKey.allCases {
            XCTAssertEqual(result.nutrients[key], expectedValues[key])
            XCTAssertEqual(result.assessment.statuses[key], expectedStatuses[key])
        }
    }

    func testRejectsNonObjectTopLevelJSON() throws {
        for data in [Data("[]".utf8), Data("null".utf8), Data("true".utf8)] {
            assertDecodeFails(data, as: .notJSONObject)
        }
    }

    func testRejectsMissingOrExtraKeysAtEveryObjectLevel() throws {
        let objectPaths = [
            [],
            ["food_names"],
            ["nutrients"],
            ["confidence"],
            ["confidence", "nutrients"],
            ["assessment"],
            ["assessment", "statuses"],
        ]

        for path in objectPaths {
            assertMutationFails(as: .unexpectedKeys) { root in
                self.mutateObject(&root, at: path) { $0["unexpected"] = true }
            }
            assertMutationFails(as: .unexpectedKeys) { root in
                self.mutateObject(&root, at: path) { object in
                    object.removeValue(forKey: object.keys.sorted().first!)
                }
            }
        }
    }

    func testRejectsMalformedObjectTypesAndJSON() throws {
        assertMutationFails(as: .invalidValue) { $0["nutrients"] = [] }
        assertMutationFails(as: .invalidValue) { root in
            self.mutateObject(&root, at: ["confidence"]) { $0["nutrients"] = "high" }
        }
        assertMutationFails(as: .invalidValue) { root in
            self.mutateObject(&root, at: ["assessment"]) { $0["statuses"] = NSNull() }
        }
        assertDecodeFails(Data("{not-json".utf8), as: .invalidValue)
    }

    func testRejectsInvalidScalarTypesAndEnumValues() throws {
        let mutations: [Mutation] = [
            { $0["food_detected"] = "true" },
            { $0["portion_grams"] = true },
            { root in self.mutateObject(&root, at: ["nutrients"]) { $0["fat_g"] = "24" } },
            { root in self.mutateObject(&root, at: ["confidence"]) { $0["overall"] = "certain" } },
            { root in self.mutateObject(&root, at: ["confidence", "nutrients"]) { $0["fat_g"] = "certain" } },
            { $0["assumption_keys"] = ["untrusted"] },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["score"] = 64.5 } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["tier"] = "excellent" } },
            { root in self.mutateObject(&root, at: ["assessment", "statuses"]) { $0["fiber_g"] = "unknown" } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["suggestion_keys"] = ["eat_anything"] } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["scoring_reasons"] = ["mystery"] } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["insufficient_data"] = 0 } },
        ]

        for mutation in mutations {
            assertMutationFails(as: .invalidValue, mutation)
        }
    }

    func testRejectsOutOfRangeAndNonFiniteNumbers() throws {
        let mutations: [Mutation] = [
            { $0["portion_grams"] = -1 },
            { $0["portion_grams"] = 10_001 },
            { root in self.mutateObject(&root, at: ["nutrients"]) { $0["calories_kcal"] = -1 } },
            { root in self.mutateObject(&root, at: ["nutrients"]) { $0["calories_kcal"] = 10_001 } },
            { root in self.mutateObject(&root, at: ["nutrients"]) { $0["sodium_mg"] = -1 } },
            { root in self.mutateObject(&root, at: ["nutrients"]) { $0["sodium_mg"] = 100_001 } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["score"] = -1 } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["score"] = 101 } },
        ]

        for mutation in mutations {
            assertMutationFails(as: .invalidValue, mutation)
        }

        for nutrient in NutrientKey.allCases where nutrient != .caloriesKcal && nutrient != .sodiumMg {
            assertMutationFails(as: .invalidValue) { root in
                self.mutateObject(&root, at: ["nutrients"]) { $0[nutrient.rawValue] = -1 }
            }
            assertMutationFails(as: .invalidValue) { root in
                self.mutateObject(&root, at: ["nutrients"]) { $0[nutrient.rawValue] = 2_001 }
            }
        }

        if NutrientKey.allCases.filter({ $0 != .caloriesKcal && $0 != .sodiumMg }).isEmpty {
            XCTFail("Expected gram nutrient keys")
        }
        assertDecodeFails(
            replacing("\"fat_g\": 24", with: "\"fat_g\": 1e400"),
            as: .invalidValue
        )
    }

    func testRejectsUnnormalizedFoodNames() throws {
        let tooManyUnicodeCodePoints = String(repeating: "👨‍👩‍👧‍👦", count: 18)
        for invalidName in [
            "",
            " ",
            " leading",
            "trailing ",
            String(repeating: "x", count: 121),
            tooManyUnicodeCodePoints,
        ] {
            assertMutationFails(as: .invalidValue) { root in
                self.mutateObject(&root, at: ["food_names"]) { $0["en"] = invalidName }
            }
        }
    }

    func testRejectsDuplicateOrOversizedKnownLists() throws {
        let mutations: [Mutation] = [
            { $0["assumption_keys"] = ["visible_portion_only", "visible_portion_only"] },
            {
                $0["assumption_keys"] = [
                    "visible_portion_only",
                    "portion_estimated",
                    "seasoning_estimated",
                    "hidden_ingredients_possible",
                    "visible_portion_only",
                ]
            },
            { root in
                self.mutateObject(&root, at: ["assessment"]) {
                    $0["suggestion_keys"] = ["reduce_sauce", "reduce_sauce"]
                }
            },
            { root in
                self.mutateObject(&root, at: ["assessment"]) {
                    $0["suggestion_keys"] = ["reduce_sauce", "adjust_staple", "reduce_fat"]
                }
            },
            { root in
                self.mutateObject(&root, at: ["assessment"]) {
                    $0["scoring_reasons"] = ["sodium_high", "sodium_high"]
                }
            },
            { root in
                self.mutateObject(&root, at: ["assessment"]) {
                    $0["scoring_reasons"] = [
                        "calories_low", "calories_high", "protein_g_low", "protein_g_high",
                        "carbs_g_low", "carbs_g_high", "fat_g_low", "fat_g_high",
                    ]
                }
            },
        ]

        for mutation in mutations {
            assertMutationFails(as: .invalidValue, mutation)
        }
    }

    func testAcceptsNormalizedNoFoodResponse() throws {
        let result = try StrictAnalysisDecoder().decode(data(from: normalizedNoFoodObject()))

        XCTAssertFalse(result.foodDetected)
        XCTAssertNil(result.foodNames)
        XCTAssertNil(result.nutrients.sodiumMg)
        XCTAssertEqual(result.assessment.tier, .indeterminate)
        XCTAssertTrue(result.assessment.insufficientData)
    }

    func testRejectsEveryContradictionInNormalizedNoFoodResponse() throws {
        let mutations: [Mutation] = [
            { $0["food_names"] = self.canonicalObject()["food_names"]! },
            { $0["portion_grams"] = 1 },
            { root in self.mutateObject(&root, at: ["nutrients"]) { $0["fiber_g"] = 1 } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["score"] = 0 } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["tier"] = "balanced" } },
            { root in self.mutateObject(&root, at: ["assessment", "statuses"]) { $0["sodium_mg"] = "appropriate" } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["suggestion_keys"] = ["reduce_sauce"] } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["scoring_reasons"] = ["sodium_high"] } },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["insufficient_data"] = false } },
        ]

        for mutation in mutations {
            var object = normalizedNoFoodObject()
            mutation(&object)
            assertDecodeFails(data(from: object), as: .incoherentAssessment)
        }
    }

    func testRejectsStatusValueContradictions() throws {
        let mutations: [Mutation] = [
            { root in
                self.mutateObject(&root, at: ["nutrients"]) { $0["fiber_g"] = NSNull() }
                self.setIndeterminateAssessment(&root)
            },
            { root in
                self.mutateObject(&root, at: ["assessment", "statuses"]) { $0["fiber_g"] = "indeterminate" }
            },
            { root in
                self.mutateObject(&root, at: ["nutrients"]) { $0["fat_g"] = NSNull() }
                self.setIndeterminateAssessment(&root)
                self.mutateObject(&root, at: ["assessment", "statuses"]) { $0["fat_g"] = "indeterminate" }
            },
            { root in
                self.setAllMacros(&root, to: 0)
                self.setIndeterminateAssessment(&root)
            },
        ]

        for mutation in mutations {
            assertMutationFails(as: .incoherentAssessment, mutation)
        }
    }

    func testAcceptsCoherentIndeterminateFoodAssessments() throws {
        var missingMacro = canonicalObject()
        mutateObject(&missingMacro, at: ["nutrients"]) { $0["fat_g"] = NSNull() }
        setAllMacroStatuses(&missingMacro, to: "indeterminate")
        setIndeterminateAssessment(&missingMacro)

        var zeroMacroEnergy = canonicalObject()
        setAllMacros(&zeroMacroEnergy, to: 0)
        setAllMacroStatuses(&zeroMacroEnergy, to: "indeterminate")
        setIndeterminateAssessment(&zeroMacroEnergy)

        XCTAssertNoThrow(try StrictAnalysisDecoder().decode(data(from: missingMacro)))
        XCTAssertNoThrow(try StrictAnalysisDecoder().decode(data(from: zeroMacroEnergy)))
    }

    func testRejectsScoreAvailabilityContradictions() throws {
        let mutations: [Mutation] = [
            { root in self.mutateObject(&root, at: ["confidence"]) { $0["overall"] = "low" } },
            { root in
                self.mutateObject(&root, at: ["nutrients"]) { $0["calories_kcal"] = NSNull() }
                self.mutateObject(&root, at: ["assessment", "statuses"]) { $0["calories_kcal"] = "indeterminate" }
            },
            { root in
                self.mutateObject(&root, at: ["nutrients"]) { $0["fat_g"] = NSNull() }
                self.setAllMacroStatuses(&root, to: "indeterminate")
            },
            { root in
                self.setAllMacros(&root, to: 0)
                self.setAllMacroStatuses(&root, to: "indeterminate")
            },
            { root in self.setIndeterminateAssessment(&root) },
            { root in self.mutateObject(&root, at: ["assessment"]) { $0["insufficient_data"] = true } },
        ]

        for mutation in mutations {
            assertMutationFails(as: .incoherentAssessment, mutation)
        }
    }

    func testEnforcesScoreTierBoundaries() throws {
        let validTiers: [(Int, String)] = [
            (0, "needs_attention"),
            (59, "needs_attention"),
            (60, "mostly_balanced"),
            (79, "mostly_balanced"),
            (80, "balanced"),
            (99, "balanced"),
        ]
        for (score, tier) in validTiers {
            var object = canonicalObject()
            mutateObject(&object, at: ["assessment"]) {
                $0["score"] = score
                $0["tier"] = tier
            }
            XCTAssertNoThrow(try StrictAnalysisDecoder().decode(data(from: object)))
        }

        assertMutationFails(as: .incoherentAssessment) { root in
            self.mutateObject(&root, at: ["assessment"]) {
                $0["score"] = 79
                $0["tier"] = "balanced"
            }
        }
    }

    func testScoreOfOneHundredRequiresNoReasonsOrSuggestions() throws {
        assertMutationFails(as: .incoherentAssessment) { root in
            self.mutateObject(&root, at: ["assessment"]) {
                $0["score"] = 100
                $0["tier"] = "balanced"
            }
        }

        var coherent = canonicalObject()
        mutateObject(&coherent, at: ["assessment"]) {
            $0["score"] = 100
            $0["tier"] = "balanced"
            $0["suggestion_keys"] = []
            $0["scoring_reasons"] = []
        }
        XCTAssertNoThrow(try StrictAnalysisDecoder().decode(data(from: coherent)))
    }

    private func canonicalData() -> Data {
        let url = Bundle(for: Self.self).url(
            forResource: "canonical_analysis_result",
            withExtension: "json"
        )!
        return try! Data(contentsOf: url)
    }

    private func canonicalObject() -> JSONObject {
        try! JSONSerialization.jsonObject(with: canonicalData()) as! JSONObject
    }

    private func normalizedNoFoodObject() -> JSONObject {
        var object = canonicalObject()
        object["food_detected"] = false
        object["food_names"] = NSNull()
        object["portion_grams"] = NSNull()
        mutateObject(&object, at: ["nutrients"]) { nutrients in
            for key in nutrients.keys {
                nutrients[key] = NSNull()
            }
        }
        mutateObject(&object, at: ["assessment"]) {
            $0["score"] = NSNull()
            $0["tier"] = "indeterminate"
            $0["suggestion_keys"] = []
            $0["scoring_reasons"] = []
            $0["insufficient_data"] = true
        }
        mutateObject(&object, at: ["assessment", "statuses"]) { statuses in
            for key in statuses.keys {
                statuses[key] = "indeterminate"
            }
        }
        return object
    }

    private func assertMutationFails(
        as expected: AnalysisContractError,
        _ mutation: Mutation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var object = canonicalObject()
        mutation(&object)
        assertDecodeFails(data(from: object), as: expected, file: file, line: line)
    }

    private func assertDecodeFails(
        _ data: Data,
        as expected: AnalysisContractError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try StrictAnalysisDecoder().decode(data),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? AnalysisContractError, expected, file: file, line: line)
        }
    }

    private func data(from object: JSONObject) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func replacing(_ oldValue: String, with newValue: String) -> Data {
        let original = String(decoding: canonicalData(), as: UTF8.self)
        return Data(original.replacingOccurrences(of: oldValue, with: newValue).utf8)
    }

    private func mutateObject(
        _ object: inout JSONObject,
        at path: [String],
        mutation: (inout JSONObject) -> Void
    ) {
        guard let head = path.first else {
            mutation(&object)
            return
        }
        var child = object[head] as! JSONObject
        mutateObject(&child, at: Array(path.dropFirst()), mutation: mutation)
        object[head] = child
    }

    private func setIndeterminateAssessment(_ object: inout JSONObject) {
        mutateObject(&object, at: ["assessment"]) {
            $0["score"] = NSNull()
            $0["tier"] = "indeterminate"
            $0["insufficient_data"] = true
        }
    }

    private func setAllMacros(_ object: inout JSONObject, to value: Double) {
        mutateObject(&object, at: ["nutrients"]) {
            $0["protein_g"] = value
            $0["carbs_g"] = value
            $0["fat_g"] = value
        }
    }

    private func setAllMacroStatuses(_ object: inout JSONObject, to status: String) {
        mutateObject(&object, at: ["assessment", "statuses"]) {
            $0["protein_g"] = status
            $0["carbs_g"] = status
            $0["fat_g"] = status
        }
    }
}
