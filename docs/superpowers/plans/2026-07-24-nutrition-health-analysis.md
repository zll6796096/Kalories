# Kalories Nutrition and Health Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an Apple-inspired, camera-first Kalories experience that estimates seven nutrition values, applies a deterministic Japan-first health assessment, and presents every result on one continuous page in Chinese, Japanese, and English.

**Architecture:** Gemini returns structured estimation facts and three localized food names. A pure Python module computes score, tier, nutrient statuses, and advice keys from documented rules. React owns the camera state machine, locale selection, translation, error recovery, single-page result presentation, and image export; the browser never receives the Gemini key.

**Tech Stack:** React 19, TypeScript 5.8, Vite 6, Tailwind CSS 4, CSS motion with reduced-motion support, react-webcam, html2canvas, FastAPI, Pydantic, Google GenAI for Python, Python `unittest`, Vitest.

---

## File Map

### Create

- `lib/__init__.py` — marks the shared backend library package.
- `lib/nutrition.py` — pure deterministic nutrition assessment and advice selection.
- `tests/__init__.py` — makes backend tests importable by exact module name.
- `tests/test_nutrition.py` — boundary and scoring tests for the assessment module.
- `tests/test_analyze.py` — image-validation and response-composition tests.
- `src/types.ts` — API, assessment, locale, confidence, and UI types.
- `src/i18n.ts` — three complete dictionaries, locale resolution, and local persistence.
- `src/i18n.test.ts` — locale resolution and translation-completeness tests.
- `src/formatters.ts` — null-safe localized number and nutrient formatting.
- `src/formatters.test.ts` — null handling and localized formatting tests.
- `src/api.ts` — typed API client and stable error-code mapping.
- `src/api.test.ts` — API success and typed-failure tests.
- `src/components/LanguageSwitcher.tsx` — accessible three-language control.
- `src/screens/IntroScreen.tsx` — Apple-style entry screen.
- `src/screens/CameraScreen.tsx` — camera, inline permission/capture errors, and shutter.
- `src/screens/AnalyzingScreen.tsx` — localized progress state over the captured image.
- `src/screens/ResultScreen.tsx` — continuous result page with all required information.
- `src/screens/ResultScreen.test.tsx` — static-render contract for the single result page.

### Modify

- `api/analyze.py` — typed schema, safe image parsing, Gemini estimation, safe errors, assessment composition.
- `src/App.tsx` — app state machine, retry flow, locale state, and screen orchestration.
- `src/index.css` — complete Apple-inspired responsive visual system.
- `vite.config.ts` — remove client-side API-key injection while preserving proxy and aliases.
- `package.json` — add Vitest scripts and development dependency.
- `package-lock.json` — lock Vitest dependency graph.
- `.gitignore` — ignore visual-companion and browser-verification artifacts.
- `README.md` — document separate API/UI startup, test commands, languages, and estimation boundary.

### Preserve

- `src/main.tsx`
- `index.html`
- `.env.example`
- `requirements.txt` unless a genuinely missing runtime dependency is discovered by a clean install check.

---

### Task 1: Establish Test Harness and Repository Hygiene

**Files:**

- Modify: `package.json:6-35`
- Modify: `package-lock.json`
- Modify: `.gitignore:1-13`

- [ ] **Step 1: Confirm the pre-task Git boundary**

Run:

```bash
git status --short --branch
git diff --stat
```

Expected: `main` is ahead by the approved design commit, `.superpowers/` is the only untracked implementation-adjacent directory, and there are no unrelated user modifications.

- [ ] **Step 2: Install the frontend test runner**

Run:

```bash
npm install --save-dev vitest@^3.2.4
```

Expected: `package.json` and `package-lock.json` change; no production dependency is added.

- [ ] **Step 3: Add deterministic test scripts**

Update `package.json` scripts to:

```json
{
  "scripts": {
    "dev": "vite --port=3000 --host=0.0.0.0",
    "build": "vite build",
    "preview": "vite preview",
    "clean": "rm -rf dist",
    "lint": "tsc --noEmit",
    "test": "vitest run --passWithNoTests",
    "test:watch": "vitest"
  }
}
```

- [ ] **Step 4: Ignore local design and browser artifacts**

Append to `.gitignore`:

```gitignore

# Local design and browser verification
.superpowers/
output/playwright/
```

- [ ] **Step 5: Verify the harness**

Run:

```bash
npm test
npm run lint
```

Expected: Vitest exits successfully with no test files yet; TypeScript exits 0.

- [ ] **Step 6: Commit the harness**

```bash
git add -- package.json package-lock.json .gitignore
git commit -m "test: add frontend test harness"
```

---

### Task 2: Build the Deterministic Nutrition Assessment with TDD

**Files:**

- Create: `lib/__init__.py`
- Create: `lib/nutrition.py`
- Create: `tests/__init__.py`
- Create: `tests/test_nutrition.py`

- [ ] **Step 1: Write failing scoring and boundary tests**

Create `tests/test_nutrition.py`:

```python
import unittest

from lib.nutrition import assess_nutrition


def nutrients(**overrides):
    values = {
        "calories_kcal": 600.0,
        "protein_g": 25.0,
        "carbs_g": 82.0,
        "fat_g": 18.0,
        "fiber_g": 7.0,
        "sugar_g": 8.0,
        "sodium_mg": 500.0,
    }
    values.update(overrides)
    return values


def confidence(overall="high", **nutrient_confidence):
    return {
        "overall": overall,
        "nutrients": {
            "calories_kcal": "high",
            "protein_g": "high",
            "carbs_g": "high",
            "fat_g": "high",
            "fiber_g": "medium",
            "sugar_g": "low",
            "sodium_mg": "low",
            **nutrient_confidence,
        },
    }


class NutritionAssessmentTests(unittest.TestCase):
    def test_balanced_meal_scores_in_balanced_tier(self):
        result = assess_nutrition(nutrients(), confidence())
        self.assertGreaterEqual(result["score"], 80)
        self.assertEqual(result["tier"], "balanced")
        self.assertEqual(result["statuses"]["protein_g"], "appropriate")
        self.assertEqual(result["statuses"]["carbs_g"], "appropriate")
        self.assertEqual(result["statuses"]["fat_g"], "appropriate")

    def test_macro_states_use_derived_macro_energy(self):
        result = assess_nutrition(
            nutrients(protein_g=10, carbs_g=20, fat_g=40),
            confidence(),
        )
        self.assertEqual(result["statuses"]["protein_g"], "low")
        self.assertEqual(result["statuses"]["fat_g"], "high")
        self.assertLess(result["score"], 80)

    def test_fiber_boundaries_are_deterministic(self):
        self.assertEqual(
            assess_nutrition(nutrients(fiber_g=6), confidence())["statuses"]["fiber_g"],
            "appropriate",
        )
        self.assertEqual(
            assess_nutrition(nutrients(fiber_g=3), confidence())["statuses"]["fiber_g"],
            "low",
        )
        low = assess_nutrition(nutrients(fiber_g=2.9), confidence())
        self.assertIn("add_vegetables", low["suggestion_keys"])

    def test_sodium_uses_667_and_850_mg_boundaries(self):
        appropriate = assess_nutrition(nutrients(sodium_mg=667), confidence())
        elevated = assess_nutrition(nutrients(sodium_mg=668), confidence())
        high = assess_nutrition(nutrients(sodium_mg=851), confidence())
        self.assertEqual(appropriate["statuses"]["sodium_mg"], "appropriate")
        self.assertEqual(elevated["statuses"]["sodium_mg"], "high")
        self.assertEqual(high["statuses"]["sodium_mg"], "high")
        self.assertGreater(elevated["score"], high["score"])

    def test_sugar_penalty_requires_medium_or_high_confidence(self):
        low_confidence = assess_nutrition(
            nutrients(sugar_g=25),
            confidence(sugar_g="low"),
        )
        high_confidence = assess_nutrition(
            nutrients(sugar_g=25),
            confidence(sugar_g="high"),
        )
        self.assertGreater(low_confidence["score"], high_confidence["score"])

    def test_missing_values_are_indeterminate_not_zero(self):
        result = assess_nutrition(
            nutrients(fiber_g=None, sugar_g=None, sodium_mg=None),
            confidence(),
        )
        self.assertEqual(result["statuses"]["fiber_g"], "indeterminate")
        self.assertEqual(result["statuses"]["sugar_g"], "indeterminate")
        self.assertEqual(result["statuses"]["sodium_mg"], "indeterminate")

    def test_low_overall_confidence_suppresses_score(self):
        result = assess_nutrition(nutrients(), confidence(overall="low"))
        self.assertIsNone(result["score"])
        self.assertEqual(result["tier"], "indeterminate")
        self.assertTrue(result["insufficient_data"])

    def test_calories_plus_all_three_macros_are_required(self):
        result = assess_nutrition(
            nutrients(fat_g=None),
            confidence(),
        )
        self.assertIsNone(result["score"])
        self.assertEqual(result["tier"], "indeterminate")
        self.assertTrue(result["insufficient_data"])

    def test_score_is_clamped_and_repeatable(self):
        input_values = nutrients(
            calories_kcal=1600,
            protein_g=5,
            carbs_g=30,
            fat_g=130,
            fiber_g=0,
            sugar_g=80,
            sodium_mg=3500,
        )
        first = assess_nutrition(input_values, confidence(sugar_g="high"))
        second = assess_nutrition(input_values, confidence(sugar_g="high"))
        self.assertGreaterEqual(first["score"], 0)
        self.assertLessEqual(first["score"], 100)
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
python -m unittest tests.test_nutrition -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'lib.nutrition'`.

- [ ] **Step 3: Implement the minimal deterministic evaluator**

Create empty `lib/__init__.py` and `tests/__init__.py` files.

Create `lib/nutrition.py` with these public and private contracts:

```python
from __future__ import annotations

from collections.abc import Mapping
from typing import Any

MACRO_RANGES = {
    "protein_g": (13.0, 20.0),
    "fat_g": (20.0, 30.0),
    "carbs_g": (50.0, 65.0),
}
MACRO_KCAL_PER_GRAM = {
    "protein_g": 4.0,
    "fat_g": 9.0,
    "carbs_g": 4.0,
}


def _number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    return numeric if numeric >= 0 else None


def _macro_ratios(nutrients: Mapping[str, Any]) -> dict[str, float] | None:
    calories = {
        key: _number(nutrients.get(key))
        for key in MACRO_KCAL_PER_GRAM
    }
    if any(value is None for value in calories.values()):
        return None
    derived = {
        key: calories[key] * MACRO_KCAL_PER_GRAM[key]
        for key in MACRO_KCAL_PER_GRAM
    }
    total = sum(derived.values())
    if total <= 0:
        return None
    return {key: value / total * 100 for key, value in derived.items()}


def _macro_state(ratio: float, lower: float, upper: float) -> tuple[str, int]:
    if ratio < lower:
        return "low", 6 if lower - ratio <= 5 else 12
    if ratio > upper:
        return "high", 6 if ratio - upper <= 5 else 12
    return "appropriate", 0


def _confidence_for(confidence: Mapping[str, Any], nutrient: str) -> str:
    nutrient_levels = confidence.get("nutrients")
    if not isinstance(nutrient_levels, Mapping):
        return "low"
    level = nutrient_levels.get(nutrient)
    return level if level in {"low", "medium", "high"} else "low"


def assess_nutrition(
    nutrients: Mapping[str, Any],
    confidence: Mapping[str, Any],
) -> dict[str, Any]:
    statuses = {
        key: "indeterminate"
        for key in (
            "calories_kcal",
            "protein_g",
            "carbs_g",
            "fat_g",
            "fiber_g",
            "sugar_g",
            "sodium_mg",
        )
    }
    reasons: list[str] = []
    suggestions: list[str] = []
    score = 100

    ratios = _macro_ratios(nutrients)
    if ratios:
        for key, ratio in ratios.items():
            lower, upper = MACRO_RANGES[key]
            status, penalty = _macro_state(ratio, lower, upper)
            statuses[key] = status
            score -= penalty
            if penalty:
                reasons.append(f"{key}_{status}")

    calories = _number(nutrients.get("calories_kcal"))
    if calories is not None:
        if calories < 450:
            statuses["calories_kcal"] = "low"
            score -= 4 if calories >= 300 else 8
        elif calories > 850:
            statuses["calories_kcal"] = "high"
            score -= 4 if calories <= 1000 else 8
        else:
            statuses["calories_kcal"] = "appropriate"

    fiber = _number(nutrients.get("fiber_g"))
    if fiber is not None:
        if fiber >= 6:
            statuses["fiber_g"] = "appropriate"
        else:
            statuses["fiber_g"] = "low"
            score -= 5 if fiber >= 3 else 10
            reasons.append("fiber_low")
            suggestions.append("add_vegetables")

    sodium = _number(nutrients.get("sodium_mg"))
    if sodium is not None:
        if sodium <= 667:
            statuses["sodium_mg"] = "appropriate"
        else:
            statuses["sodium_mg"] = "high"
            score -= 6 if sodium <= 850 else 12
            reasons.append("sodium_elevated" if sodium <= 850 else "sodium_high")
            suggestions.append("reduce_sauce")

    sugar = _number(nutrients.get("sugar_g"))
    if sugar is not None:
        if sugar <= 8:
            statuses["sugar_g"] = "low"
        elif sugar <= 17:
            statuses["sugar_g"] = "appropriate"
        else:
            statuses["sugar_g"] = "high"
            if _confidence_for(confidence, "sugar_g") in {"medium", "high"}:
                score -= 6
                reasons.append("sugar_high")
                suggestions.append("reduce_sweet_items")

    if statuses["fat_g"] == "high":
        suggestions.append("reduce_fat")
    if statuses["protein_g"] == "low":
        suggestions.append("add_protein")
    if statuses["carbs_g"] in {"low", "high"}:
        suggestions.append("adjust_staple")
    if statuses["calories_kcal"] == "high":
        suggestions.append("reduce_portion")

    macro_values = [
        _number(nutrients.get(key))
        for key in ("protein_g", "carbs_g", "fat_g")
    ]
    macro_denominator = sum(
        value * kcal_per_gram
        for value, kcal_per_gram in zip(macro_values, (4, 4, 9))
        if value is not None
    )
    sufficient = (
        calories is not None
        and all(value is not None for value in macro_values)
        and macro_denominator > 0
        and confidence.get("overall") in {"medium", "high"}
    )
    if not sufficient:
        return {
            "score": None,
            "tier": "indeterminate",
            "statuses": statuses,
            "suggestion_keys": list(dict.fromkeys(suggestions))[:2],
            "scoring_reasons": reasons,
            "insufficient_data": True,
        }

    bounded_score = max(0, min(100, score))
    tier = (
        "balanced"
        if bounded_score >= 80
        else "mostly_balanced"
        if bounded_score >= 60
        else "needs_attention"
    )
    return {
        "score": bounded_score,
        "tier": tier,
        "statuses": statuses,
        "suggestion_keys": list(dict.fromkeys(suggestions))[:2],
        "scoring_reasons": reasons,
        "insufficient_data": False,
    }
```

- [ ] **Step 4: Run the evaluator tests and verify GREEN**

Run:

```bash
python -m unittest tests.test_nutrition -v
```

Expected: 9 tests pass.

- [ ] **Step 5: Review public constants and rule comments**

Add module comments linking the Japanese 2025 and WHO sources and stating that the one-meal ranges are product heuristics. Do not change the tested boundaries.

- [ ] **Step 6: Run the full backend suite**

Run:

```bash
python -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: all discovered tests pass.

- [ ] **Step 7: Commit the evaluator**

```bash
git add -- lib/__init__.py lib/nutrition.py tests/__init__.py tests/test_nutrition.py
git commit -m "feat: add deterministic nutrition assessment"
```

---

### Task 3: Expand and Secure the Analysis API with TDD

**Files:**

- Create: `tests/test_analyze.py`
- Modify: `api/analyze.py:1-82`

- [ ] **Step 1: Write failing image-validation and response tests**

Create `tests/test_analyze.py`:

```python
import base64
import unittest

from api.analyze import (
    ImageValidationError,
    ModelAnalysis,
    build_response,
    decode_image,
)


class AnalyzeApiTests(unittest.TestCase):
    def test_decode_image_accepts_supported_data_uri(self):
        payload = base64.b64encode(b"jpeg-bytes").decode("ascii")
        mime_type, image = decode_image(f"data:image/jpeg;base64,{payload}")
        self.assertEqual(mime_type, "image/jpeg")
        self.assertEqual(image, b"jpeg-bytes")

    def test_decode_image_rejects_unsupported_mime_type(self):
        payload = base64.b64encode(b"gif-bytes").decode("ascii")
        with self.assertRaisesRegex(ImageValidationError, "UNSUPPORTED_IMAGE"):
            decode_image(f"data:image/gif;base64,{payload}")

    def test_decode_image_rejects_invalid_base64(self):
        with self.assertRaisesRegex(ImageValidationError, "INVALID_IMAGE"):
            decode_image("data:image/jpeg;base64,not-valid***")

    def test_no_food_response_has_no_fake_values(self):
        model = ModelAnalysis(
            food_detected=False,
            food_names=None,
            portion_grams=None,
            nutrients={
                "calories_kcal": None,
                "protein_g": None,
                "carbs_g": None,
                "fat_g": None,
                "fiber_g": None,
                "sugar_g": None,
                "sodium_mg": None,
            },
            confidence={
                "overall": "low",
                "portion": "low",
                "nutrients": {
                    "calories_kcal": "low",
                    "protein_g": "low",
                    "carbs_g": "low",
                    "fat_g": "low",
                    "fiber_g": "low",
                    "sugar_g": "low",
                    "sodium_mg": "low",
                },
            },
            assumption_keys=[],
        )
        response = build_response(model)
        self.assertFalse(response.food_detected)
        self.assertIsNone(response.assessment.score)
        self.assertTrue(response.assessment.insufficient_data)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
python -m unittest tests.test_analyze -v
```

Expected: FAIL because `ImageValidationError`, `ModelAnalysis`, `build_response`, and `decode_image` do not exist.

- [ ] **Step 3: Replace the API schema with nullable structured models**

Define these models in `api/analyze.py`:

```python
from typing import Literal

ConfidenceLevel = Literal["low", "medium", "high"]
AssumptionKey = Literal[
    "visible_portion_only",
    "portion_estimated",
    "seasoning_estimated",
    "hidden_ingredients_possible",
]


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
    assumption_keys: list[AssumptionKey] = Field(default_factory=list)


class Assessment(BaseModel):
    score: int | None
    tier: Literal[
        "balanced",
        "mostly_balanced",
        "needs_attention",
        "indeterminate",
    ]
    statuses: dict[str, Literal["low", "appropriate", "high", "indeterminate"]]
    suggestion_keys: list[str]
    scoring_reasons: list[str]
    insufficient_data: bool


class AnalyzeResponse(ModelAnalysis):
    assessment: Assessment
```

- [ ] **Step 4: Implement strict image parsing**

Add `import binascii` beside the existing `base64` import, then add:

```python
SUPPORTED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_IMAGE_BYTES = 5 * 1024 * 1024


class ImageValidationError(ValueError):
    pass


def decode_image(image: str) -> tuple[str, bytes]:
    if not image:
        raise ImageValidationError("INVALID_IMAGE")
    mime_type = "image/jpeg"
    encoded = image
    if image.startswith("data:"):
        try:
            header, encoded = image.split(",", 1)
            mime_type = header.split(";", 1)[0].removeprefix("data:")
        except ValueError as error:
            raise ImageValidationError("INVALID_IMAGE") from error
    if mime_type not in SUPPORTED_MIME_TYPES:
        raise ImageValidationError("UNSUPPORTED_IMAGE")
    try:
        decoded = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ImageValidationError("INVALID_IMAGE") from error
    if not decoded or len(decoded) > MAX_IMAGE_BYTES:
        raise ImageValidationError("IMAGE_TOO_LARGE" if decoded else "INVALID_IMAGE")
    return mime_type, decoded
```

- [ ] **Step 5: Compose deterministic assessment**

Add:

```python
from lib.nutrition import assess_nutrition


def build_response(model: ModelAnalysis) -> AnalyzeResponse:
    assessment = assess_nutrition(
        model.nutrients.model_dump(),
        model.confidence.model_dump(),
    )
    return AnalyzeResponse(
        **model.model_dump(),
        assessment=Assessment(**assessment),
    )
```

- [ ] **Step 6: Update the Gemini prompt and provider boundary**

Use a prompt that requires:

```text
Analyze only the visible meal. Return whether food is detected; food names in
Simplified Chinese, Japanese, and English; estimated visible portion weight;
calories, protein, carbohydrates, fat, dietary fibre, sugars, and sodium; overall,
portion, and field-level confidence; and only the allowed assumption keys.
Use null when a value cannot be estimated. Never return zero for missing data.
Sugar and sodium must be low confidence when hidden seasonings prevent a reliable
estimate. Do not return a health score, health tier, nutrient status, diagnosis,
or medical advice.
```

Keep `temperature=0.1`, structured JSON, and the current Gemini model unless the current provider rejects the schema during verified integration.

Remove the wildcard `CORSMiddleware` configuration. Local development already uses the Vite same-origin proxy and production uses `/api/analyze` on the same origin.

Extract the provider call into this function so endpoint error handling remains testable:

```python
def call_gemini(
    api_key: str,
    mime_type: str,
    file_bytes: bytes,
) -> ModelAnalysis:
    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        model="gemini-3-flash-preview",
        contents=[
            types.Part.from_bytes(data=file_bytes, mime_type=mime_type),
            ANALYSIS_PROMPT,
        ],
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=ModelAnalysis,
            temperature=0.1,
        ),
    )
    if response.parsed:
        return ModelAnalysis.model_validate(response.parsed)
    return ModelAnalysis.model_validate_json(response.text)
```

- [ ] **Step 7: Return stable safe errors**

Implement this order in the endpoint:

```python
if not api_key:
    raise HTTPException(
        status_code=503,
        detail={"code": "SERVICE_NOT_CONFIGURED"},
    )

try:
    mime_type, file_bytes = decode_image(request.image)
except ImageValidationError as error:
    raise HTTPException(status_code=400, detail={"code": str(error)}) from error

try:
    model_result = call_gemini(api_key, mime_type, file_bytes)
    return build_response(model_result)
except HTTPException:
    raise
except Exception:
    logger.exception("Food analysis failed")
    raise HTTPException(
        status_code=502,
        detail={"code": "ANALYSIS_FAILED"},
    )
```

Do not log `request.image`, decoded bytes, the API key, or raw provider responses.

- [ ] **Step 8: Run API and backend tests**

Run:

```bash
python -m unittest tests.test_analyze tests.test_nutrition -v
```

Expected: all tests pass.

- [ ] **Step 9: Compile the backend**

Run:

```bash
python -m compileall -q api lib tests
```

Expected: exit 0.

- [ ] **Step 10: Commit the API**

```bash
git add -- api/analyze.py tests/test_analyze.py
git commit -m "feat: expand nutrition analysis api"
```

---

### Task 4: Add Complete Three-Language Types, Messages, and Formatters with TDD

**Files:**

- Create: `src/types.ts`
- Create: `src/i18n.ts`
- Create: `src/i18n.test.ts`
- Create: `src/formatters.ts`
- Create: `src/formatters.test.ts`

- [ ] **Step 1: Define the frontend API contract**

Create `src/types.ts`:

```typescript
export type Locale = 'zh' | 'ja' | 'en';
export type ConfidenceLevel = 'low' | 'medium' | 'high';
export type NutrientStatus = 'low' | 'appropriate' | 'high' | 'indeterminate';
export type AssessmentTier =
  | 'balanced'
  | 'mostly_balanced'
  | 'needs_attention'
  | 'indeterminate';

export type NutrientKey =
  | 'calories_kcal'
  | 'protein_g'
  | 'carbs_g'
  | 'fat_g'
  | 'fiber_g'
  | 'sugar_g'
  | 'sodium_mg';

export interface FoodNames {
  zh: string;
  ja: string;
  en: string;
}

export type NutrientValues = Record<NutrientKey, number | null>;
export type NutrientConfidence = Record<NutrientKey, ConfidenceLevel>;

export interface AnalysisResult {
  food_detected: boolean;
  food_names: FoodNames | null;
  portion_grams: number | null;
  nutrients: NutrientValues;
  confidence: {
    overall: ConfidenceLevel;
    portion: ConfidenceLevel;
    nutrients: NutrientConfidence;
  };
  assumption_keys: string[];
  assessment: {
    score: number | null;
    tier: AssessmentTier;
    statuses: Record<NutrientKey, NutrientStatus>;
    suggestion_keys: string[];
    scoring_reasons: string[];
    insufficient_data: boolean;
  };
}

export type AppState = 'intro' | 'camera' | 'analyzing' | 'result';

export type AppErrorCode =
  | 'CAMERA_DENIED'
  | 'CAPTURE_FAILED'
  | 'INVALID_IMAGE'
  | 'UNSUPPORTED_IMAGE'
  | 'IMAGE_TOO_LARGE'
  | 'NO_FOOD'
  | 'SERVICE_NOT_CONFIGURED'
  | 'ANALYSIS_FAILED'
  | 'NETWORK_ERROR'
  | 'SAVE_FAILED';
```

- [ ] **Step 2: Write failing locale and formatting tests**

Create `src/i18n.test.ts`:

```typescript
import { describe, expect, it } from 'vitest';
import { messages, resolveInitialLocale } from './i18n';

describe('resolveInitialLocale', () => {
  it('prefers a saved supported locale', () => {
    expect(resolveInitialLocale('en', ['ja-JP'])).toBe('en');
  });

  it('uses the first supported device locale', () => {
    expect(resolveInitialLocale(null, ['fr-FR', 'zh-CN', 'en-US'])).toBe('zh');
  });

  it('falls back to Japanese', () => {
    expect(resolveInitialLocale(null, ['fr-FR'])).toBe('ja');
  });
});

describe('message dictionaries', () => {
  it('have exactly the same keys', () => {
    const expected = Object.keys(messages.ja).sort();
    expect(Object.keys(messages.zh).sort()).toEqual(expected);
    expect(Object.keys(messages.en).sort()).toEqual(expected);
  });
});
```

Create `src/formatters.test.ts`:

```typescript
import { describe, expect, it } from 'vitest';
import { formatNutritionValue } from './formatters';

describe('formatNutritionValue', () => {
  it('uses a dash for missing values instead of zero', () => {
    expect(formatNutritionValue(null, 'g', 'ja')).toBe('—');
  });

  it('formats a present value with its unit', () => {
    expect(formatNutritionValue(36, 'g', 'en')).toBe('36 g');
  });

  it('rounds sodium to a whole milligram', () => {
    expect(formatNutritionValue(920.4, 'mg', 'zh')).toBe('920 mg');
  });
});
```

- [ ] **Step 3: Run the tests and verify RED**

Run:

```bash
npm test -- src/i18n.test.ts src/formatters.test.ts
```

Expected: FAIL because `i18n.ts` and `formatters.ts` do not exist.

- [ ] **Step 4: Implement locale resolution and persistence**

Create `src/i18n.ts` with:

```typescript
import type { Locale } from './types';

export const LOCALE_STORAGE_KEY = 'kalories.locale';

const supported = new Set<Locale>(['zh', 'ja', 'en']);

const normalizeLocale = (value: string): Locale | null => {
  const base = value.toLowerCase().split('-')[0] as Locale;
  return supported.has(base) ? base : null;
};

export const resolveInitialLocale = (
  saved: string | null,
  deviceLocales: readonly string[],
): Locale => {
  const savedLocale = saved ? normalizeLocale(saved) : null;
  if (savedLocale) return savedLocale;
  for (const value of deviceLocales) {
    const locale = normalizeLocale(value);
    if (locale) return locale;
  }
  return 'ja';
};

export const persistLocale = (locale: Locale): void => {
  window.localStorage.setItem(LOCALE_STORAGE_KEY, locale);
};

export const documentLanguage = (locale: Locale): string =>
  ({ zh: 'zh-CN', ja: 'ja', en: 'en' })[locale];
```

Define and export a `Messages` interface and complete `messages` dictionaries containing these exact keys:

```typescript
export interface Messages {
  appName: string;
  languageLabel: string;
  introEyebrow: string;
  introTitle: string;
  introBody: string;
  startCamera: string;
  cameraTitle: string;
  cameraHint: string;
  cameraReady: string;
  capture: string;
  analyzingEyebrow: string;
  analyzingTitle: string;
  analyzingBody: string;
  detectedFood: string;
  confidence: string;
  confidenceLow: string;
  confidenceMedium: string;
  confidenceHigh: string;
  estimatedScore: string;
  tierBalanced: string;
  tierMostlyBalanced: string;
  tierNeedsAttention: string;
  tierIndeterminate: string;
  calories: string;
  protein: string;
  carbs: string;
  fat: string;
  fiber: string;
  sugar: string;
  sodium: string;
  portion: string;
  statusLow: string;
  statusAppropriate: string;
  statusHigh: string;
  statusIndeterminate: string;
  sugarLow: string;
  adviceTitle: string;
  suggestionAddVegetables: string;
  suggestionReduceSauce: string;
  suggestionReduceSweetItems: string;
  suggestionReduceFat: string;
  suggestionAddProtein: string;
  suggestionAdjustStaple: string;
  suggestionReducePortion: string;
  saveResult: string;
  retake: string;
  retry: string;
  disclaimer: string;
  referenceBasis: string;
  errorCameraDenied: string;
  errorCaptureFailed: string;
  errorInvalidImage: string;
  errorUnsupportedImage: string;
  errorImageTooLarge: string;
  errorNoFood: string;
  errorServiceNotConfigured: string;
  errorAnalysisFailed: string;
  errorNetwork: string;
  errorSaveFailed: string;
}
```

Use this exact translation content:

```typescript
export const messages: Record<Locale, Messages> = {
  ja: {
    appName: 'Kalories',
    languageLabel: '言語',
    introEyebrow: 'AI 食事分析',
    introTitle: '一枚の写真から、食事をもっと理解する。',
    introBody: 'カロリーと栄養バランスを写真から推定します。',
    startCamera: 'カメラを開く',
    cameraTitle: '食事を撮影',
    cameraHint: '料理全体が枠内に入るようにしてください',
    cameraReady: '分析の準備ができました',
    capture: '撮影する',
    analyzingEyebrow: '栄養を推定中',
    analyzingTitle: '食事を分析しています',
    analyzingBody: '量と栄養バランスを確認しています。',
    detectedFood: '推定した料理',
    confidence: '推定精度',
    confidenceLow: '低',
    confidenceMedium: '中',
    confidenceHigh: '高',
    estimatedScore: '推定スコア',
    tierBalanced: 'バランス良好',
    tierMostlyBalanced: 'おおむね良好',
    tierNeedsAttention: '見直しポイントあり',
    tierIndeterminate: '判定できません',
    calories: 'エネルギー',
    protein: 'たんぱく質',
    carbs: '炭水化物',
    fat: '脂質',
    fiber: '食物繊維',
    sugar: '糖類',
    sodium: 'ナトリウム',
    portion: '推定量',
    statusLow: '少なめ',
    statusAppropriate: '適量',
    statusHigh: '多め',
    statusIndeterminate: '推定不可',
    sugarLow: '低め',
    adviceTitle: 'より良くするには',
    suggestionAddVegetables: '野菜、豆類、海藻などを一品加えてみましょう。',
    suggestionReduceSauce: 'ソースや汁を少なめにすると塩分を抑えられます。',
    suggestionReduceSweetItems: '甘い飲み物やソースを控えめにしてみましょう。',
    suggestionReduceFat: '揚げ物や油の多いソースを少し減らしてみましょう。',
    suggestionAddProtein: '魚、卵、豆腐、豆類などを加えてみましょう。',
    suggestionAdjustStaple: 'ご飯、パン、麺など主食の量を調整してみましょう。',
    suggestionReducePortion: '量や高エネルギーなトッピングを少し減らしてみましょう。',
    saveResult: '結果を保存',
    retake: '撮り直す',
    retry: 'もう一度分析',
    disclaimer: '写真からの推定値です。1食の参考であり、医療上の診断ではありません。',
    referenceBasis: '日本人の食事摂取基準（2025年版）とWHO指針を参考にしています。',
    errorCameraDenied: 'カメラを利用できません。ブラウザの権限を確認してください。',
    errorCaptureFailed: '撮影できませんでした。もう一度お試しください。',
    errorInvalidImage: '画像を読み取れませんでした。',
    errorUnsupportedImage: 'この画像形式には対応していません。',
    errorImageTooLarge: '画像サイズが大きすぎます。',
    errorNoFood: '食事を認識できませんでした。料理全体を撮り直してください。',
    errorServiceNotConfigured: '分析サービスが設定されていません。',
    errorAnalysisFailed: '分析に失敗しました。しばらくしてからお試しください。',
    errorNetwork: 'ネットワークに接続できません。',
    errorSaveFailed: '結果を保存できませんでした。',
  },
  zh: {
    appName: 'Kalories',
    languageLabel: '语言',
    introEyebrow: 'AI 饮食分析',
    introTitle: '一张照片，更了解这一餐。',
    introBody: '通过照片估算热量与营养结构。',
    startCamera: '打开相机',
    cameraTitle: '拍摄这一餐',
    cameraHint: '请让完整食物出现在取景框内',
    cameraReady: '已准备好分析',
    capture: '拍摄',
    analyzingEyebrow: '正在估算营养',
    analyzingTitle: '正在分析这一餐',
    analyzingBody: '正在识别份量与营养结构。',
    detectedFood: '识别到的食物',
    confidence: '估算可信度',
    confidenceLow: '低',
    confidenceMedium: '中',
    confidenceHigh: '高',
    estimatedScore: '估算健康分',
    tierBalanced: '营养均衡',
    tierMostlyBalanced: '基本均衡',
    tierNeedsAttention: '需要关注',
    tierIndeterminate: '无法判断',
    calories: '热量',
    protein: '蛋白质',
    carbs: '碳水化合物',
    fat: '脂肪',
    fiber: '膳食纤维',
    sugar: '糖',
    sodium: '钠',
    portion: '估算份量',
    statusLow: '偏少',
    statusAppropriate: '适量',
    statusHigh: '偏多',
    statusIndeterminate: '无法估算',
    sugarLow: '较低',
    adviceTitle: '让它更均衡',
    suggestionAddVegetables: '可以增加一份蔬菜、豆类或海藻。',
    suggestionReduceSauce: '少放一些酱汁或汤汁，有助于减少钠。',
    suggestionReduceSweetItems: '可以减少甜饮、糖浆或甜味酱汁。',
    suggestionReduceFat: '可以减少油炸食物或高脂酱汁。',
    suggestionAddProtein: '可以增加鱼、蛋、豆腐或豆类。',
    suggestionAdjustStaple: '可以调整米饭、面包或面条等主食的份量。',
    suggestionReducePortion: '可以稍微减少总份量或高热量配料。',
    saveResult: '保存结果',
    retake: '重新拍摄',
    retry: '重新分析',
    disclaimer: '本结果为照片估算，仅作单餐参考，不是医疗诊断。',
    referenceBasis: '参考日本人饮食摄入标准（2025年版）及WHO指南。',
    errorCameraDenied: '无法使用相机，请检查浏览器权限。',
    errorCaptureFailed: '拍摄失败，请重试。',
    errorInvalidImage: '无法读取这张图片。',
    errorUnsupportedImage: '暂不支持这种图片格式。',
    errorImageTooLarge: '图片尺寸过大。',
    errorNoFood: '没有识别到食物，请重新拍摄完整餐食。',
    errorServiceNotConfigured: '分析服务尚未完成配置。',
    errorAnalysisFailed: '分析失败，请稍后重试。',
    errorNetwork: '网络连接失败。',
    errorSaveFailed: '无法保存结果。',
  },
  en: {
    appName: 'Kalories',
    languageLabel: 'Language',
    introEyebrow: 'AI meal analysis',
    introTitle: 'Understand your meal from one photo.',
    introBody: 'Estimate calories and nutritional balance from a photo.',
    startCamera: 'Open camera',
    cameraTitle: 'Photograph your meal',
    cameraHint: 'Keep the whole meal inside the frame',
    cameraReady: 'Ready to analyze',
    capture: 'Take photo',
    analyzingEyebrow: 'Estimating nutrition',
    analyzingTitle: 'Analyzing your meal',
    analyzingBody: 'Checking portion size and nutritional balance.',
    detectedFood: 'Estimated meal',
    confidence: 'Estimate confidence',
    confidenceLow: 'Low',
    confidenceMedium: 'Medium',
    confidenceHigh: 'High',
    estimatedScore: 'Estimated score',
    tierBalanced: 'Balanced',
    tierMostlyBalanced: 'Mostly balanced',
    tierNeedsAttention: 'Needs attention',
    tierIndeterminate: 'Unable to assess',
    calories: 'Calories',
    protein: 'Protein',
    carbs: 'Carbohydrates',
    fat: 'Fat',
    fiber: 'Dietary fibre',
    sugar: 'Sugars',
    sodium: 'Sodium',
    portion: 'Estimated portion',
    statusLow: 'Low',
    statusAppropriate: 'In range',
    statusHigh: 'High',
    statusIndeterminate: 'Unable to estimate',
    sugarLow: 'Lower',
    adviceTitle: 'Make it more balanced',
    suggestionAddVegetables: 'Consider adding vegetables, beans, or seaweed.',
    suggestionReduceSauce: 'Use less sauce or broth to reduce sodium.',
    suggestionReduceSweetItems: 'Reduce sweet drinks, syrups, or sweet sauces.',
    suggestionReduceFat: 'Reduce fried items or high-fat sauces.',
    suggestionAddProtein: 'Add fish, eggs, tofu, or beans.',
    suggestionAdjustStaple: 'Adjust the serving of rice, bread, or noodles.',
    suggestionReducePortion: 'Reduce the portion or energy-dense toppings slightly.',
    saveResult: 'Save result',
    retake: 'Retake',
    retry: 'Analyze again',
    disclaimer: 'Values are estimated from a photo for single-meal reference only. This is not a medical diagnosis.',
    referenceBasis: 'Based on the Dietary Reference Intakes for Japanese (2025) and WHO guidance.',
    errorCameraDenied: 'Camera access is unavailable. Check your browser permissions.',
    errorCaptureFailed: 'The photo could not be captured. Please try again.',
    errorInvalidImage: 'This image could not be read.',
    errorUnsupportedImage: 'This image format is not supported.',
    errorImageTooLarge: 'The image is too large.',
    errorNoFood: 'No meal was detected. Retake the photo with the whole meal visible.',
    errorServiceNotConfigured: 'The analysis service is not configured.',
    errorAnalysisFailed: 'Analysis failed. Please try again shortly.',
    errorNetwork: 'The network connection failed.',
    errorSaveFailed: 'The result could not be saved.',
  },
};
```

- [ ] **Step 5: Implement null-safe formatting**

Create `src/formatters.ts`:

```typescript
import type { Locale, NutrientKey, NutrientStatus } from './types';

const localeTags: Record<Locale, string> = {
  zh: 'zh-CN',
  ja: 'ja-JP',
  en: 'en-US',
};

export const formatNutritionValue = (
  value: number | null,
  unit: 'kcal' | 'g' | 'mg',
  locale: Locale,
): string => {
  if (value === null || !Number.isFinite(value)) return '—';
  const maximumFractionDigits = unit === 'g' && value < 10 ? 1 : 0;
  const formatted = new Intl.NumberFormat(localeTags[locale], {
    maximumFractionDigits,
  }).format(value);
  return `${formatted} ${unit}`;
};

export const statusMessageKey = (
  nutrient: NutrientKey,
  status: NutrientStatus,
): string => {
  if (nutrient === 'sugar_g' && status === 'low') return 'sugarLow';
  return {
    low: 'statusLow',
    appropriate: 'statusAppropriate',
    high: 'statusHigh',
    indeterminate: 'statusIndeterminate',
  }[status];
};
```

- [ ] **Step 6: Run locale and formatter tests**

Run:

```bash
npm test -- src/i18n.test.ts src/formatters.test.ts
npm run lint
```

Expected: all tests and TypeScript pass.

- [ ] **Step 7: Commit localization foundations**

```bash
git add -- src/types.ts src/i18n.ts src/i18n.test.ts src/formatters.ts src/formatters.test.ts
git commit -m "feat: add three-language nutrition contract"
```

---

### Task 5: Build the Apple-Style Continuous Result Page and Screens with TDD

**Files:**

- Create: `src/components/LanguageSwitcher.tsx`
- Create: `src/screens/IntroScreen.tsx`
- Create: `src/screens/CameraScreen.tsx`
- Create: `src/screens/AnalyzingScreen.tsx`
- Create: `src/screens/ResultScreen.tsx`
- Create: `src/screens/ResultScreen.test.tsx`
- Modify: `src/index.css:1`

- [ ] **Step 1: Write the failing result-page contract**

Create `src/screens/ResultScreen.test.tsx` using `renderToStaticMarkup`:

```tsx
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { messages } from '../i18n';
import type { AnalysisResult } from '../types';
import { ResultScreen } from './ResultScreen';

const fixture: AnalysisResult = {
  food_detected: true,
  food_names: {
    zh: '烤鲑鱼套餐',
    ja: '焼き鮭定食',
    en: 'Grilled salmon set',
  },
  portion_grams: 420,
  nutrients: {
    calories_kcal: 640,
    protein_g: 34,
    carbs_g: 68,
    fat_g: 24,
    fiber_g: 8.4,
    sugar_g: 12,
    sodium_mg: 980,
  },
  confidence: {
    overall: 'high',
    portion: 'medium',
    nutrients: {
      calories_kcal: 'high',
      protein_g: 'high',
      carbs_g: 'medium',
      fat_g: 'medium',
      fiber_g: 'medium',
      sugar_g: 'low',
      sodium_mg: 'low',
    },
  },
  assumption_keys: [],
  assessment: {
    score: 64,
    tier: 'mostly_balanced',
    statuses: {
      calories_kcal: 'appropriate',
      protein_g: 'high',
      carbs_g: 'low',
      fat_g: 'high',
      fiber_g: 'appropriate',
      sugar_g: 'appropriate',
      sodium_mg: 'high',
    },
    suggestion_keys: ['reduce_sauce', 'adjust_staple'],
    scoring_reasons: [
      'protein_g_high',
      'fat_g_high',
      'carbs_g_low',
      'sodium_high',
    ],
    insufficient_data: false,
  },
};

describe('ResultScreen', () => {
  it('renders every required result section on one page', () => {
    const html = renderToStaticMarkup(
      <ResultScreen
        locale="ja"
        text={messages.ja}
        data={fixture}
        capturedImage="data:image/jpeg;base64,Zm9v"
        onRetry={() => undefined}
        onRetake={() => undefined}
        onSaveError={() => undefined}
      />,
    );
    expect(html).toContain('焼き鮭定食');
    expect(html).toContain('64');
    for (const value of ['640', '34', '68', '24', '8.4', '12', '980', '420']) {
      expect(html).toContain(value);
    }
    expect(html).toContain(messages.ja.disclaimer);
    expect(html).not.toContain('role="tab"');
  });

  it('renders missing values as a dash rather than zero', () => {
    const missing = {
      ...fixture,
      nutrients: { ...fixture.nutrients, sugar_g: null },
    };
    const html = renderToStaticMarkup(
      <ResultScreen
        locale="en"
        text={messages.en}
        data={missing}
        capturedImage={null}
        onRetry={() => undefined}
        onRetake={() => undefined}
        onSaveError={() => undefined}
      />,
    );
    expect(html).toContain('—');
  });
});
```

- [ ] **Step 2: Run the result test and verify RED**

Run:

```bash
npm test -- src/screens/ResultScreen.test.tsx
```

Expected: FAIL because `ResultScreen.tsx` does not exist.

- [ ] **Step 3: Build the language switcher**

Implement an accessible segmented control:

```tsx
import type { Locale } from '../types';

const options: Array<{ locale: Locale; label: string }> = [
  { locale: 'zh', label: '中文' },
  { locale: 'ja', label: '日本語' },
  { locale: 'en', label: 'EN' },
];

export function LanguageSwitcher({
  locale,
  label,
  onChange,
}: {
  locale: Locale;
  label: string;
  onChange: (locale: Locale) => void;
}) {
  return (
    <div className="language-switcher" role="group" aria-label={label}>
      {options.map((option) => (
        <button
          type="button"
          key={option.locale}
          className={locale === option.locale ? 'is-active' : undefined}
          aria-pressed={locale === option.locale}
          onClick={() => onChange(option.locale)}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}
```

- [ ] **Step 4: Build intro, camera, and analysis screens**

Each screen accepts already-localized `text`. The camera screen:

- owns the `Webcam` ref;
- calls `onCapture(image)` when a screenshot exists;
- calls `onError('CAPTURE_FAILED')` when it does not;
- calls `onError('CAMERA_DENIED')` from `onUserMediaError`;
- contains no `alert`;
- uses a real `<button aria-label={text.capture}>` for the shutter.

The analyzing screen uses the captured image, a localized title/body, and a CSS progress indicator. CSS animations use media queries to respect reduced motion.

- [ ] **Step 5: Build the continuous result screen**

Implement these sections in this exact DOM order inside one `<main className="result-page">`:

```tsx
<header className="result-hero" />
<section className="result-summary" />
<section className="energy-summary" />
<section className="macro-list" />
<section className="secondary-nutrients" />
{/* Render only when at least one known localized suggestion is visible. */}
<section className="advice-card" />
<footer className="result-footer" />
```

Use:

- `data.food_names?.[locale]` for instant language switching;
- `formatNutritionValue` for every value;
- `statusMessageKey` for context-sensitive status text;
- `data.confidence.nutrients[key]` beside every nutrient;
- only the four approved assumption keys mapped to localized copy inside the footer before the reference note;
- `data.assessment.suggestion_keys.slice(0, 2)` for advice;
- `html2canvas` only from the save button handler;
- `onSaveError('SAVE_FAILED')` instead of `alert`;
- `onRetake` without forcing a save;
- `onRetry` when `food_detected` is false or assessment is indeterminate.

Do not add tabs, dialogs, accordions, or secondary routes.

The score decoder and deterministic evaluator must both require calories plus protein, carbohydrates, and fat, with a positive macro-energy denominator and medium/high overall confidence. A partially observed macro profile is always indeterminate and must never be presented as a scored result.

- [ ] **Step 6: Replace the visual system**

Replace `src/index.css` with Tailwind import plus focused custom classes:

```css
@import "tailwindcss";

:root {
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display",
    "SF Pro Text", "Hiragino Sans", "Yu Gothic UI", sans-serif;
  color: #1d1d1f;
  background: #f5f5f7;
  font-synthesis: none;
  text-rendering: optimizeLegibility;
}

* {
  box-sizing: border-box;
}

html {
  background: #f5f5f7;
}

body {
  margin: 0;
  min-width: 320px;
  min-height: 100vh;
  background:
    radial-gradient(circle at 50% -15%, rgba(0, 122, 255, 0.1), transparent 34rem),
    #f5f5f7;
}

button {
  font: inherit;
}

.glass {
  border: 1px solid rgba(255, 255, 255, 0.72);
  background: rgba(255, 255, 255, 0.76);
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.08);
  backdrop-filter: blur(28px) saturate(150%);
}

.result-page {
  width: min(100%, 46rem);
  min-height: 100vh;
  margin: 0 auto;
  padding: max(1rem, env(safe-area-inset-top)) 1rem
    max(2rem, env(safe-area-inset-bottom));
}

@media (min-width: 760px) {
  .result-page {
    padding-inline: 2rem;
  }
}

@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    scroll-behavior: auto !important;
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

Add the remaining named classes used by the screens with:

- minimum 44px touch targets;
- 16–28px corner radii;
- semantic green, amber, blue, and neutral status styling;
- text labels in addition to colour;
- no horizontal overflow at 320px;
- desktop max width and two-column grouping only where reading order remains unchanged.

- [ ] **Step 7: Run result-page tests and type checking**

Run:

```bash
npm test -- src/screens/ResultScreen.test.tsx
npm run lint
```

Expected: tests and TypeScript pass.

- [ ] **Step 8: Commit the screens**

```bash
git add -- src/components/LanguageSwitcher.tsx src/screens src/index.css
git commit -m "feat: add apple-style nutrition screens"
```

---

### Task 6: Wire App State, Retry, Locales, API Errors, and Key Isolation with TDD

**Files:**

- Create: `src/api.ts`
- Create: `src/api.test.ts`
- Modify: `src/App.tsx:1-357`
- Modify: `vite.config.ts:1-30`

- [ ] **Step 1: Write failing API-client tests**

Create `src/api.test.ts`:

```typescript
import { afterEach, describe, expect, it, vi } from 'vitest';
import { analyzeImage, AnalysisApiError } from './api';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('analyzeImage', () => {
  it('returns a typed JSON result', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ food_detected: true }),
      }),
    );
    await expect(analyzeImage('data:image/jpeg;base64,Zm9v')).resolves.toMatchObject({
      food_detected: true,
    });
  });

  it('maps a stable API detail code', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        json: async () => ({ detail: { code: 'INVALID_IMAGE' } }),
      }),
    );
    await expect(analyzeImage('bad')).rejects.toMatchObject({
      code: 'INVALID_IMAGE',
    });
  });

  it('maps a rejected request to a network error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('offline')));
    await expect(analyzeImage('image')).rejects.toEqual(
      new AnalysisApiError('NETWORK_ERROR'),
    );
  });
});
```

- [ ] **Step 2: Run the API-client test and verify RED**

Run:

```bash
npm test -- src/api.test.ts
```

Expected: FAIL because `api.ts` does not exist.

- [ ] **Step 3: Implement the typed API client**

Create `src/api.ts`:

```typescript
import type { AnalysisResult, AppErrorCode } from './types';

const knownCodes = new Set<AppErrorCode>([
  'INVALID_IMAGE',
  'UNSUPPORTED_IMAGE',
  'IMAGE_TOO_LARGE',
  'SERVICE_NOT_CONFIGURED',
  'ANALYSIS_FAILED',
]);

export class AnalysisApiError extends Error {
  constructor(public readonly code: AppErrorCode) {
    super(code);
    this.name = 'AnalysisApiError';
  }
}

export async function analyzeImage(image: string): Promise<AnalysisResult> {
  let response: Response;
  try {
    response = await fetch('/api/analyze', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image }),
    });
  } catch {
    throw new AnalysisApiError('NETWORK_ERROR');
  }

  if (!response.ok) {
    let code: AppErrorCode = 'ANALYSIS_FAILED';
    try {
      const body = await response.json();
      const candidate = body?.detail?.code as AppErrorCode;
      if (knownCodes.has(candidate)) code = candidate;
    } catch {
      // Keep the safe fallback code.
    }
    throw new AnalysisApiError(code);
  }

  return (await response.json()) as AnalysisResult;
}
```

- [ ] **Step 4: Run API-client tests and verify GREEN**

Run:

```bash
npm test -- src/api.test.ts
```

Expected: 3 tests pass.

- [ ] **Step 5: Replace `App.tsx` with the typed state machine**

Implement state with:

```typescript
const [appState, setAppState] = useState<AppState>('intro');
const [locale, setLocale] = useState<Locale>(() =>
  resolveInitialLocale(
    window.localStorage.getItem(LOCALE_STORAGE_KEY),
    navigator.languages,
  ),
);
const [analysisResult, setAnalysisResult] = useState<AnalysisResult | null>(null);
const [errorCode, setErrorCode] = useState<AppErrorCode | null>(null);
const [capturedImage, setCapturedImage] = useState<string | null>(null);
```

Use one `runAnalysis(image)` function for capture and retry. It:

1. keeps `capturedImage`;
2. enters `analyzing`;
3. clears the previous error;
4. calls `analyzeImage`;
5. maps `food_detected === false` to a result screen with `NO_FOOD`;
6. otherwise stores the result and enters `result`;
7. on `AnalysisApiError`, stores `error.code` and returns to `camera`.

Language change calls only:

```typescript
const changeLocale = (nextLocale: Locale) => {
  setLocale(nextLocale);
  persistLocale(nextLocale);
};
```

It must not call `runAnalysis`.

Render `LanguageSwitcher` above every state, pass `messages[locale]` to all screens, preserve the captured image for retry, and clear result/image only on retake.

- [ ] **Step 6: Remove frontend API-key injection**

Change `vite.config.ts` to:

```typescript
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '.'),
    },
  },
  server: {
    hmr: process.env.DISABLE_HMR !== 'true',
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8000',
        changeOrigin: true,
      },
    },
  },
});
```

There must be no `loadEnv`, `define`, `process.env.GEMINI_API_KEY`, or `VITE_GEMINI_API_KEY` browser substitution.

- [ ] **Step 7: Run all frontend checks**

Run:

```bash
npm test
npm run lint
npm run build
```

Expected: all tests pass, TypeScript exits 0, and Vite builds `dist/`.

- [ ] **Step 8: Prove the built browser bundle contains no API key identifier**

Run:

```bash
rg -n "GEMINI_API_KEY|sk-[A-Za-z0-9_-]+" dist || true
```

Expected: no matches.

- [ ] **Step 9: Commit orchestration and security**

```bash
git add -- src/api.ts src/api.test.ts src/App.tsx vite.config.ts
git commit -m "feat: wire localized nutrition analysis flow"
```

---

### Task 7: Documentation, Full Verification, and Browser Acceptance

**Files:**

- Modify: `README.md:1-20`
- Verify: all changed files
- Optional local artifact: `output/playwright/kalories-result.png`

- [ ] **Step 1: Rewrite local setup and product boundary**

Update `README.md` with:

```markdown
# Kalories

Kalories is a camera-first meal estimator. It estimates calories, protein,
carbohydrates, fat, dietary fibre, sugars, and sodium from a food photo, then
applies a deterministic Japan-first single-meal heuristic.

The result is an estimate, not a measurement or medical diagnosis. Hidden oils,
sauces, sugar, sodium, fillings, and portion size can materially change the result.

## Local development

1. Install frontend dependencies: `npm install`
2. Install Python dependencies: `python -m pip install -r requirements.txt`
3. Add `GEMINI_API_KEY` to `.env`
4. Start the API:
   `python -m uvicorn api.analyze:app --host 127.0.0.1 --port 8000`
5. Start the UI in another terminal: `npm run dev`
6. Open `http://127.0.0.1:3000`

## Verification

- Frontend tests: `npm test`
- TypeScript: `npm run lint`
- Production build: `npm run build`
- Backend tests: `python -m unittest discover -s tests -p 'test_*.py' -v`

Supported UI languages are Japanese, Simplified Chinese, and English. The first
visit follows a supported device language and otherwise defaults to Japanese.
```

Include links to the approved Japanese 2025 and WHO sources from the design spec.

- [ ] **Step 2: Run the full automated verification fresh**

Run:

```bash
npm test
npm run lint
npm run build
python -m unittest discover -s tests -p 'test_*.py' -v
python -m compileall -q api lib tests
```

Expected: every command exits 0 with no failed test.

- [ ] **Step 3: Check secret availability without printing it**

Run:

```bash
if [ -n "${GEMINI_API_KEY:-}" ]; then
  echo "GEMINI_API_KEY=available"
elif [ -s .env ]; then
  echo "GEMINI_API_KEY=check-local-env"
else
  echo "GEMINI_API_KEY=absent"
fi
```

Expected: only availability state is printed. Never print the key.

- [ ] **Step 4: Start API and UI**

Run API in one PTY:

```bash
python -m uvicorn api.analyze:app --host 127.0.0.1 --port 8000
```

Run UI in another PTY:

```bash
npm run dev
```

Expected:

- API listens on `127.0.0.1:8000`.
- UI listens on `0.0.0.0:3000`.
- `curl -I http://127.0.0.1:3000` returns HTTP 200.

- [ ] **Step 5: Verify the real browser prerequisites**

Run:

```bash
command -v npx >/dev/null 2>&1
```

Expected: exit 0.

Set the Playwright wrapper path without reusing system variables:

```bash
PWCLI=/Users/zhanglonglong/.codex/skills/playwright/scripts/playwright_cli.sh
```

- [ ] **Step 6: Verify intro and all three languages in a real browser**

Run:

```bash
"$PWCLI" open http://127.0.0.1:3000 --headed
"$PWCLI" snapshot
```

Expected: Apple-inspired intro screen with the three-language control.

Use snapshot refs to select Japanese, Chinese, and English, taking a fresh snapshot after each change. Expected: visible intro content changes immediately and the active selector state follows the chosen locale.

- [ ] **Step 7: Verify camera and error recovery**

Click the localized start button, re-snapshot, and inspect the camera state.

Expected:

- camera UI is readable and photo-forward;
- shutter is a real button;
- if camera permission is unavailable, the inline localized recovery message appears;
- there is no browser alert.

If the environment contains a usable API key and camera input, capture a real meal photo and verify actual Gemini participation from API logs without exposing the payload or key.

If either prerequisite is absent, explicitly mark live photo analysis `NOT VERIFIED` and continue with deterministic, build, static-result, and error-path checks.

- [ ] **Step 8: Verify continuous result-page rendering**

When live analysis is available, confirm:

- photo and localized name;
- confidence;
- score and written tier;
- calories;
- protein, carbohydrate, fat, fibre, sugar, sodium, and portion;
- statuses;
- no more than two suggestions;
- disclaimer and reference basis;
- save and retake actions;
- one continuous scrollable page with no tabs or secondary result route.

At 390×844 and 1280×900 viewports, verify no horizontal overflow and save:

```bash
"$PWCLI" screenshot --filename output/playwright/kalories-result.png
```

If live analysis is unavailable, use the passing `ResultScreen` static-render test as structural evidence and do not claim live result-page browser verification.

- [ ] **Step 9: Review exact changes**

Run:

```bash
git diff --check
git diff --stat 14510cd..HEAD
git diff 14510cd..HEAD -- . ':(exclude)package-lock.json'
git status --short --branch
```

Expected:

- no whitespace errors;
- no unrelated files;
- `.superpowers/` is ignored;
- only intended changes remain;
- current branch is ahead only by scoped commits.

- [ ] **Step 10: Commit documentation**

```bash
git add -- README.md
git commit -m "docs: document nutrition analysis verification"
```

- [ ] **Step 11: Run final verification after the last commit**

Run:

```bash
npm test &&
npm run lint &&
npm run build &&
python -m unittest discover -s tests -p 'test_*.py' -v &&
python -m compileall -q api lib tests &&
git diff --check &&
git status --short --branch
```

Expected: all verification commands pass. Report the exact test counts, build outcome, browser evidence, live-Gemini status, Git status, remaining photo-estimation limitations, and the next action.

---

## Plan Self-Review

- Every in-scope design requirement maps to Tasks 2–7.
- The plan keeps AI estimation separate from deterministic assessment.
- The API and frontend types use the same snake-case property names.
- Missing values remain nullable through the API, type contract, formatter, and UI.
- Language switching is local frontend state and cannot trigger reanalysis.
- The result-page test explicitly rejects tabs.
- Security verification checks the built bundle, not only source code.
- Live Gemini participation is never inferred from a successful mock, build, or UI render.
- No task adds profiles, history, medical advice, micronutrients, or unrelated refactors.
- Placeholder scan contains no deferred-work markers or unspecified implementation steps.
