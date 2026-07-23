# Kalories Apple-Style Nutrition and Health Analysis Design

Date: 2026-07-24

## 1. Objective

Turn the current calorie camera into a trustworthy single-meal nutrition assistant:

1. Capture a food photo.
2. Estimate calories and seven nutrition values.
3. Explain whether each value appears low, appropriate, or high.
4. Show an estimated health score plus a plain-language conclusion.
5. Provide one or two practical improvements.
6. Present the full result in one continuous page in Chinese, Japanese, or English.

The real job is not to show more numbers. It is to help a user understand what the meal likely contains, what deserves attention, and what to change next.

## 2. First-Principles Rules

- Understanding before persuasion: show the conclusion first, then the evidence.
- Risk control before surface output: never represent photo estimates as measurements or medical diagnosis.
- Maintainability before novelty: separate AI estimation, deterministic assessment, localization, and presentation.
- Evidence before completion: the feature requires automated tests, a production build, browser verification, diff review, and Git status evidence.

## 3. Scope

### In scope

- Apple-inspired visual redesign of the intro, camera, analysis, result, and error states.
- One continuous result page. Small screens may scroll; there are no result tabs, secondary detail pages, or result modals.
- Nutrition estimates for:
  - energy in kcal;
  - protein in g;
  - carbohydrates in g;
  - fat in g;
  - dietary fibre in g;
  - sugars in g;
  - sodium in mg.
- Estimated portion weight, overall confidence, field-level confidence, and visible assumptions.
- A deterministic 0–100 estimated health score.
- A three-level conclusion: balanced, mostly balanced, or needs attention.
- Per-nutrient state: low, appropriate, high, or indeterminate.
- One or two deterministic improvement suggestions.
- Chinese, Japanese, and English UI and result names.
- Initial language from device preferences; unsupported languages fall back to Japanese.
- Locally persisted manual language selection.
- Existing Gemini provider and existing camera-first workflow.

### Out of scope

- User profiles, age, sex, height, weight, activity level, or body-composition input.
- Personalised calorie targets, weight-loss plans, muscle-gain plans, or disease-specific advice.
- Medical diagnosis or replacing a dietitian or physician.
- Vitamin and mineral estimates beyond sodium.
- Accounts, cloud history, meal logging, or cross-device sync.
- Live trading, finance, or investment functionality.
- Changing the AI provider.
- Gallery upload, barcode scanning, packaged-food label OCR, or manual food editing.

## 4. Reference Basis and Product Boundary

The primary reference is Japan's Ministry of Health, Labour and Welfare, *Dietary Reference Intakes for Japanese (2025)*, which applies from fiscal year 2025 through fiscal year 2029:

- <https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/kenkou_iryou/kenkou/eiyou/syokuji_kijyun.html>
- <https://www.mhlw.go.jp/stf/newpage_44138.html>

The Japanese authority states that the reference values describe habitual intake, not a direct standard for one day, one meal, or one dish:

- <https://kennet.mhlw.go.jp/information/information/dictionary/food/ye-025>

Japan's Food Balance Guide also says that one unbalanced meal should not by itself be treated as proof of an unbalanced overall diet:

- <https://www.maff.go.jp/j/syokuiku/zissen_navi/balance/features.html>

WHO guidance supplements areas where a single generic Japanese threshold is not available, especially free sugars and sodium:

- <https://www.who.int/news-room/fact-sheets/detail/healthy-diet>
- <https://www.who.int/news-room/fact-sheets/detail/sodium-reduction>

Therefore:

- Every score and state is labelled as a photo-based, single-meal estimate.
- The app calls its thresholds a product heuristic, not an official Japanese one-meal standard.
- It never states that a single meal proves the user's overall diet is healthy or unhealthy.
- Sugar and sodium estimates receive visibly lower confidence when hidden ingredients or seasonings cannot be inferred.

## 5. Chosen Product Experience

The selected direction is "health conclusion first."

### Result-page order

1. Food photo and localized food name.
2. Overall confidence.
3. Estimated 0–100 score and three-level written conclusion.
4. Short explanation of the strongest positive and concern.
5. Estimated calories.
6. Protein, carbohydrate, fat, and fibre cards with status and progress rails.
7. Sugar, sodium, and portion cards with confidence cues.
8. One or two improvement suggestions.
9. Photo-estimate, single-meal, non-medical disclaimer and reference basis.
10. Save-result and retake actions.

All content appears on one continuous result page. Mobile devices may scroll vertically. The design must not hide required content behind tabs, accordions, dialogs, or a secondary route.

### Apple-inspired visual language

- System font stack headed by SF Pro equivalents.
- Light neutral surfaces, restrained semantic colours, generous whitespace, and thin separators.
- Large corner radii, subtle material blur, and soft shadows.
- Clear type hierarchy and large touch targets.
- Motion is brief and functional and respects `prefers-reduced-motion`.
- Status is never communicated by colour alone.
- The camera state remains photo-forward, while the result state prioritises readability over visual effects.

## 6. Language Behaviour

Supported locales:

- `zh`: Simplified Chinese.
- `ja`: Japanese.
- `en`: English.

Resolution order:

1. A previously saved supported locale from local storage.
2. The first supported locale in `navigator.languages`.
3. Japanese fallback.

Manual switching updates the intro, camera, analysis, result, errors, actions, nutrient names, status labels, advice, confidence, and disclaimer immediately. Switching language must not trigger another AI request.

To support instant switching, the AI returns food names in all three languages in one structured response. Deterministic assessment labels and advice are stored as language-neutral keys and localized in the frontend.

## 7. Architecture

### 7.1 AI estimation

Gemini receives the image and a strict structured-response schema. It returns estimation facts only:

- whether food was detected;
- three localized food names;
- estimated portion weight;
- seven nullable nutrition values;
- overall confidence;
- portion confidence;
- field-level confidence;
- short visible assumptions about ingredients or portions.

The model does not return the health score, high/low states, tier, or final improvement advice.

### 7.2 Deterministic assessment

A pure Python nutrition assessment module receives the normalized estimates and returns:

- a 0–100 estimated score when enough data exists;
- a language-neutral tier key;
- a language-neutral status key for each nutrient;
- zero to two language-neutral suggestion keys;
- scoring reasons;
- an `insufficient_data` indicator when assessment is unsafe.

The API composes estimation and assessment into one response. This makes identical nutrition values produce identical conclusions.

### 7.3 Frontend presentation

The React frontend owns:

- app state and camera lifecycle;
- locale resolution and persistence;
- translation dictionaries;
- localized error messages;
- result formatting;
- Apple-style presentation;
- save-as-image and retake actions.

The frontend does not calculate the health score and does not hold the Gemini API key.

### 7.4 API response shape

The response is conceptually:

```json
{
  "food_detected": true,
  "food_names": {
    "zh": "烤鸡胸藜麦碗",
    "ja": "グリルチキンとキヌア",
    "en": "Grilled chicken quinoa bowl"
  },
  "portion_grams": 430,
  "nutrients": {
    "calories_kcal": 486,
    "protein_g": 36,
    "carbs_g": 54,
    "fat_g": 25,
    "fiber_g": 5,
    "sugar_g": 8,
    "sodium_mg": 920
  },
  "confidence": {
    "overall": "medium",
    "portion": "medium",
    "nutrients": {
      "calories_kcal": "medium",
      "protein_g": "medium",
      "carbs_g": "medium",
      "fat_g": "medium",
      "fiber_g": "low",
      "sugar_g": "low",
      "sodium_mg": "low"
    }
  },
  "assumption_keys": ["visible_portion_only", "seasoning_estimated"],
  "assessment": {
    "score": 82,
    "tier": "balanced",
    "statuses": {
      "protein_g": "appropriate",
      "carbs_g": "appropriate",
      "fat_g": "high",
      "fiber_g": "low",
      "sugar_g": "indeterminate",
      "sodium_mg": "high"
    },
    "suggestion_keys": ["reduce_sauce", "add_vegetables"],
    "scoring_reasons": ["macro_balance_good", "sodium_high", "fiber_low"],
    "insufficient_data": false
  }
}
```

All nutrition values are nullable. Missing values remain `null`; they are never rewritten to zero.

## 8. Assessment Heuristic

The heuristic is intentionally simple, deterministic, and documented.

### 8.1 Macro balance

When calories and the three macro values are present, calculate their energy contribution:

- protein: 4 kcal/g;
- carbohydrates: 4 kcal/g;
- fat: 9 kcal/g.

Compare energy ratios with the Japanese 2025 adult ranges:

- protein: 13–20% of energy;
- fat: 20–30% of energy;
- carbohydrates: 50–65% of energy.

Because model-estimated total calories may not exactly equal macro-derived calories, macro ratios use the sum of macro-derived calories as their denominator. If that denominator is invalid, macro states become indeterminate.

### 8.2 Single-meal product targets

The app uses broad one-meal product targets derived from approximately one-third of adult daily guidance:

- calories: 450–850 kcal is the broad neutral band;
- fibre: at least 6 g is appropriate, 3–6 g is low, and less than 3 g is very low;
- sodium: up to 667 mg is appropriate, 668–850 mg is elevated, and above 850 mg is high;
- sugar: up to 8 g is low, 8–17 g is moderate, and above 17 g is high.

These are application heuristics, not official one-meal Japanese thresholds. Sugar uses WHO daily free-sugar guidance as an upper-bound reference, but the model estimates visible total sugars rather than laboratory-measured free sugars. Sugar therefore remains low-confidence unless the image gives unusually clear evidence.

### 8.3 Score

Start at 100. Apply bounded penalties:

- each macro outside its range: 6 points for a small deviation, 12 for a material deviation;
- calories outside the broad band: 4 points, or 8 for a large deviation;
- low fibre: 5 points; very low fibre: 10 points;
- elevated sodium: 6 points; high sodium: 12 points;
- high sugar: at most 6 points and only when sugar confidence is medium or high.

Clamp the score to 0–100.

Tier mapping:

- 80–100: balanced;
- 60–79: mostly balanced;
- 0–59: needs attention.

A score is returned only when calories plus at least two macros are present and overall confidence is not low. Otherwise, `score` is `null`, the tier is `indeterminate`, and the UI explains that there is not enough information.

Confidence does not silently change the score. It is displayed next to the score so the user can interpret it.

## 9. Advice Rules

Advice is deterministic, limited to one or two items, and selected from the largest actionable deviations:

- low fibre → add vegetables, legumes, mushrooms, seaweed, or whole grains;
- high sodium → reduce sauce, soup, processed foods, or salty condiments;
- high fat → reduce fried components, creamy sauces, or visible oils;
- low protein → add fish, eggs, tofu, beans, dairy, or lean meat;
- carbohydrate imbalance → adjust the visible staple portion;
- high sugar → reduce sweet drinks, syrups, desserts, or sweet sauces;
- very high calories → reduce portion size or high-energy toppings.

Suggestions avoid disease claims and respect the food visible in the image. When evidence is low, the wording says "consider" rather than asserting a hidden ingredient is present.

## 10. Error Handling

### No food

- The API returns a typed no-food result rather than fake nutrition values.
- The frontend shows a localized no-food message and offers retake.

### Low confidence

- The UI shows low confidence prominently.
- Missing fields show "unable to estimate."
- Sugar and sodium can be indeterminate even when other nutrients are present.

### Network or model failure

- Keep the captured photo in memory.
- Show a localized inline error.
- Offer "retry analysis" and "retake."
- Do not use browser `alert` for recoverable failures.

### Invalid request

- Reject empty, malformed, unsupported, or oversized image payloads before calling Gemini.
- Return a stable error code; the frontend maps the code to localized text.

### Missing API key

- Return a server configuration error without echoing secret values.
- Keep the key server-side only.

## 11. Security and Privacy Guardrails

- Remove frontend build-time exposure of `GEMINI_API_KEY`.
- Do not log base64 image payloads.
- Do not persist food images or results to the server.
- Store only the selected locale in local storage.
- Keep API errors free of raw provider responses when they could expose internals.
- Preserve the same-origin API flow used in production.

## 12. Files Expected to Change

- `src/App.tsx`
- `src/index.css`
- `src/i18n.ts` or equivalent localization module
- `src/types.ts` or equivalent shared frontend types
- frontend unit-test files
- `api/analyze.py`
- `api/nutrition.py`
- backend unit-test files
- `vite.config.ts`
- `package.json`
- `package-lock.json`
- `.gitignore`
- `README.md` if local verification instructions need correction

No unrelated refactor is in scope.

## 13. Testing Strategy

Implementation follows red-green-refactor.

### Backend unit tests

- balanced representative meal;
- low protein;
- high fat;
- low fibre;
- elevated and high sodium boundaries;
- sugar penalty gated by confidence;
- missing nutrient values;
- insufficient data returns no score;
- score clamps to 0–100;
- identical inputs produce identical assessment.

### Frontend unit tests

- locale resolution from saved preference;
- locale resolution from `navigator.languages`;
- Japanese fallback;
- all required translation keys exist in all three dictionaries;
- formatting preserves null as indeterminate rather than zero;
- language switching does not alter analysis data.

### Static and build checks

```bash
npm run lint
npm test
npm run build
python -m unittest discover -s tests -p 'test_*.py'
```

### Browser verification

- Verify intro, camera, analysis, result, and error states in a real browser.
- Verify Japanese, Chinese, and English switching.
- Verify mobile and desktop viewport layout.
- Verify the result remains one continuous page with all required sections.
- Verify reduced-motion behaviour where applicable.
- Verify save-result and retake actions.
- Record a screenshot under `output/playwright/` when useful.

Actual Gemini participation is verified only when the environment contains a usable server-side key. Without one, model integration remains explicitly unverified even if mocked and deterministic checks pass.

## 14. Acceptance Criteria

- The entire user-visible app follows the approved Apple-inspired design direction.
- The result page contains the photo, localized name, confidence, score, written tier, explanation, calories, seven nutrition estimates, per-item statuses, suggestions, disclaimer, and actions.
- All result content is on one continuous page. Mobile scrolling is allowed.
- Chinese, Japanese, and English cover every user-facing state and can be changed without reanalysis.
- First visit follows a supported device language; unsupported devices fall back to Japanese; manual choice persists locally.
- Japan's 2025 guidance is primary and WHO is supplementary.
- The app explicitly labels thresholds as single-meal product heuristics and the output as non-medical photo estimates.
- Missing values never become zero.
- AI estimates facts; deterministic code calculates score, status, tier, and advice.
- The frontend does not receive the Gemini API key.
- Automated tests, type checking, and production build pass, or any failure is reported without claiming completion.
- Final delivery includes reviewed Git diff, Git status, verification evidence, and remaining limitations.

## 15. Risks and Remaining Limitations

- Portion size is difficult to infer without a scale reference.
- Sauces, oils, fillings, sugar, and sodium can be hidden.
- Food composition differs by recipe and restaurant.
- The score is a product heuristic and cannot determine the healthiness of a user's full diet.
- A single generic adult baseline cannot serve children, pregnancy, high-performance athletes, or people with medical dietary restrictions.
- Japanese and WHO guidance can evolve; reference assumptions must remain centralized and documented.

These limitations are surfaced in the UI rather than hidden.
