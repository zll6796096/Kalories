"""Behavioral tests for the deterministic nutrition assessment."""

import json
from pathlib import Path
import unittest

from api.analyze import AnalyzeResponse
from lib.nutrition import assess_nutrition

CANONICAL_FIXTURE_PATH = (
    Path(__file__).parent / "fixtures" / "canonical_analysis_result.json"
)


def high_confidence(*, nutrients=None, **overrides):
    confidence = {
        "overall": "high",
        "nutrients": {
            "calories_kcal": "high",
            "protein_g": "high",
            "carbs_g": "high",
            "fat_g": "high",
            "fiber_g": "high",
            "sugar_g": "high",
            "sodium_mg": "high",
        },
    }
    confidence.update(overrides)
    if nutrients:
        confidence["nutrients"].update(nutrients)
    return confidence


class AssessNutritionTests(unittest.TestCase):
    def test_canonical_salmon_fixture_matches_the_documented_contract(self):
        fixture = json.loads(CANONICAL_FIXTURE_PATH.read_text(encoding="utf-8"))
        validated_fixture = AnalyzeResponse.model_validate(fixture)

        self.assertEqual(fixture, validated_fixture.model_dump(mode="json"))

        result = assess_nutrition(fixture["nutrients"], fixture["confidence"])
        self.assertEqual(fixture["assessment"], result)

    def test_representative_meal_is_balanced_with_appropriate_macros(self):
        result = assess_nutrition(
            {
                "calories_kcal": 600,
                "protein_g": 25,
                "carbs_g": 82,
                "fat_g": 18,
                "fiber_g": 7,
                "sugar_g": 8,
                "sodium_mg": 500,
            },
            high_confidence(),
        )

        self.assertGreaterEqual(result["score"], 80)
        self.assertEqual("balanced", result["tier"])
        self.assertEqual("appropriate", result["statuses"]["protein_g"])
        self.assertEqual("appropriate", result["statuses"]["carbs_g"])
        self.assertEqual("appropriate", result["statuses"]["fat_g"])
        self.assertFalse(result["insufficient_data"])

    def test_derived_macro_energy_ratios_flag_low_protein_and_high_fat(self):
        result = assess_nutrition(
            {
                "calories_kcal": 600,
                "protein_g": 10,
                "carbs_g": 20,
                "fat_g": 40,
                "fiber_g": 6,
                "sugar_g": 9,
                "sodium_mg": 600,
            },
            high_confidence(),
        )

        self.assertEqual("low", result["statuses"]["protein_g"])
        self.assertEqual("high", result["statuses"]["fat_g"])
        self.assertLess(result["score"], 80)

    def test_zero_derived_macro_energy_makes_the_score_indeterminate(self):
        result = assess_nutrition(
            self._meal(protein_g=0, carbs_g=0, fat_g=0), high_confidence()
        )

        self.assertIsNone(result["score"])
        self.assertEqual("indeterminate", result["tier"])
        self.assertTrue(result["insufficient_data"])

    def test_partial_zero_macros_with_positive_energy_remain_computable(self):
        result = assess_nutrition(
            self._meal(protein_g=0, carbs_g=50, fat_g=10), high_confidence()
        )

        self.assertIsNotNone(result["score"])
        self.assertFalse(result["insufficient_data"])
        self.assertEqual("low", result["statuses"]["protein_g"])
        self.assertEqual("high", result["statuses"]["carbs_g"])
        self.assertEqual("high", result["statuses"]["fat_g"])

    def test_missing_any_macro_suppresses_score_even_when_partial_values_look_balanced(self):
        result = assess_nutrition(
            self._meal(protein_g=25, carbs_g=82, fat_g=None),
            high_confidence(),
        )

        self.assertIsNone(result["score"])
        self.assertEqual("indeterminate", result["tier"])
        self.assertTrue(result["insufficient_data"])
        self.assertEqual("appropriate", result["statuses"]["calories_kcal"])

    def test_extreme_partial_macros_cannot_produce_a_false_perfect_score(self):
        result = assess_nutrition(
            self._meal(
                protein_g=0,
                carbs_g=1,
                fat_g=None,
                fiber_g=7,
                sugar_g=8,
                sodium_mg=500,
            ),
            high_confidence(),
        )

        self.assertIsNone(result["score"])
        self.assertEqual("indeterminate", result["tier"])
        self.assertTrue(result["insufficient_data"])
        self.assertTrue(
            all(
                result["statuses"][field] == "indeterminate"
                for field in ("protein_g", "carbs_g", "fat_g")
            )
        )

    def test_fiber_thresholds_and_penalties(self):
        appropriate = assess_nutrition(self._meal(fiber_g=6), high_confidence())
        moderate = assess_nutrition(self._meal(fiber_g=3), high_confidence())
        low = assess_nutrition(self._meal(fiber_g=2), high_confidence())

        self.assertEqual("appropriate", appropriate["statuses"]["fiber_g"])
        self.assertEqual("low", moderate["statuses"]["fiber_g"])
        self.assertEqual(appropriate["score"] - 5, moderate["score"])
        self.assertEqual("low", low["statuses"]["fiber_g"])
        self.assertEqual(appropriate["score"] - 10, low["score"])
        self.assertIn("add_vegetables", low["suggestion_keys"])

    def test_sodium_bands_have_defined_penalties_reasons_and_advice(self):
        baseline = assess_nutrition(self._meal(sodium_mg=667), high_confidence())
        elevated = assess_nutrition(self._meal(sodium_mg=668), high_confidence())
        high = assess_nutrition(self._meal(sodium_mg=851), high_confidence())

        self.assertEqual("appropriate", baseline["statuses"]["sodium_mg"])
        self.assertEqual("high", elevated["statuses"]["sodium_mg"])
        self.assertEqual(baseline["score"] - 6, elevated["score"])
        self.assertIn("sodium_elevated", elevated["scoring_reasons"])
        self.assertEqual(baseline["score"] - 12, high["score"])
        self.assertIn("sodium_high", high["scoring_reasons"])
        self.assertIn("reduce_sauce", high["suggestion_keys"])

    def test_sugar_thresholds_and_confidence_gated_penalty(self):
        low = assess_nutrition(self._meal(sugar_g=8), high_confidence())
        appropriate = assess_nutrition(self._meal(sugar_g=9), high_confidence())
        high = assess_nutrition(self._meal(sugar_g=18), high_confidence())
        uncertain_high = assess_nutrition(
            self._meal(sugar_g=18), high_confidence(nutrients={"sugar_g": "low"})
        )

        self.assertEqual("low", low["statuses"]["sugar_g"])
        self.assertEqual("appropriate", appropriate["statuses"]["sugar_g"])
        self.assertEqual("high", high["statuses"]["sugar_g"])
        self.assertEqual(appropriate["score"] - 6, high["score"])
        self.assertIn("reduce_sweet_items", high["suggestion_keys"])
        self.assertEqual(appropriate["score"], uncertain_high["score"])
        self.assertNotIn("reduce_sweet_items", uncertain_high["suggestion_keys"])

    def test_nested_sugar_confidence_controls_sugar_penalty_reason_and_advice(self):
        high = assess_nutrition(self._meal(sugar_g=25), high_confidence())
        low = assess_nutrition(
            self._meal(sugar_g=25), high_confidence(nutrients={"sugar_g": "low"})
        )

        self.assertEqual(low["score"] - 6, high["score"])
        self.assertIn("sugar_high", high["scoring_reasons"])
        self.assertIn("reduce_sweet_items", high["suggestion_keys"])
        self.assertNotIn("sugar_high", low["scoring_reasons"])
        self.assertNotIn("reduce_sweet_items", low["suggestion_keys"])

    def test_missing_null_and_invalid_values_are_indeterminate_not_zero(self):
        result = assess_nutrition(
            {
                "calories_kcal": None,
                "protein_g": True,
                "carbs_g": -1,
                "fat_g": "18",
                "fiber_g": None,
                "sugar_g": None,
                "sodium_mg": None,
            },
            high_confidence(),
        )

        self.assertTrue(all(status == "indeterminate" for status in result["statuses"].values()))
        self.assertIsNone(result["score"])
        self.assertTrue(result["insufficient_data"])

    def test_huge_nonfinite_and_nan_numbers_are_unavailable(self):
        cases = (10**10000, float("nan"), float("inf"), float("-inf"))
        for value in cases:
            with self.subTest(kind=type(value).__name__):
                result = assess_nutrition(
                    self._meal(calories_kcal=value), high_confidence()
                )
                self.assertEqual("indeterminate", result["statuses"]["calories_kcal"])
                self.assertIsNone(result["score"])
                self.assertTrue(result["insufficient_data"])

    def test_score_requires_calories_all_macros_and_reliable_overall_confidence(self):
        missing_macro = assess_nutrition(self._meal(fat_g=None), high_confidence())
        low_overall = assess_nutrition(self._meal(), high_confidence(overall="low"))

        for result in (missing_macro, low_overall):
            self.assertIsNone(result["score"])
            self.assertEqual("indeterminate", result["tier"])
            self.assertTrue(result["insufficient_data"])

    def test_all_three_macros_keep_statuses_and_penalties_coherent(self):
        balanced = assess_nutrition(self._meal(), high_confidence())
        extreme = assess_nutrition(
            self._meal(protein_g=2, carbs_g=10, fat_g=50),
            high_confidence(),
        )

        self.assertIsNotNone(balanced["score"])
        self.assertFalse(balanced["insufficient_data"])
        self.assertTrue(
            all(
                balanced["statuses"][field] != "indeterminate"
                for field in ("protein_g", "carbs_g", "fat_g")
            )
        )
        self.assertIsNotNone(extreme["score"])
        self.assertLess(extreme["score"], balanced["score"])
        self.assertEqual("low", extreme["statuses"]["protein_g"])
        self.assertEqual("high", extreme["statuses"]["fat_g"])

    def test_insufficient_data_preserves_available_reasons_and_suggestions(self):
        result = assess_nutrition(
            self._meal(fiber_g=2, sodium_mg=851), high_confidence(overall="low")
        )

        self.assertIsNone(result["score"])
        self.assertEqual("indeterminate", result["tier"])
        self.assertTrue(result["insufficient_data"])
        self.assertEqual("low", result["statuses"]["fiber_g"])
        self.assertEqual("high", result["statuses"]["sodium_mg"])
        self.assertEqual(["fiber_low", "sodium_high"], result["scoring_reasons"])
        self.assertEqual(["reduce_sauce", "add_vegetables"], result["suggestion_keys"])

    def test_invalid_confidence_values_are_treated_as_low(self):
        result = assess_nutrition(self._meal(), high_confidence(overall={"bad": "value"}))

        self.assertIsNone(result["score"])
        self.assertTrue(result["insufficient_data"])

    def test_calorie_bands_apply_expected_statuses_and_penalties(self):
        baseline = assess_nutrition(self._meal(calories_kcal=450), high_confidence())
        low = assess_nutrition(self._meal(calories_kcal=449), high_confidence())
        very_low = assess_nutrition(self._meal(calories_kcal=299), high_confidence())
        high = assess_nutrition(self._meal(calories_kcal=851), high_confidence())
        very_high = assess_nutrition(self._meal(calories_kcal=1001), high_confidence())

        self.assertEqual("appropriate", baseline["statuses"]["calories_kcal"])
        self.assertEqual("low", low["statuses"]["calories_kcal"])
        self.assertEqual(baseline["score"] - 4, low["score"])
        self.assertEqual(baseline["score"] - 8, very_low["score"])
        self.assertEqual("high", high["statuses"]["calories_kcal"])
        self.assertEqual(baseline["score"] - 4, high["score"])
        self.assertEqual(baseline["score"] - 8, very_high["score"])

    def test_calorie_exact_boundaries_and_adjacent_penalties(self):
        cases = (
            (299, "low", 8),
            (300, "low", 4),
            (449, "low", 4),
            (450, "appropriate", 0),
            (850, "appropriate", 0),
            (851, "high", 4),
            (1000, "high", 4),
            (1001, "high", 8),
        )
        for calories, status, penalty in cases:
            with self.subTest(calories=calories):
                result = assess_nutrition(
                    self._meal(calories_kcal=calories), high_confidence()
                )
                self.assertEqual(status, result["statuses"]["calories_kcal"])
                self.assertEqual(100 - penalty, result["score"])
                self.assertEqual("balanced", result["tier"])

    def test_fiber_exact_boundaries_and_adjacent_penalties(self):
        cases = (
            (2.999, "low", 10),
            (3, "low", 5),
            (5.999, "low", 5),
            (6, "appropriate", 0),
        )
        for fiber, status, penalty in cases:
            with self.subTest(fiber=fiber):
                result = assess_nutrition(self._meal(fiber_g=fiber), high_confidence())
                self.assertEqual(status, result["statuses"]["fiber_g"])
                self.assertEqual(100 - penalty, result["score"])
                self.assertEqual("balanced", result["tier"])

    def test_sodium_exact_boundaries_and_penalties(self):
        cases = (
            (667, "appropriate", 0, None),
            (668, "high", 6, "sodium_elevated"),
            (850, "high", 6, "sodium_elevated"),
            (851, "high", 12, "sodium_high"),
        )
        for sodium, status, penalty, reason in cases:
            with self.subTest(sodium=sodium):
                result = assess_nutrition(self._meal(sodium_mg=sodium), high_confidence())
                self.assertEqual(status, result["statuses"]["sodium_mg"])
                self.assertEqual(100 - penalty, result["score"])
                if reason:
                    self.assertIn(reason, result["scoring_reasons"])

    def test_sugar_exact_boundaries_and_nested_confidence_penalties(self):
        cases = (
            (8, "low", 0),
            (8.001, "appropriate", 0),
            (17, "appropriate", 0),
            (17.001, "high", 6),
        )
        for sugar, status, penalty in cases:
            with self.subTest(sugar=sugar):
                result = assess_nutrition(self._meal(sugar_g=sugar), high_confidence())
                self.assertEqual(status, result["statuses"]["sugar_g"])
                self.assertEqual(100 - penalty, result["score"])
                if penalty:
                    self.assertIn("sugar_high", result["scoring_reasons"])
                    self.assertIn("reduce_sweet_items", result["suggestion_keys"])

    def test_every_macro_range_edge_is_appropriate_without_a_penalty(self):
        cases = (
            ("protein_g", 13, 25, 62),
            ("protein_g", 20, 25, 55),
            ("fat_g", 15, 20, 65),
            ("fat_g", 15, 30, 55),
            ("carbs_g", 20, 30, 50),
            ("carbs_g", 15, 20, 65),
        )
        for field, protein, fat, carbs in cases:
            with self.subTest(field=field, protein=protein, fat=fat, carbs=carbs):
                result = assess_nutrition(
                    self._meal_for_macro_percentages(protein, fat, carbs),
                    high_confidence(),
                )
                self.assertEqual("appropriate", result["statuses"][field])
                self.assertEqual(100, result["score"])
                self.assertEqual("balanced", result["tier"])

    def test_macro_exact_five_point_deviation_costs_six_and_more_costs_twelve(self):
        cases = (
            ("protein_g", self._meal_for_macro_percentages(8, 30, 62), 6),
            ("protein_g", self._meal_for_macro_percentages(7.999, 30, 62.001), 12),
            ("fat_g", self._meal_for_macro_percentages(14.999, 35, 50.001), 6),
            ("fat_g", self._meal_for_macro_percentages(14.999, 35.001, 50), 12),
        )
        for field, meal, penalty in cases:
            with self.subTest(field=field, penalty=penalty):
                result = assess_nutrition(meal, high_confidence())
                self.assertIn(result["statuses"][field], {"low", "high"})
                self.assertEqual(100 - penalty, result["score"])

    def test_score_and_tier_boundaries_are_inclusive(self):
        balanced = assess_nutrition(
            self._meal(calories_kcal=1001, sodium_mg=851), high_confidence()
        )
        mostly_balanced = assess_nutrition(
            self._meal_for_macro_percentages(7, 30, 63, fiber_g=2, sugar_g=18, sodium_mg=851),
            high_confidence(),
        )
        below_balanced = assess_nutrition(
            self._meal_for_macro_percentages(7, 30, 63, calories_kcal=449, fiber_g=3),
            high_confidence(),
        )
        needs_attention = assess_nutrition(
            self._meal_for_macro_percentages(
                8, 30, 62, calories_kcal=1001, fiber_g=2, sugar_g=18, sodium_mg=851
            ),
            high_confidence(),
        )

        self.assertEqual((80, "balanced"), (balanced["score"], balanced["tier"]))
        self.assertEqual((60, "mostly_balanced"), (mostly_balanced["score"], mostly_balanced["tier"]))
        self.assertEqual((79, "mostly_balanced"), (below_balanced["score"], below_balanced["tier"]))
        self.assertEqual((58, "needs_attention"), (needs_attention["score"], needs_attention["tier"]))

    def test_extreme_input_results_are_deterministic_and_bounded(self):
        meal = self._meal(
            calories_kcal=2000,
            protein_g=0,
            carbs_g=0,
            fat_g=100,
            fiber_g=0,
            sugar_g=100,
            sodium_mg=2000,
        )

        first = assess_nutrition(meal, high_confidence())
        second = assess_nutrition(meal, high_confidence())

        self.assertEqual(first, second)
        self.assertGreaterEqual(first["score"], 0)
        self.assertLessEqual(first["score"], 100)

    def test_suggestions_are_deduplicated_deterministic_and_limited_to_two(self):
        meal = self._meal(
            calories_kcal=1001,
            protein_g=5,
            carbs_g=20,
            fat_g=50,
            fiber_g=2,
            sugar_g=20,
            sodium_mg=900,
        )

        result = assess_nutrition(meal, high_confidence())

        self.assertEqual(["reduce_sauce", "reduce_fat"], result["suggestion_keys"])
        self.assertEqual(len(result["suggestion_keys"]), len(set(result["suggestion_keys"])))

    def test_largest_actionable_deviations_outrank_milder_findings(self):
        result = assess_nutrition(
            self._meal_for_macro_percentages(15, 40, 45, fiber_g=3, sodium_mg=668),
            high_confidence(),
        )

        self.assertEqual("high", result["statuses"]["fat_g"])
        self.assertEqual("low", result["statuses"]["fiber_g"])
        self.assertEqual("high", result["statuses"]["sodium_mg"])
        self.assertEqual(["reduce_fat", "reduce_sauce"], result["suggestion_keys"])

    @staticmethod
    def _meal(**overrides):
        meal = {
            "calories_kcal": 600,
            "protein_g": 25,
            "carbs_g": 82,
            "fat_g": 18,
            "fiber_g": 7,
            "sugar_g": 9,
            "sodium_mg": 500,
        }
        meal.update(overrides)
        return meal

    @classmethod
    def _meal_for_macro_percentages(cls, protein, fat, carbs, **overrides):
        if protein + fat + carbs != 100:
            raise ValueError("Macro energy percentages must total 100")
        return cls._meal(
            protein_g=protein / 4,
            fat_g=fat / 9,
            carbs_g=carbs / 4,
            **overrides,
        )


if __name__ == "__main__":
    unittest.main()
