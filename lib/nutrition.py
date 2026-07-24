"""Deterministic nutrition assessment for one estimated meal.

The broad nutrition context is informed by the Japanese Dietary Reference
Intakes (https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/kenkou_iryou/kenkou/eiyou/syokuji_kijyun.html),
the WHO healthy-diet fact sheet (https://www.who.int/news-room/fact-sheets/detail/healthy-diet),
and the WHO sodium-reduction fact sheet (https://www.who.int/news-room/fact-sheets/detail/sodium-reduction).
These one-meal thresholds are app heuristics, not medical or official one-meal
standards.
"""

from __future__ import annotations

from collections.abc import Mapping
from math import isfinite
from typing import Any


MACRO_RANGES = {
    "protein_g": (13.0, 20.0),
    "fat_g": (20.0, 30.0),
    "carbs_g": (50.0, 65.0),
}

_FIELDS = (
    "calories_kcal",
    "protein_g",
    "carbs_g",
    "fat_g",
    "fiber_g",
    "sugar_g",
    "sodium_mg",
)
_MACRO_KCAL_PER_GRAM = {"protein_g": 4.0, "fat_g": 9.0, "carbs_g": 4.0}
_SUGGESTION_PRIORITY = (
    "add_vegetables",
    "reduce_sauce",
    "reduce_sweet_items",
    "reduce_fat",
    "add_protein",
    "adjust_staple",
    "reduce_portion",
)
_SUGGESTION_PRIORITY_INDEX = {
    key: index for index, key in enumerate(_SUGGESTION_PRIORITY)
}


def assess_nutrition(
    nutrients: Mapping[str, Any], confidence: Mapping[str, Any]
) -> dict[str, Any]:
    """Assess available meal estimates without calling providers or applying medical rules."""
    values = {
        field: _number(nutrients.get(field) if isinstance(nutrients, Mapping) else None)
        for field in _FIELDS
    }
    overall_confidence = _confidence(
        confidence.get("overall") if isinstance(confidence, Mapping) else None
    )
    statuses = {field: "indeterminate" for field in _FIELDS}
    reasons: list[str] = []
    suggestion_candidates: list[tuple[str, int]] = []
    penalties: list[int] = []

    calorie_status, calorie_penalty, calorie_reason, calorie_suggestion = _calories(
        values["calories_kcal"]
    )
    statuses["calories_kcal"] = calorie_status
    _record(
        penalties,
        reasons,
        suggestion_candidates,
        calorie_penalty,
        calorie_reason,
        calorie_suggestion,
    )

    macro_statuses, macro_outcomes = _macros(values)
    statuses.update(macro_statuses)
    for penalty, reason, suggestion in macro_outcomes:
        _record(penalties, reasons, suggestion_candidates, penalty, reason, suggestion)

    fiber_status, fiber_penalty, fiber_reason, fiber_suggestion = _fiber(values["fiber_g"])
    statuses["fiber_g"] = fiber_status
    _record(
        penalties,
        reasons,
        suggestion_candidates,
        fiber_penalty,
        fiber_reason,
        fiber_suggestion,
    )

    sugar_status, sugar_penalty, sugar_reason, sugar_suggestion = _sugar(
        values["sugar_g"], _nutrient_confidence(confidence, "sugar_g")
    )
    statuses["sugar_g"] = sugar_status
    _record(
        penalties,
        reasons,
        suggestion_candidates,
        sugar_penalty,
        sugar_reason,
        sugar_suggestion,
    )

    sodium_status, sodium_penalty, sodium_reason, sodium_suggestion = _sodium(
        values["sodium_mg"]
    )
    statuses["sodium_mg"] = sodium_status
    _record(
        penalties,
        reasons,
        suggestion_candidates,
        sodium_penalty,
        sodium_reason,
        sodium_suggestion,
    )

    all_macros_present = all(values[field] is not None for field in MACRO_RANGES)
    macro_denominator = _macro_energy_denominator(values)
    score_is_available = (
        values["calories_kcal"] is not None
        and all_macros_present
        and macro_denominator is not None
        and macro_denominator > 0
        and overall_confidence in {"medium", "high"}
    )
    suggestion_keys = _select_suggestions(suggestion_candidates)
    if not score_is_available:
        return {
            "score": None,
            "tier": "indeterminate",
            "statuses": statuses,
            "suggestion_keys": suggestion_keys,
            "scoring_reasons": reasons,
            "insufficient_data": True,
        }

    score = max(0, min(100, 100 - sum(penalties)))
    return {
        "score": score,
        "tier": _tier(score),
        "statuses": statuses,
        "suggestion_keys": suggestion_keys,
        "scoring_reasons": reasons,
        "insufficient_data": False,
    }


def _number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    try:
        number = float(value)
    except (OverflowError, ValueError):
        return None
    return number if isfinite(number) and number >= 0 else None


def _confidence(value: Any) -> str:
    return value if isinstance(value, str) and value in {"low", "medium", "high"} else "low"


def _nutrient_confidence(confidence: Mapping[str, Any], field: str) -> str:
    if not isinstance(confidence, Mapping):
        return "low"
    nutrients = confidence.get("nutrients")
    if not isinstance(nutrients, Mapping):
        return "low"
    return _confidence(nutrients.get(field))


def _record(
    penalties: list[int],
    reasons: list[str],
    suggestion_candidates: list[tuple[str, int]],
    penalty: int,
    reason: str | None,
    suggestion: str | None,
) -> None:
    if penalty:
        penalties.append(penalty)
        if reason:
            reasons.append(reason)
        if suggestion:
            suggestion_candidates.append((suggestion, penalty))


def _select_suggestions(candidates: list[tuple[str, int]]) -> list[str]:
    severities: dict[str, int] = {}
    for key, severity in candidates:
        severities[key] = max(severity, severities.get(key, 0))
    return [
        key
        for key, _ in sorted(
            severities.items(),
            key=lambda item: (-item[1], _SUGGESTION_PRIORITY_INDEX[item[0]]),
        )
    ][:2]


def _calories(value: float | None) -> tuple[str, int, str | None, str | None]:
    if value is None:
        return "indeterminate", 0, None, None
    if value < 450:
        return "low", 4 if value >= 300 else 8, "calories_low", "adjust_staple"
    if value > 850:
        return "high", 4 if value <= 1000 else 8, "calories_high", "reduce_portion"
    return "appropriate", 0, None, None


def _macros(
    values: Mapping[str, float | None],
) -> tuple[dict[str, str], list[tuple[int, str | None, str | None]]]:
    statuses = {field: "indeterminate" for field in MACRO_RANGES}
    macro_values = [values[field] for field in MACRO_RANGES]
    if any(value is None for value in macro_values):
        return statuses, []

    denominator = _macro_energy_denominator(values)
    if denominator is None or denominator == 0:
        return statuses, []
    macro_energy = {
        field: values[field] * _MACRO_KCAL_PER_GRAM[field] for field in MACRO_RANGES
    }

    outcomes: list[tuple[int, str | None, str | None]] = []
    for field, (lower, upper) in MACRO_RANGES.items():
        ratio = macro_energy[field] / denominator * 100
        if ratio < lower:
            statuses[field] = "low"
            deviation = lower - ratio
            outcomes.append((_macro_penalty(deviation), f"{field}_low", _macro_advice(field, "low")))
        elif ratio > upper:
            statuses[field] = "high"
            deviation = ratio - upper
            outcomes.append((_macro_penalty(deviation), f"{field}_high", _macro_advice(field, "high")))
        else:
            statuses[field] = "appropriate"
    return statuses, outcomes


def _macro_energy_denominator(values: Mapping[str, float | None]) -> float | None:
    present_macro_fields = [
        field for field in MACRO_RANGES if values[field] is not None
    ]
    if not present_macro_fields:
        return None
    denominator = sum(
        values[field] * _MACRO_KCAL_PER_GRAM[field] for field in present_macro_fields
    )
    return denominator if isfinite(denominator) else None


def _macro_penalty(deviation: float) -> int:
    return 6 if deviation <= 5 else 12


def _macro_advice(field: str, status: str) -> str | None:
    if field == "protein_g" and status == "low":
        return "add_protein"
    if field == "fat_g" and status == "high":
        return "reduce_fat"
    if field == "carbs_g":
        return "adjust_staple"
    return None


def _fiber(value: float | None) -> tuple[str, int, str | None, str | None]:
    if value is None:
        return "indeterminate", 0, None, None
    if value >= 6:
        return "appropriate", 0, None, None
    if value >= 3:
        return "low", 5, "fiber_low", "add_vegetables"
    return "low", 10, "fiber_low", "add_vegetables"


def _sugar(
    value: float | None, confidence: str
) -> tuple[str, int, str | None, str | None]:
    if value is None:
        return "indeterminate", 0, None, None
    if value <= 8:
        return "low", 0, None, None
    if value <= 17:
        return "appropriate", 0, None, None
    if confidence in {"medium", "high"}:
        return "high", 6, "sugar_high", "reduce_sweet_items"
    return "high", 0, None, None


def _sodium(value: float | None) -> tuple[str, int, str | None, str | None]:
    if value is None:
        return "indeterminate", 0, None, None
    if value <= 667:
        return "appropriate", 0, None, None
    if value <= 850:
        return "high", 6, "sodium_elevated", "reduce_sauce"
    return "high", 12, "sodium_high", "reduce_sauce"


def _tier(score: int) -> str:
    if score >= 80:
        return "balanced"
    if score >= 60:
        return "mostly_balanced"
    return "needs_attention"
