"""Secure Gemini-backed meal estimation API with deterministic assessment."""

from __future__ import annotations

import base64
import binascii
import logging
import os
import re
from typing import Literal

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from lib.nutrition import assess_nutrition


env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
load_dotenv(env_path)

logger = logging.getLogger(__name__)
app = FastAPI()

SUPPORTED_MIME_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})
MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_ENCODED_IMAGE_CHARS = 7 * 1024 * 1024

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


class ImageValidationError(ValueError):
    """A safe, stable validation failure for image input."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class FoodNames(BaseModel):
    zh: str
    ja: str
    en: str


class Nutrients(BaseModel):
    calories_kcal: float | None = Field(default=None, ge=0)
    protein_g: float | None = Field(default=None, ge=0)
    carbs_g: float | None = Field(default=None, ge=0)
    fat_g: float | None = Field(default=None, ge=0)
    fiber_g: float | None = Field(default=None, ge=0)
    sugar_g: float | None = Field(default=None, ge=0)
    sodium_mg: float | None = Field(default=None, ge=0)


class NutrientConfidence(BaseModel):
    calories_kcal: ConfidenceLevel
    protein_g: ConfidenceLevel
    carbs_g: ConfidenceLevel
    fat_g: ConfidenceLevel
    fiber_g: ConfidenceLevel
    sugar_g: ConfidenceLevel
    sodium_mg: ConfidenceLevel


class Confidence(BaseModel):
    overall: ConfidenceLevel
    portion: ConfidenceLevel
    nutrients: NutrientConfidence


class ModelAnalysis(BaseModel):
    food_detected: bool
    food_names: FoodNames | None
    portion_grams: float | None = Field(default=None, ge=0)
    nutrients: Nutrients
    confidence: Confidence
    assumption_keys: list[AssumptionKey]


class Assessment(BaseModel):
    score: int | None
    tier: AssessmentTier
    statuses: dict[str, NutrientStatus]
    suggestion_keys: list[str]
    scoring_reasons: list[str]
    insufficient_data: bool


class AnalyzeResponse(ModelAnalysis):
    assessment: Assessment


class AnalyzeRequest(BaseModel):
    image: str = Field(min_length=1, max_length=MAX_ENCODED_IMAGE_CHARS)


_DATA_URI_PATTERN = re.compile(r"data:([^;,]+);base64,([A-Za-z0-9+/]*={0,2})")


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

    try:
        file_bytes = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise ImageValidationError("INVALID_IMAGE") from None

    if not file_bytes:
        raise ImageValidationError("INVALID_IMAGE")
    if len(file_bytes) > MAX_IMAGE_BYTES:
        raise ImageValidationError("IMAGE_TOO_LARGE")
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
    client = genai.Client(api_key=api_key)
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
                "seasonings make them unreliable. Do not provide a health score, tier, nutrient "
                "state, diagnosis, medical advice, or any assessment."
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
async def analyze_food(request: AnalyzeRequest) -> AnalyzeResponse:
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
    except HTTPException:
        raise
    except Exception:
        try:
            raise RuntimeError("Gemini provider request failed") from None
        except RuntimeError:
            logger.exception("Nutrition analysis provider request failed")
        raise HTTPException(
            status_code=502,
            detail={"code": "ANALYSIS_FAILED"},
        ) from None


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("api.analyze:app", host="0.0.0.0", port=8000, reload=True)
