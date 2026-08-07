"""Contract tests for the secure nutrition-analysis API."""

import base64
import inspect
import json
import os
import tempfile
import unittest
import warnings
from io import BytesIO
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from fastapi import FastAPI, HTTPException
from PIL import Image
from pydantic import ValidationError

with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    from starlette.testclient import TestClient

import api.analyze as analyze


def real_image_bytes(image_format: str) -> bytes:
    buffer = BytesIO()
    Image.new("RGB", (1, 1), color=(10, 20, 30)).save(buffer, format=image_format)
    return buffer.getvalue()


JPEG_BYTES = real_image_bytes("JPEG")
PNG_BYTES = real_image_bytes("PNG")
WEBP_BYTES = real_image_bytes("WEBP")
IMAGE_BYTES_BY_MIME = {
    "image/jpeg": JPEG_BYTES,
    "image/png": PNG_BYTES,
    "image/webp": WEBP_BYTES,
}


def image_data_uri(payload=JPEG_BYTES, mime_type="image/jpeg"):
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


class DeploymentSurfaceTests(unittest.TestCase):
    def test_health_endpoint_identifies_the_running_service(self):
        response = TestClient(analyze.app).get("/health")

        self.assertEqual(200, response.status_code)
        self.assertEqual(
            {"status": "ok", "service": "kalories"},
            response.json(),
        )

    def test_mount_frontend_serves_the_built_index(self):
        with tempfile.TemporaryDirectory() as directory:
            dist = Path(directory)
            (dist / "index.html").write_text(
                "<!doctype html><title>Kalories</title>",
                encoding="utf-8",
            )
            application = FastAPI()

            self.assertTrue(analyze.mount_frontend(application, dist))
            response = TestClient(application).get("/")

        self.assertEqual(200, response.status_code)
        self.assertIn("<title>Kalories</title>", response.text)


class ImageDecodingTests(unittest.TestCase):
    def test_decode_image_accepts_real_supported_data_uris_and_bare_jpeg(self):
        bare_jpeg = base64.b64encode(JPEG_BYTES).decode("ascii")

        for mime_type, image in (
            ("image/jpeg", image_data_uri(JPEG_BYTES, "image/jpeg")),
            ("image/png", image_data_uri(PNG_BYTES, "image/png")),
            ("image/webp", image_data_uri(WEBP_BYTES, "image/webp")),
            ("image/jpeg", bare_jpeg),
        ):
            with self.subTest(mime_type=mime_type):
                actual_mime, actual_payload = analyze.decode_image(image)
                self.assertEqual(mime_type, actual_mime)
                self.assertEqual(IMAGE_BYTES_BY_MIME[mime_type], actual_payload)

    def test_decode_image_rejects_unsupported_mime_type(self):
        with self.assertRaises(analyze.ImageValidationError) as context:
            analyze.decode_image(image_data_uri(JPEG_BYTES, "image/gif"))

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

    def test_decode_image_rejects_invalid_or_mismatched_content(self):
        invalid_images = (
            image_data_uri(b"not-a-jpeg", "image/jpeg"),
            image_data_uri(JPEG_BYTES, "image/png"),
            image_data_uri(b"\xff\xd8\xffnot-an-image", "image/jpeg"),
            image_data_uri(JPEG_BYTES[:20], "image/jpeg"),
            image_data_uri(PNG_BYTES[:20], "image/png"),
            image_data_uri(WEBP_BYTES[:20], "image/webp"),
        )

        for image in invalid_images:
            with self.subTest(image=image[:32]):
                with self.assertRaises(analyze.ImageValidationError) as context:
                    analyze.decode_image(image)
                self.assertEqual("INVALID_IMAGE", context.exception.code)

    def test_decode_image_rejects_jpeg_missing_trailing_byte_after_verify(self):
        with self.assertRaises(analyze.ImageValidationError) as context:
            analyze.decode_image(image_data_uri(JPEG_BYTES[:-1], "image/jpeg"))

        self.assertEqual("INVALID_IMAGE", context.exception.code)

    def test_decode_image_rejects_payload_larger_than_three_mebibytes(self):
        oversized = image_data_uri(
            JPEG_BYTES + b"x" * (3 * 1024 * 1024 + 1 - len(JPEG_BYTES))
        )

        with self.assertRaises(analyze.ImageValidationError) as context:
            analyze.decode_image(oversized)

        self.assertEqual("IMAGE_TOO_LARGE", context.exception.code)

    def test_encoded_length_limit_is_checked_before_base64_decoding(self):
        encoded = "A" * (4 * 1024 * 1024 + 1)

        with patch.object(analyze.base64, "b64decode") as decode:
            with self.assertRaises(analyze.ImageValidationError) as context:
                analyze.decode_image(encoded)

        self.assertEqual("IMAGE_TOO_LARGE", context.exception.code)
        decode.assert_not_called()

    def test_pixel_limit_rejects_image_before_full_verify(self):
        image = MagicMock(format="JPEG", size=(5_000, 4_001))

        with patch.object(analyze.Image, "open", return_value=image):
            with self.assertRaises(analyze.ImageValidationError) as context:
                analyze.decode_image(image_data_uri())

        self.assertEqual("INVALID_IMAGE", context.exception.code)
        image.verify.assert_not_called()


class SchemaValidationTests(unittest.TestCase):
    def test_model_analysis_rejects_stringly_typed_provider_values(self):
        invalid_payloads = []

        string_boolean = model_analysis().model_dump()
        string_boolean["food_detected"] = "false"
        invalid_payloads.append(string_boolean)

        string_portion = model_analysis().model_dump()
        string_portion["portion_grams"] = "320"
        invalid_payloads.append(string_portion)

        string_nutrient = model_analysis().model_dump()
        string_nutrient["nutrients"]["calories_kcal"] = "600"
        invalid_payloads.append(string_nutrient)

        boolean_nutrient = model_analysis().model_dump()
        boolean_nutrient["nutrients"]["protein_g"] = True
        invalid_payloads.append(boolean_nutrient)

        for payload in invalid_payloads:
            with self.subTest(payload=payload):
                with self.assertRaises(ValidationError):
                    analyze.ModelAnalysis.model_validate(payload)

    def test_nutrients_reject_nan_and_infinite_values(self):
        for value in (float("nan"), float("inf"), float("-inf")):
            with self.subTest(value=value):
                with self.assertRaises(ValidationError):
                    analyze.Nutrients.model_validate({"calories_kcal": value})

    def test_model_analysis_rejects_excessive_portion_and_nutrient_estimates(self):
        excessive_portion = model_analysis().model_dump()
        excessive_portion["portion_grams"] = 10_001
        excessive_calories = model_analysis().model_dump()
        excessive_calories["nutrients"]["calories_kcal"] = 10_001

        for payload in (excessive_portion, excessive_calories):
            with self.subTest(payload=payload):
                with self.assertRaises(ValidationError):
                    analyze.ModelAnalysis.model_validate(payload)

    def test_food_names_strip_whitespace_and_reject_empty_names(self):
        names = analyze.FoodNames.model_validate(
            {"zh": " 鸡肉饭 ", "ja": " チキンライス ", "en": " chicken rice "}
        )
        self.assertEqual("chicken rice", names.en)

        with self.assertRaises(ValidationError):
            analyze.FoodNames.model_validate({"zh": " ", "ja": "米", "en": "rice"})

    def test_model_analysis_rejects_invalid_food_name_assumptions_and_extras(self):
        missing_names = model_analysis().model_dump()
        missing_names["food_names"] = None
        duplicates = model_analysis().model_dump()
        duplicates["assumption_keys"] = ["visible_portion_only", "visible_portion_only"]
        extra = model_analysis().model_dump()
        extra["untrusted_provider_field"] = True

        for payload in (missing_names, duplicates, extra):
            with self.subTest(payload=payload):
                with self.assertRaises(ValidationError):
                    analyze.ModelAnalysis.model_validate(payload)

    def test_assessment_rejects_out_of_range_scores_and_unrecognized_status_keys(self):
        assessment = analyze.build_response(model_analysis()).assessment.model_dump()
        out_of_range = assessment | {"score": 101}
        extra_status = analyze.build_response(model_analysis()).assessment.model_dump()
        extra_status["statuses"]["untrusted"] = "high"

        for payload in (out_of_range, extra_status):
            with self.subTest(payload=payload):
                with self.assertRaises(ValidationError):
                    analyze.Assessment.model_validate(payload)


class ResponseCompositionTests(unittest.TestCase):
    def test_build_response_appends_deterministic_assessment(self):
        response = analyze.build_response(model_analysis())

        self.assertEqual("chicken rice", response.food_names.en)
        self.assertFalse(response.assessment.insufficient_data)
        self.assertIsNotNone(response.assessment.score)
        self.assertEqual("appropriate", response.assessment.statuses.calories_kcal)

    def test_no_food_response_has_no_synthetic_nutrition_values(self):
        response = analyze.build_response(model_analysis(food_detected=False))

        self.assertIsNone(response.food_names)
        self.assertIsNone(response.portion_grams)
        self.assertTrue(all(value is None for value in response.nutrients.model_dump().values()))
        self.assertIsNone(response.assessment.score)
        self.assertEqual("indeterminate", response.assessment.tier)
        self.assertTrue(response.assessment.insufficient_data)


class GeminiProviderTests(unittest.TestCase):
    def test_call_gemini_uses_bounded_context_managed_structured_request_and_safe_prompt(self):
        response = SimpleNamespace(parsed=model_analysis().model_dump(), text=None)
        image_part = object()
        file_bytes = JPEG_BYTES

        with patch.object(analyze.genai, "Client") as client_class:
            with patch.object(
                analyze.types.Part, "from_bytes", return_value=image_part
            ) as from_bytes:
                client = client_class.return_value.__enter__.return_value
                client.models.generate_content.return_value = response
                actual = analyze.call_gemini("configured-key", "image/jpeg", file_bytes)

        self.assertIsInstance(actual, analyze.ModelAnalysis)
        http_options = client_class.call_args.kwargs["http_options"]
        self.assertEqual(20_000, http_options.timeout)
        self.assertEqual("configured-key", client_class.call_args.kwargs["api_key"])
        client_class.return_value.__enter__.assert_called_once_with()
        client_class.return_value.__exit__.assert_called_once()
        from_bytes.assert_called_once_with(data=file_bytes, mime_type="image/jpeg")
        call = client.models.generate_content.call_args
        self.assertEqual("gemini-3-flash-preview", call.kwargs["model"])
        self.assertEqual(image_part, call.kwargs["contents"][0])
        prompt = call.kwargs["contents"][1]
        config = call.kwargs["config"]
        self.assertEqual("application/json", config.response_mime_type)
        self.assertEqual(
            analyze._clean_json_schema(analyze.ModelAnalysis.model_json_schema()),
            config.response_schema,
        )
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
            client = client_class.return_value.__enter__.return_value
            client.models.generate_content.return_value = response
            actual = analyze.call_gemini("configured-key", "image/png", PNG_BYTES)

        self.assertEqual("chicken rice", actual.food_names.en)

    def test_call_gemini_rejects_stringly_typed_text_json(self):
        stringly_typed = model_analysis().model_dump()
        stringly_typed["food_detected"] = "false"
        stringly_typed["portion_grams"] = "320"
        stringly_typed["nutrients"]["calories_kcal"] = "600"
        response = SimpleNamespace(parsed=None, text=json.dumps(stringly_typed))

        with patch.object(analyze.genai, "Client") as client_class:
            client = client_class.return_value.__enter__.return_value
            client.models.generate_content.return_value = response
            with self.assertRaises(ValidationError):
                analyze.call_gemini("configured-key", "image/png", PNG_BYTES)

    def test_call_gemini_rejects_invalid_provider_model_values(self):
        invalid = model_analysis().model_dump()
        invalid["nutrients"]["calories_kcal"] = -1
        response = SimpleNamespace(parsed=invalid, text=None)

        with patch.object(analyze.genai, "Client") as client_class:
            client = client_class.return_value.__enter__.return_value
            client.models.generate_content.return_value = response
            with self.assertRaises(ValidationError):
                analyze.call_gemini("configured-key", "image/webp", WEBP_BYTES)


class AnalyzeEndpointTests(unittest.TestCase):
    def setUp(self):
        self.rate_limiter = MagicMock()
        self.rate_limiter.try_acquire.return_value = True
        limiter_patch = patch.object(
            analyze,
            "ANALYSIS_RATE_LIMITER",
            self.rate_limiter,
        )
        limiter_patch.start()
        self.addCleanup(limiter_patch.stop)

    def test_route_is_synchronous_and_request_rejects_empty_image(self):
        self.assertFalse(inspect.iscoroutinefunction(analyze.analyze_food))
        with self.assertRaises(ValidationError):
            analyze.AnalyzeRequest(image="")

    def test_oversized_encoded_request_reaches_image_validation(self):
        oversized_image = image_data_uri(
            JPEG_BYTES + b"x" * (3 * 1024 * 1024 + 1 - len(JPEG_BYTES))
        )
        request = analyze.AnalyzeRequest(image=oversized_image)

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(analyze, "call_gemini") as provider:
                with self.assertRaises(HTTPException) as context:
                    analyze.analyze_food(request)

        self.assertEqual(400, context.exception.status_code)
        self.assertEqual({"code": "IMAGE_TOO_LARGE"}, context.exception.detail)
        self.rate_limiter.try_acquire.assert_not_called()
        provider.assert_not_called()

    def test_missing_api_key_returns_configured_service_error_without_provider_call(self):
        request = analyze.AnalyzeRequest(image=image_data_uri())

        with patch.dict(os.environ, {"GEMINI_API_KEY": ""}):
            with patch.object(analyze, "call_gemini") as provider:
                with self.assertRaises(HTTPException) as context:
                    analyze.analyze_food(request)

        self.assertEqual(503, context.exception.status_code)
        self.assertEqual({"code": "SERVICE_NOT_CONFIGURED"}, context.exception.detail)
        self.rate_limiter.try_acquire.assert_not_called()
        provider.assert_not_called()

    def test_valid_image_is_rate_limited_before_provider_call(self):
        request = analyze.AnalyzeRequest(image=image_data_uri())
        self.rate_limiter.try_acquire.return_value = False

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(analyze, "call_gemini") as provider:
                with self.assertRaises(HTTPException) as context:
                    analyze.analyze_food(request)

        self.assertEqual(429, context.exception.status_code)
        self.assertEqual({"code": "RATE_LIMITED"}, context.exception.detail)
        self.rate_limiter.try_acquire.assert_called_once_with()
        provider.assert_not_called()

    def test_allowed_valid_image_acquires_once_immediately_before_provider(self):
        request = analyze.AnalyzeRequest(image=image_data_uri())
        call_order = []
        self.rate_limiter.try_acquire.side_effect = (
            lambda: call_order.append("limiter") or True
        )

        def provider_response(*_args):
            call_order.append("provider")
            return model_analysis()

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(
                analyze,
                "call_gemini",
                side_effect=provider_response,
            ) as provider:
                response = analyze.analyze_food(request)

        self.assertTrue(response.food_detected)
        self.assertEqual(["limiter", "provider"], call_order)
        self.rate_limiter.try_acquire.assert_called_once_with()
        provider.assert_called_once_with("configured", "image/jpeg", JPEG_BYTES)

    def test_provider_failure_returns_stable_error_and_safe_exception_type_log(self):
        request = analyze.AnalyzeRequest(image=image_data_uri())

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(
                analyze,
                "call_gemini",
                side_effect=RuntimeError("provider response: secret internal failure"),
            ):
                with patch.object(analyze.logger, "error") as log_error:
                    with self.assertRaises(HTTPException) as context:
                        analyze.analyze_food(request)

        self.assertEqual(502, context.exception.status_code)
        self.assertEqual({"code": "ANALYSIS_FAILED"}, context.exception.detail)
        self.assertNotIn("secret", str(context.exception.detail))
        self.rate_limiter.try_acquire.assert_called_once_with()
        log_error.assert_called_once_with(
            "Nutrition analysis provider request failed",
            extra={"exception_type": "RuntimeError"},
        )
        self.assertNotIn("secret", str(log_error.call_args))

    def test_invalid_and_unsupported_images_return_stable_client_errors(self):
        cases = (
            ("data:image/jpeg;base64,not-valid%%", "INVALID_IMAGE"),
            (image_data_uri(JPEG_BYTES, "image/gif"), "UNSUPPORTED_IMAGE"),
        )
        for image, expected_code in cases:
            with self.subTest(expected_code=expected_code):
                request = analyze.AnalyzeRequest(image=image)
                with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
                    with patch.object(analyze, "call_gemini") as provider:
                        with self.assertRaises(HTTPException) as context:
                            analyze.analyze_food(request)
                self.assertEqual(400, context.exception.status_code)
                self.assertEqual({"code": expected_code}, context.exception.detail)
                self.rate_limiter.try_acquire.assert_not_called()
                provider.assert_not_called()

    def test_provider_http_exception_is_mapped_to_owned_error(self):
        request = analyze.AnalyzeRequest(image=image_data_uri())
        provider_error = HTTPException(status_code=429, detail={"code": "RATE_LIMITED"})

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(analyze, "call_gemini", side_effect=provider_error):
                with patch.object(analyze.logger, "error") as log_error:
                    with self.assertRaises(HTTPException) as context:
                        analyze.analyze_food(request)

        self.assertEqual(502, context.exception.status_code)
        self.assertEqual({"code": "ANALYSIS_FAILED"}, context.exception.detail)
        self.assertNotIn("RATE_LIMITED", str(context.exception.detail))
        self.rate_limiter.try_acquire.assert_called_once_with()
        log_error.assert_called_once_with(
            "Nutrition analysis provider request failed",
            extra={"exception_type": "HTTPException"},
        )

    def test_successful_provider_response_has_deterministic_assessment_without_fake_zeros(self):
        request = analyze.AnalyzeRequest(image=image_data_uri())

        with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
            with patch.object(
                analyze, "call_gemini", return_value=model_analysis(food_detected=False)
            ):
                response = analyze.analyze_food(request)

        self.assertFalse(response.food_detected)
        self.rate_limiter.try_acquire.assert_called_once_with()
        self.assertTrue(all(value is None for value in response.nutrients.model_dump().values()))
        self.assertIsNone(response.assessment.score)
        self.assertTrue(response.assessment.insufficient_data)


class ApplicationContractTests(unittest.TestCase):
    def setUp(self):
        self.rate_limiter = MagicMock()
        self.rate_limiter.try_acquire.return_value = True
        limiter_patch = patch.object(
            analyze,
            "ANALYSIS_RATE_LIMITER",
            self.rate_limiter,
        )
        limiter_patch.start()
        self.addCleanup(limiter_patch.stop)

    def test_post_routes_and_no_cors_middleware(self):
        post_paths = {
            route.path
            for route in analyze.app.routes
            if "POST" in getattr(route, "methods", set())
        }

        self.assertTrue({"/", "/api/analyze"}.issubset(post_paths))
        self.assertEqual([], analyze.app.user_middleware)

    def test_testclient_serializes_owned_error_and_success(self):
        with TestClient(analyze.app) as client:
            with patch.dict(os.environ, {"GEMINI_API_KEY": ""}):
                missing_key = client.post("/api/analyze", json={"image": image_data_uri()})
            self.rate_limiter.try_acquire.return_value = False
            with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
                rate_limited = client.post(
                    "/api/analyze",
                    json={"image": image_data_uri()},
                )
            self.rate_limiter.try_acquire.return_value = True
            with patch.dict(os.environ, {"GEMINI_API_KEY": "configured"}):
                with patch.object(analyze, "call_gemini", return_value=model_analysis()):
                    success = client.post("/api/analyze", json={"image": image_data_uri()})

        self.assertEqual(503, missing_key.status_code)
        self.assertEqual({"code": "SERVICE_NOT_CONFIGURED"}, missing_key.json()["detail"])
        self.assertEqual(429, rate_limited.status_code)
        self.assertEqual({"code": "RATE_LIMITED"}, rate_limited.json()["detail"])
        self.assertEqual(200, success.status_code)
        self.assertEqual("chicken rice", success.json()["food_names"]["en"])
        self.assertIn("assessment", success.json())
        self.assertEqual(2, self.rate_limiter.try_acquire.call_count)

    def test_stringly_typed_or_assessment_provider_json_maps_to_owned_error(self):
        stringly_typed = model_analysis().model_dump()
        stringly_typed["food_detected"] = "false"
        stringly_typed["portion_grams"] = "320"
        stringly_typed["nutrients"]["calories_kcal"] = "600"

        provider_assessment = model_analysis().model_dump()
        provider_assessment["score"] = "82"

        with TestClient(analyze.app) as client:
            for label, provider_payload in (
                ("stringly typed facts", stringly_typed),
                ("provider supplied score", provider_assessment),
            ):
                with self.subTest(label=label):
                    provider_response = SimpleNamespace(
                        parsed=None,
                        text=json.dumps(provider_payload),
                    )
                    with patch.dict(
                        os.environ,
                        {"GEMINI_API_KEY": "configured"},
                    ):
                        with patch.object(analyze.genai, "Client") as client_class:
                            provider = client_class.return_value.__enter__.return_value
                            provider.models.generate_content.return_value = provider_response
                            response = client.post(
                                "/api/analyze",
                                json={"image": image_data_uri()},
                            )

                    self.assertEqual(502, response.status_code)
                    self.assertEqual(
                        {"detail": {"code": "ANALYSIS_FAILED"}},
                        response.json(),
                    )

        self.assertEqual(2, self.rate_limiter.try_acquire.call_count)

    def test_malformed_requests_return_only_the_owned_invalid_image_error(self):
        cases = (
            ("missing image", {"json": {}}),
            ("empty image", {"json": {"image": ""}}),
            ("wrong image type", {"json": {"image": 123}}),
            (
                "extra request field",
                {"json": {"image": image_data_uri(), "unexpected": True}},
            ),
            (
                "malformed json",
                {
                    "content": b'{"image":',
                    "headers": {"Content-Type": "application/json"},
                },
            ),
        )

        with TestClient(analyze.app) as client:
            for label, request_kwargs in cases:
                with self.subTest(label=label):
                    response = client.post("/api/analyze", **request_kwargs)

                    self.assertEqual(400, response.status_code)
                    self.assertEqual(
                        {"detail": {"code": "INVALID_IMAGE"}},
                        response.json(),
                    )
                    serialized = response.text
                    for leaked_key in ('"loc"', '"msg"', '"input"'):
                        self.assertNotIn(leaked_key, serialized)

        self.rate_limiter.try_acquire.assert_not_called()


if __name__ == "__main__":
    unittest.main()
