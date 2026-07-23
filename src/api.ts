import type {
  AnalysisResult,
  AppErrorCode,
  AssessmentTier,
  ConfidenceLevel,
  NutrientKey,
  NutrientStatus,
} from './types';

export const ANALYSIS_TIMEOUT_MS = 25_000;

const backendErrorCodes = new Set<AppErrorCode>([
  'INVALID_IMAGE',
  'UNSUPPORTED_IMAGE',
  'IMAGE_TOO_LARGE',
  'SERVICE_NOT_CONFIGURED',
  'ANALYSIS_FAILED',
]);

const nutrientKeys = [
  'calories_kcal',
  'protein_g',
  'carbs_g',
  'fat_g',
  'fiber_g',
  'sugar_g',
  'sodium_mg',
] as const satisfies readonly NutrientKey[];

const topLevelKeys = [
  'food_detected',
  'food_names',
  'portion_grams',
  'nutrients',
  'confidence',
  'assumption_keys',
  'assessment',
] as const;
const foodNameKeys = ['zh', 'ja', 'en'] as const;
const confidenceKeys = ['overall', 'portion', 'nutrients'] as const;
const assessmentKeys = [
  'score',
  'tier',
  'statuses',
  'suggestion_keys',
  'scoring_reasons',
  'insufficient_data',
] as const;

const confidenceLevels = new Set<ConfidenceLevel>(['low', 'medium', 'high']);
const nutrientStatuses = new Set<NutrientStatus>([
  'low',
  'appropriate',
  'high',
  'indeterminate',
]);
const assessmentTiers = new Set<AssessmentTier>([
  'balanced',
  'mostly_balanced',
  'needs_attention',
  'indeterminate',
]);
const assumptionKeys = new Set([
  'visible_portion_only',
  'portion_estimated',
  'seasoning_estimated',
  'hidden_ingredients_possible',
]);
const suggestionKeys = new Set([
  'add_vegetables',
  'reduce_sauce',
  'reduce_sweet_items',
  'reduce_fat',
  'add_protein',
  'adjust_staple',
  'reduce_portion',
]);
const scoringReasons = new Set([
  'calories_low',
  'calories_high',
  'protein_g_low',
  'protein_g_high',
  'carbs_g_low',
  'carbs_g_high',
  'fat_g_low',
  'fat_g_high',
  'fiber_low',
  'sugar_high',
  'sodium_elevated',
  'sodium_high',
]);
const nutrientMaximums: Record<NutrientKey, number> = {
  calories_kcal: 10_000,
  protein_g: 2_000,
  carbs_g: 2_000,
  fat_g: 2_000,
  fiber_g: 2_000,
  sugar_g: 2_000,
  sodium_mg: 100_000,
};
const macroEnergy: Partial<Record<NutrientKey, number>> = {
  protein_g: 4,
  carbs_g: 4,
  fat_g: 9,
};
const macroKeys = ['protein_g', 'carbs_g', 'fat_g'] as const;

export interface AnalyzeImageOptions {
  fetcher?: typeof fetch;
  signal?: AbortSignal;
  timeoutMs?: number;
}

export class AnalysisApiError extends Error {
  readonly code: AppErrorCode;

  constructor(code: AppErrorCode) {
    super(code);
    this.name = 'AnalysisApiError';
    this.code = code;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasOwn(value: object, key: PropertyKey): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function hasExactKeys(
  value: unknown,
  keys: readonly string[],
): value is Record<string, unknown> {
  if (!isRecord(value)) {
    return false;
  }

  const actualKeys = Object.keys(value);
  return (
    actualKeys.length === keys.length &&
    keys.every((key) => hasOwn(value, key))
  );
}

function isBoundedNullableNumber(
  value: unknown,
  maximum: number,
): value is number | null {
  return (
    value === null ||
    (typeof value === 'number' &&
      Number.isFinite(value) &&
      value >= 0 &&
      value <= maximum)
  );
}

function isTrimmedBoundedString(
  value: unknown,
  maximumLength: number,
): value is string {
  return (
    typeof value === 'string' &&
    value === value.trim() &&
    [...value].length >= 1 &&
    [...value].length <= maximumLength
  );
}

function isUniqueKnownStringList(
  value: unknown,
  allowed: ReadonlySet<string>,
  maximumLength: number,
): value is string[] {
  return (
    Array.isArray(value) &&
    value.length <= maximumLength &&
    value.every((item) => typeof item === 'string' && allowed.has(item)) &&
    new Set(value).size === value.length
  );
}

function hasFoodNames(value: unknown): boolean {
  return (
    value === null ||
    (hasExactKeys(value, foodNameKeys) &&
      foodNameKeys.every((key) =>
        isTrimmedBoundedString(value[key], 120),
      ))
  );
}

function hasNutrients(value: unknown): boolean {
  return (
    hasExactKeys(value, nutrientKeys) &&
    nutrientKeys.every((key) =>
      isBoundedNullableNumber(value[key], nutrientMaximums[key]),
    )
  );
}

function hasConfidence(value: unknown): boolean {
  if (
    !hasExactKeys(value, confidenceKeys) ||
    !hasExactKeys(value.nutrients, nutrientKeys)
  ) {
    return false;
  }

  return (
    confidenceLevels.has(value.overall as ConfidenceLevel) &&
    confidenceLevels.has(value.portion as ConfidenceLevel) &&
    nutrientKeys.every((key) =>
      confidenceLevels.has(value.nutrients[key] as ConfidenceLevel),
    )
  );
}

function hasAssessment(value: unknown): boolean {
  if (
    !hasExactKeys(value, assessmentKeys) ||
    !hasExactKeys(value.statuses, nutrientKeys)
  ) {
    return false;
  }

  const validScore =
    value.score === null ||
    (typeof value.score === 'number' &&
      Number.isInteger(value.score) &&
      value.score >= 0 &&
      value.score <= 100);

  return (
    validScore &&
    assessmentTiers.has(value.tier as AssessmentTier) &&
    nutrientKeys.every((key) =>
      nutrientStatuses.has(value.statuses[key] as NutrientStatus),
    ) &&
    isUniqueKnownStringList(value.suggestion_keys, suggestionKeys, 2) &&
    isUniqueKnownStringList(value.scoring_reasons, scoringReasons, 7) &&
    typeof value.insufficient_data === 'boolean'
  );
}

function expectedTier(score: number): AssessmentTier {
  if (score >= 80) {
    return 'balanced';
  }
  if (score >= 60) {
    return 'mostly_balanced';
  }
  return 'needs_attention';
}

function scoreIsAvailable(value: AnalysisResult): boolean {
  const presentMacros = macroKeys.filter(
    (key) => value.nutrients[key] !== null,
  );
  const denominator = presentMacros.reduce(
    (total, key) =>
      total + value.nutrients[key]! * macroEnergy[key]!,
    0,
  );
  return (
    value.nutrients.calories_kcal !== null &&
    presentMacros.length >= 2 &&
    denominator > 0 &&
    (value.confidence.overall === 'medium' ||
      value.confidence.overall === 'high')
  );
}

function statusesAreCoherent(value: AnalysisResult): boolean {
  const directKeys = [
    'calories_kcal',
    'fiber_g',
    'sugar_g',
    'sodium_mg',
  ] as const;
  if (
    directKeys.some(
      (key) =>
        (value.nutrients[key] === null) !==
        (value.assessment.statuses[key] === 'indeterminate'),
    )
  ) {
    return false;
  }

  const allMacrosPresent = macroKeys.every(
    (key) => value.nutrients[key] !== null,
  );
  const macroDenominator = macroKeys.reduce(
    (total, key) =>
      total + (value.nutrients[key] ?? 0) * macroEnergy[key]!,
    0,
  );
  const macrosAreDeterminate = allMacrosPresent && macroDenominator > 0;
  return macroKeys.every(
    (key) =>
      (value.assessment.statuses[key] !== 'indeterminate') ===
      macrosAreDeterminate,
  );
}

function isNormalizedNoFood(value: AnalysisResult): boolean {
  return (
    value.food_names === null &&
    value.portion_grams === null &&
    nutrientKeys.every((key) => value.nutrients[key] === null) &&
    value.assessment.score === null &&
    value.assessment.tier === 'indeterminate' &&
    nutrientKeys.every(
      (key) => value.assessment.statuses[key] === 'indeterminate',
    ) &&
    value.assessment.suggestion_keys.length === 0 &&
    value.assessment.scoring_reasons.length === 0 &&
    value.assessment.insufficient_data
  );
}

function isCoherentFoodAnalysis(value: AnalysisResult): boolean {
  if (value.food_names === null || !statusesAreCoherent(value)) {
    return false;
  }

  const available = scoreIsAvailable(value);
  if (value.assessment.insufficient_data === available) {
    return false;
  }

  if (!available) {
    return (
      value.assessment.score === null &&
      value.assessment.tier === 'indeterminate'
    );
  }

  return (
    value.assessment.score !== null &&
    value.assessment.tier === expectedTier(value.assessment.score) &&
    (value.assessment.score !== 100 ||
      (value.assessment.suggestion_keys.length === 0 &&
        value.assessment.scoring_reasons.length === 0))
  );
}

function isAnalysisResult(value: unknown): value is AnalysisResult {
  if (
    !hasExactKeys(value, topLevelKeys) ||
    typeof value.food_detected !== 'boolean' ||
    !hasFoodNames(value.food_names) ||
    !isBoundedNullableNumber(value.portion_grams, 10_000) ||
    !hasNutrients(value.nutrients) ||
    !hasConfidence(value.confidence) ||
    !isUniqueKnownStringList(value.assumption_keys, assumptionKeys, 4) ||
    !hasAssessment(value.assessment)
  ) {
    return false;
  }

  const result = value as unknown as AnalysisResult;
  return result.food_detected
    ? isCoherentFoodAnalysis(result)
    : isNormalizedNoFood(result);
}

function stableBackendCode(value: unknown): AppErrorCode | null {
  if (!isRecord(value) || !isRecord(value.detail)) {
    return null;
  }

  const code = value.detail.code;
  return typeof code === 'string' &&
    backendErrorCodes.has(code as AppErrorCode)
    ? (code as AppErrorCode)
    : null;
}

async function readJsonSafely(
  response: Response,
  cancellation: Promise<never>,
  signal: AbortSignal,
): Promise<unknown> {
  try {
    return await Promise.race([response.json(), cancellation]);
  } catch (error) {
    if (error instanceof AnalysisApiError || signal.aborted) {
      if (error instanceof AnalysisApiError) {
        throw error;
      }
      throw new AnalysisApiError('NETWORK_ERROR');
    }
    if (error instanceof SyntaxError) {
      return null;
    }
    throw new AnalysisApiError('NETWORK_ERROR');
  }
}

export async function analyzeImage(
  image: string,
  options: AnalyzeImageOptions = {},
): Promise<AnalysisResult> {
  const fetcher = options.fetcher ?? fetch;
  const timeoutMs = options.timeoutMs ?? ANALYSIS_TIMEOUT_MS;
  const controller = new AbortController();
  let settled = false;
  let rejectCancellation: () => void = () => undefined;
  const cancellation = new Promise<never>((_resolve, reject) => {
    rejectCancellation = () => {
      if (settled) {
        return;
      }
      controller.abort();
      reject(new AnalysisApiError('NETWORK_ERROR'));
    };
  });
  const handleExternalAbort = () => rejectCancellation();

  if (options.signal?.aborted) {
    handleExternalAbort();
  } else {
    options.signal?.addEventListener('abort', handleExternalAbort, {
      once: true,
    });
  }
  const timeout = setTimeout(
    rejectCancellation,
    Math.max(0, timeoutMs),
  );

  try {
    const response = await Promise.race([
      fetcher('/api/analyze', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({image}),
        signal: controller.signal,
      }),
      cancellation,
    ]);
    const body = await readJsonSafely(
      response,
      cancellation,
      controller.signal,
    );

    if (!response.ok) {
      throw new AnalysisApiError(
        stableBackendCode(body) ?? 'ANALYSIS_FAILED',
      );
    }
    if (!isAnalysisResult(body)) {
      throw new AnalysisApiError('ANALYSIS_FAILED');
    }
    return body;
  } catch (error) {
    if (error instanceof AnalysisApiError) {
      throw error;
    }
    throw new AnalysisApiError('NETWORK_ERROR');
  } finally {
    settled = true;
    clearTimeout(timeout);
    options.signal?.removeEventListener('abort', handleExternalAbort);
  }
}
