"""Secure Gemini-backed meal estimation API with deterministic assessment."""

from __future__ import annotations

import base64
import binascii
import logging
import os
import re
from io import BytesIO
from typing import Literal

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from google import genai
from google.genai import types
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field, model_validator

from lib.nutrition import assess_nutrition


env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
load_dotenv(env_path)

logger = logging.getLogger(__name__)
app = FastAPI()


@app.exception_handler(RequestValidationError)
def handle_request_validation(
    _request: Request, _error: RequestValidationError
) -> JSONResponse:
    """Return a stable owned error without exposing validation internals."""
    return JSONResponse(
        status_code=400,
        content={"detail": {"code": "INVALID_IMAGE"}},
    )

# Production deployment requires platform-level rate limiting, quota, and budget controls.
SUPPORTED_MIME_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})
MAX_IMAGE_BYTES = 3 * 1024 * 1024
MAX_ENCODED_IMAGE_CHARS = 4 * 1024 * 1024
MAX_IMAGE_PIXELS = 20_000_000

ConfidenceLevel = Literal["low", "medium", "high"]
AssumptionKey = Literal[
    "visible_portion_only",
    "portion_estimated",
    "seasoning_estimated",
    "hidden_ingredients_possible",
]
NutrientStatus = Literal["low", "appropriate", "high", "indeterminate"]
AssessmentTier = Literal[
    "balanced", "mostly_balanced", "needs_attention", "indeterminate"
]


class StrictModel(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        allow_inf_nan=False,
        str_strip_whitespace=True,
        strict=True,
    )


class ImageValidationError(ValueError):
    """A safe, stable validation failure for image input."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class FoodNames(StrictModel):
    zh: str = Field(min_length=1, max_length=120)
    ja: str = Field(min_length=1, max_length=120)
    en: str = Field(min_length=1, max_length=120)


class Nutrients(StrictModel):
    calories_kcal: float | None = Field(default=None, ge=0, le=10_000)
    protein_g: float | None = Field(default=None, ge=0, le=2_000)
    carbs_g: float | None = Field(default=None, ge=0, le=2_000)
    fat_g: float | None = Field(default=None, ge=0, le=2_000)
    fiber_g: float | None = Field(default=None, ge=0, le=2_000)
    sugar_g: float | None = Field(default=None, ge=0, le=2_000)
    sodium_mg: float | None = Field(default=None, ge=0, le=100_000)


class NutrientConfidence(StrictModel):
    calories_kcal: ConfidenceLevel
    protein_g: ConfidenceLevel
    carbs_g: ConfidenceLevel
    fat_g: ConfidenceLevel
    fiber_g: ConfidenceLevel
    sugar_g: ConfidenceLevel
    sodium_mg: ConfidenceLevel


class Confidence(StrictModel):
    overall: ConfidenceLevel
    portion: ConfidenceLevel
    nutrients: NutrientConfidence


class ModelAnalysis(StrictModel):
    food_detected: bool
    food_names: FoodNames | None
    portion_grams: float | None = Field(default=None, ge=0, le=10_000)
    nutrients: Nutrients
    confidence: Confidence
    assumption_keys: list[AssumptionKey] = Field(max_length=4)

    @model_validator(mode="after")
    def validate_food_and_assumptions(self) -> ModelAnalysis:
        if self.food_detected and self.food_names is None:
            raise ValueError("food_names are required when food_detected is true")
        if len(set(self.assumption_keys)) != len(self.assumption_keys):
            raise ValueError("assumption_keys must be unique")
        return self


class NutrientStatuses(StrictModel):
    calories_kcal: NutrientStatus
    protein_g: NutrientStatus
    carbs_g: NutrientStatus
    fat_g: NutrientStatus
    fiber_g: NutrientStatus
    sugar_g: NutrientStatus
    sodium_mg: NutrientStatus


class Assessment(StrictModel):
    score: int | None = Field(ge=0, le=100)
    tier: AssessmentTier
    statuses: NutrientStatuses
    suggestion_keys: list[str]
    scoring_reasons: list[str]
    insufficient_data: bool


class AnalyzeResponse(ModelAnalysis):
    assessment: Assessment


class AnalyzeRequest(StrictModel):
    image: str = Field(min_length=1)


_DATA_URI_PATTERN = re.compile(r"data:([^;,]+);base64,([A-Za-z0-9+/]*={0,2})")


def _has_valid_signature(mime_type: str, file_bytes: bytes) -> bool:
    if mime_type == "image/jpeg":
        return len(file_bytes) > 3 and file_bytes.startswith(b"\xff\xd8\xff")
    if mime_type == "image/png":
        return file_bytes.startswith(b"\x89PNG\r\n\x1a\n")
    return file_bytes.startswith(b"RIFF") and file_bytes[8:12] == b"WEBP"


_FORMAT_TO_MIME = {"JPEG": "image/jpeg", "PNG": "image/png", "WEBP": "image/webp"}


def _validate_image_metadata(mime_type: str, image: Image.Image) -> None:
    actual_mime = _FORMAT_TO_MIME.get(image.format)
    width, height = image.size
    if actual_mime != mime_type or width * height > MAX_IMAGE_PIXELS:
        raise ImageValidationError("INVALID_IMAGE")


def _verify_image_content(mime_type: str, file_bytes: bytes) -> None:
    image = None
    try:
        image = Image.open(BytesIO(file_bytes))
        _validate_image_metadata(mime_type, image)
        image.verify()
        image.close()
        image = Image.open(BytesIO(file_bytes))
        _validate_image_metadata(mime_type, image)
        image.load()
    except ImageValidationError:
        raise
    except (Image.DecompressionBombError, OSError, TypeError, UnidentifiedImageError, ValueError):
        raise ImageValidationError("INVALID_IMAGE") from None
    finally:
        if image is not None:
            image.close()


def decode_image(image: str) -> tuple[str, bytes]:
    """Strictly decode a supported data URI or bare JPEG base64 payload."""
    if image.startswith("data:"):
        match = _DATA_URI_PATTERN.fullmatch(image)
        if not match:
            raise ImageValidationError("INVALID_IMAGE")
        mime_type = match.group(1).lower()
        encoded = match.group(2)
        if mime_type not in SUPPORTED_MIME_TYPES:
            raise ImageValidationError("UNSUPPORTED_IMAGE")
    else:
        mime_type = "image/jpeg"
        encoded = image

    if len(encoded) > MAX_ENCODED_IMAGE_CHARS:
        raise ImageValidationError("IMAGE_TOO_LARGE")
    try:
        file_bytes = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise ImageValidationError("INVALID_IMAGE") from None

    if not file_bytes or not _has_valid_signature(mime_type, file_bytes):
        raise ImageValidationError("INVALID_IMAGE")
    if len(file_bytes) > MAX_IMAGE_BYTES:
        raise ImageValidationError("IMAGE_TOO_LARGE")
    _verify_image_content(mime_type, file_bytes)
    return mime_type, file_bytes


def build_response(model: ModelAnalysis) -> AnalyzeResponse:
    """Append the local, deterministic assessment to Gemini's estimate."""
    analysis = model
    if not model.food_detected:
        analysis = model.model_copy(
            update={
                "food_names": None,
                "portion_grams": None,
                "nutrients": Nutrients(),
            }
        )

    assessment = Assessment.model_validate(
        assess_nutrition(
            analysis.nutrients.model_dump(),
            analysis.confidence.model_dump(),
        )
    )
    return AnalyzeResponse(**analysis.model_dump(), assessment=assessment)


def call_gemini(api_key: str, mime_type: str, file_bytes: bytes) -> ModelAnalysis:
    """Ask Gemini only for observable meal facts, never a health assessment."""
    with genai.Client(
        api_key=api_key,
        http_options=types.HttpOptions(timeout=20_000),
    ) as client:
        response = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=[
                types.Part.from_bytes(data=file_bytes, mime_type=mime_type),
                (
                    "Estimate only the visible meal in this image. Set food_detected to true "
                    "only when food is visible. When food is detected, provide food names in "
                    "Simplified Chinese (zh), Japanese (ja), and English (en), the visible "
                    "portion in grams, all seven nutrient estimates (calories_kcal, protein_g, "
                    "carbs_g, fat_g, fiber_g, sugar_g, sodium_mg), overall confidence, portion "
                    "confidence, and confidence for every nutrient field. Use only these "
                    "assumption keys: visible_portion_only, portion_estimated, seasoning_estimated, "
                    "hidden_ingredients_possible. Use null when a value is unknown; never use zero "
                    "to represent missing data. Sugar and sodium confidence must be low when hidden "
                    "seasonings make them unreliable. Do not return any recommendations, improvement "
                    "suggestions, nutrition advice, health score, tier, nutrient state, diagnosis, "
                    "medical advice, or any assessment."
                ),
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=ModelAnalysis,
                temperature=0.1,
            ),
        )
    if response.parsed is not None:
        return ModelAnalysis.model_validate(response.parsed)
    return ModelAnalysis.model_validate_json(response.text)


@app.post("/api/analyze", response_model=AnalyzeResponse)
@app.post("/", response_model=AnalyzeResponse)
def analyze_food(request: AnalyzeRequest) -> AnalyzeResponse:
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise HTTPException(
            status_code=503,
            detail={"code": "SERVICE_NOT_CONFIGURED"},
        )

    try:
        mime_type, file_bytes = decode_image(request.image)
    except ImageValidationError as error:
        raise HTTPException(status_code=400, detail={"code": error.code}) from None

    try:
        return build_response(call_gemini(api_key, mime_type, file_bytes))
    except Exception as error:
        logger.error(
            "Nutrition analysis provider request failed",
            extra={"exception_type": type(error).__name__},
        )
        raise HTTPException(
            status_code=502,
            detail={"code": "ANALYSIS_FAILED"},
        ) from None


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("api.analyze:app", host="0.0.0.0", port=8000, reload=True)
