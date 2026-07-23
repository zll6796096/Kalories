"""Behavioral tests for the deterministic nutrition assessment."""

import unittest

from lib.nutrition import assess_nutrition


def high_confidence(**overrides):
    confidence = {
        "overall": "high",
        "calories_kcal": "high",
        "protein_g": "high",
        "carbs_g": "high",
        "fat_g": "high",
        "fiber_g": "high",
        "sugar_g": "high",
        "sodium_mg": "high",
    }
    confidence.update(overrides)
    return confidence


class AssessNutritionTests(unittest.TestCase):
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
            self._meal(sugar_g=18), high_confidence(sugar_g="low")
        )

        self.assertEqual("low", low["statuses"]["sugar_g"])
        self.assertEqual("appropriate", appropriate["statuses"]["sugar_g"])
        self.assertEqual("high", high["statuses"]["sugar_g"])
        self.assertEqual(appropriate["score"] - 6, high["score"])
        self.assertIn("reduce_sweet_items", high["suggestion_keys"])
        self.assertEqual(appropriate["score"], uncertain_high["score"])
        self.assertNotIn("reduce_sweet_items", uncertain_high["suggestion_keys"])

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

    def test_score_requires_calories_two_macros_and_reliable_overall_confidence(self):
        too_few_macros = assess_nutrition(
            self._meal(carbs_g=None, fat_g=None), high_confidence()
        )
        low_overall = assess_nutrition(self._meal(), high_confidence(overall="low"))

        for result in (too_few_macros, low_overall):
            self.assertIsNone(result["score"])
            self.assertEqual("indeterminate", result["tier"])
            self.assertTrue(result["insufficient_data"])

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

    def test_score_clamps_and_identical_inputs_return_identical_results(self):
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

        self.assertEqual(["add_vegetables", "reduce_sauce"], result["suggestion_keys"])
        self.assertEqual(len(result["suggestion_keys"]), len(set(result["suggestion_keys"])))

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


if __name__ == "__main__":
    unittest.main()
