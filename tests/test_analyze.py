"""Contract tests for the secure nutrition-analysis API."""

import asyncio
import base64
import os
import unittest
from unittest.mock import patch

from fastapi import HTTPException

import api.analyze as analyze


def image_data_uri(payload=b"meal", mime_type="image/jpeg"):
    encoded = base64.b64encode(payload).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


def model_analysis(*, food_detected=True):
    nutrients = {
        "calories_kcal": 600,
        "protein_g": 25,
        "carbs_g": 82,
        "fat_g": 18,
        "fiber_g": 7,
        "sugar_g": 8,
        "sodium_mg": 500,
    }
    return analyze.ModelAnalysis.model_validate(
        {
            "food_detected": food_detected,
            "food_names": {"zh": "鸡肉饭", "ja": "チキンライス", "en": "chicken rice"}
            if food_detected
            else None,
            "portion_grams": 320 if food_detected else None,
            "nutrients": nutrients,
            "confidence": {
                "overall": "high",
                "portion": "medium",
                "nutrients": {key: "high" for key in nutrients},
            },
            "assumption_keys": ["visible_portion_only"],
        }
    )


class ImageDecodingTests(unittest.TestCase):
    def test_decode_image_accepts_supported_data_uris_and_bare_base64(self):
        payload = b"meal-image"
        bare = base64.b64encode(payload).decode("ascii")

        for mime_type, image in (
            ("image/jpeg", image_data_uri(payload, "image/jpeg")),
            ("image/png", image_data_uri(payload, "image/png")),
            ("image/webp", image_data_uri(payload, "image/webp")),
            ("image/jpeg", bare),
        ):
            with self.subTest(mime_type=mime_type):
                actual_mime, actual_payload = analyze.decode_image(image)
                self.assertEqual(mime_type, actual_mime)
                self.assertEqual(payload, actual_payload)

    def test_decode_image_rejects_unsupported_mime_type(self):
        with self.assertRaises(analyze.ImageValidationError) as context:
            analyze.decode_image(image_data_uri(b"meal", "image/gif"))

        self.assertEqual("UNSUPPORTED_IMAGE", context.exception.code)

    def test_decode_image_rejects_malformed_or_empty_payloads(self):
        invalid_images = (
            "data:image/jpeg;base64,%%%not-base64%%%",
            "data:image/jpeg,Zm9vZA==",
            "data:image/jpeg;base64,",
        )

        for image in invalid_images:
            with self.subTest(image=image):
                with self.assertRaises(analyze.ImageValidationError) as context:
                    analyze.decode_image(image)
                self.assertEqual("INVALID_IMAGE", context.exception.code)

    def test_decode_image_rejects_payload_larger_than_five_mebibytes(self):
        oversized = image_data_uri(b"x" * (5 * 1024 * 1024 + 1))

        with self.assertRaises(analyze.ImageValidationError) as context:
            analyze.decode_image(oversized)

        self.assertEqual("IMAGE_TOO_LARGE", context.exception.code)


class ResponseCompositionTests(unittest.TestCase):
    def test_build_response_appends_deterministic_assessment(self):
        response = analyze.build_response(model_analysis())

        self.assertEqual("chicken rice", response.food_names.en)
        self.assertFalse(response.assessment.insufficient_data)
        self.assertIsNotNone(response.assessment.score)
        self.assertEqual("appropriate", response.assessment.statuses["calories_kcal"])

    def test_no_food_response_has_no_synthetic_nutrition_values(self):
        response = analyze.build_response(model_analysis(food_detected=False))

        self.assertIsNone(response.food_names)
        self.assertIsNone(response.portion_grams)
        self.assertTrue(all(value is None for value in response.nutrients.model_dump().values()))
        self.assertIsNone(response.assessment.score)
        self.assertEqual("indeterminate", response.assessment.tier)
        self.assertTrue(response.assessment.insufficient_data)


class AnalyzeEndpointTests(unittest.TestCase):
    def test_missing_api_key_returns_configured_service_error_without_provider_call(self):
        request = analyze.AnalyzeRequest(image=image_data_uri())

        with patch.dict(os.environ, {"GEMINI_API_KEY": ""}):
            with patch.object(analyze, "call_gemini") as provider:
                with self.assertRaises(HTTPException) as context:
                    asyncio.run(analyze.analyze_food(request))

        self.assertEqual(503, context.exception.status_code)
        self.assertEqual({"code": "SERVICE_NOT_CONFIGURED"}, context.exception.detail)
        provider.assert_not_called()

    def test_provider_failure_returns_stable_error_without_raw_exception_text(self):
        request = analyze.AnalyzeRequest(image=image_data_uri())

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(
                analyze,
                "call_gemini",
                side_effect=RuntimeError("provider response: secret internal failure"),
            ):
                with self.assertRaises(HTTPException) as context:
                    asyncio.run(analyze.analyze_food(request))

        self.assertEqual(502, context.exception.status_code)
        self.assertEqual({"code": "ANALYSIS_FAILED"}, context.exception.detail)
        self.assertNotIn("secret", str(context.exception.detail))

    def test_invalid_image_returns_stable_client_error(self):
        request = analyze.AnalyzeRequest(image="data:image/jpeg;base64,not-valid%%")

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(analyze, "call_gemini") as provider:
                with self.assertRaises(HTTPException) as context:
                    asyncio.run(analyze.analyze_food(request))

        self.assertEqual(400, context.exception.status_code)
        self.assertEqual({"code": "INVALID_IMAGE"}, context.exception.detail)
        provider.assert_not_called()


if __name__ == "__main__":
    unittest.main()
