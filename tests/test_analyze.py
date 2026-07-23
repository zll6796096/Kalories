"""Contract tests for the secure nutrition-analysis API."""

import asyncio
import base64
import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import HTTPException
from pydantic import ValidationError

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


class GeminiProviderTests(unittest.TestCase):
    def test_call_gemini_configures_structured_estimation_and_complete_safe_prompt(self):
        response = SimpleNamespace(parsed=model_analysis().model_dump(), text=None)
        image_part = object()
        file_bytes = b"jpeg-bytes"

        with patch.object(analyze.genai, "Client") as client_class:
            with patch.object(
                analyze.types.Part, "from_bytes", return_value=image_part
            ) as from_bytes:
                client_class.return_value.models.generate_content.return_value = response
                actual = analyze.call_gemini("configured-key", "image/jpeg", file_bytes)

        self.assertIsInstance(actual, analyze.ModelAnalysis)
        client_class.assert_called_once_with(api_key="configured-key")
        from_bytes.assert_called_once_with(data=file_bytes, mime_type="image/jpeg")
        call = client_class.return_value.models.generate_content.call_args
        self.assertEqual("gemini-3-flash-preview", call.kwargs["model"])
        self.assertEqual(image_part, call.kwargs["contents"][0])
        prompt = call.kwargs["contents"][1]
        config = call.kwargs["config"]
        self.assertEqual("application/json", config.response_mime_type)
        self.assertIs(analyze.ModelAnalysis, config.response_schema)
        self.assertEqual(0.1, config.temperature)
        for required_text in (
            "visible meal",
            "food_detected",
            "Simplified Chinese (zh)",
            "Japanese (ja)",
            "English (en)",
            "portion in grams",
            "calories_kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg",
            "overall confidence",
            "portion confidence",
            "confidence for every nutrient field",
            "visible_portion_only, portion_estimated, seasoning_estimated, hidden_ingredients_possible",
            "Use null",
            "never use zero",
            "Sugar and sodium confidence must be low",
            "recommendations",
            "improvement suggestions",
            "nutrition advice",
            "health score, tier, nutrient state, diagnosis",
        ):
            with self.subTest(required_text=required_text):
                self.assertIn(required_text, prompt)

    def test_call_gemini_validates_text_json_when_parsed_response_is_unavailable(self):
        response = SimpleNamespace(parsed=None, text=model_analysis().model_dump_json())

        with patch.object(analyze.genai, "Client") as client_class:
            client_class.return_value.models.generate_content.return_value = response
            actual = analyze.call_gemini("configured-key", "image/png", b"png-bytes")

        self.assertEqual("chicken rice", actual.food_names.en)

    def test_call_gemini_rejects_invalid_provider_model_values(self):
        invalid = model_analysis().model_dump()
        invalid["nutrients"]["calories_kcal"] = -1
        response = SimpleNamespace(parsed=invalid, text=None)

        with patch.object(analyze.genai, "Client") as client_class:
            client_class.return_value.models.generate_content.return_value = response
            with self.assertRaises(ValidationError):
                analyze.call_gemini("configured-key", "image/webp", b"webp-bytes")


class AnalyzeEndpointTests(unittest.TestCase):
    def test_analyze_request_rejects_empty_image(self):
        with self.assertRaises(ValidationError):
            analyze.AnalyzeRequest(image="")

    def test_oversized_encoded_request_reaches_image_validation(self):
        oversized_image = image_data_uri(b"x" * (6 * 1024 * 1024))
        try:
            request = analyze.AnalyzeRequest(image=oversized_image)
        except ValidationError:
            self.fail("encoded image size must not preempt decoded image validation")

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(analyze, "call_gemini") as provider:
                with self.assertRaises(HTTPException) as context:
                    asyncio.run(analyze.analyze_food(request))

        self.assertEqual(400, context.exception.status_code)
        self.assertEqual({"code": "IMAGE_TOO_LARGE"}, context.exception.detail)
        provider.assert_not_called()

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

    def test_unsupported_image_returns_stable_client_error(self):
        request = analyze.AnalyzeRequest(image=image_data_uri(b"meal", "image/gif"))

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(analyze, "call_gemini") as provider:
                with self.assertRaises(HTTPException) as context:
                    asyncio.run(analyze.analyze_food(request))

        self.assertEqual(400, context.exception.status_code)
        self.assertEqual({"code": "UNSUPPORTED_IMAGE"}, context.exception.detail)
        provider.assert_not_called()

    def test_deliberate_provider_http_exception_is_preserved(self):
        request = analyze.AnalyzeRequest(image=image_data_uri())
        expected = HTTPException(status_code=429, detail={"code": "RATE_LIMITED"})

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(analyze, "call_gemini", side_effect=expected):
                with self.assertRaises(HTTPException) as context:
                    asyncio.run(analyze.analyze_food(request))

        self.assertIs(expected, context.exception)

    def test_successful_provider_response_has_deterministic_assessment_without_fake_zeros(self):
        request = analyze.AnalyzeRequest(image=image_data_uri())

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(
                analyze, "call_gemini", return_value=model_analysis(food_detected=False)
            ):
                response = asyncio.run(analyze.analyze_food(request))

        self.assertTrue(response.food_detected is False)
        self.assertTrue(all(value is None for value in response.nutrients.model_dump().values()))
        self.assertIsNone(response.assessment.score)
        self.assertTrue(response.assessment.insufficient_data)


class ApplicationContractTests(unittest.TestCase):
    def test_post_routes_and_no_cors_middleware(self):
        post_paths = {
            route.path
            for route in analyze.app.routes
            if "POST" in getattr(route, "methods", set())
        }

        self.assertTrue({"/", "/api/analyze"}.issubset(post_paths))
        self.assertEqual([], analyze.app.user_middleware)


if __name__ == "__main__":
    unittest.main()
