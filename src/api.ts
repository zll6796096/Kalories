import type {
  AnalysisResult,
  AppErrorCode,
  AssessmentTier,
  ConfidenceLevel,
  NutrientKey,
  NutrientStatus,
} from './types';

const backendErrorCodes = new Set<AppErrorCode>([
  'INVALID_IMAGE',
  'UNSUPPORTED_IMAGE',
  'IMAGE_TOO_LARGE',
  'SERVICE_NOT_CONFIGURED',
  'ANALYSIS_FAILED',
]);

const nutrientKeys: NutrientKey[] = [
  'calories_kcal',
  'protein_g',
  'carbs_g',
  'fat_g',
  'fiber_g',
  'sugar_g',
  'sodium_mg',
];

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

function isNullableNumber(value: unknown): value is number | null {
  return value === null || (typeof value === 'number' && Number.isFinite(value));
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
}

function hasNutrients(value: unknown): boolean {
  return (
    isRecord(value) &&
    nutrientKeys.every((key) => isNullableNumber(value[key]))
  );
}

function hasConfidence(value: unknown): boolean {
  if (!isRecord(value) || !isRecord(value.nutrients)) {
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

function hasFoodNames(value: unknown): boolean {
  return (
    value === null ||
    (isRecord(value) &&
      typeof value.zh === 'string' &&
      typeof value.ja === 'string' &&
      typeof value.en === 'string')
  );
}

function hasAssessment(value: unknown): boolean {
  if (!isRecord(value) || !isRecord(value.statuses)) {
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
    isStringArray(value.suggestion_keys) &&
    isStringArray(value.scoring_reasons) &&
    typeof value.insufficient_data === 'boolean'
  );
}

function isAnalysisResult(value: unknown): value is AnalysisResult {
  if (!isRecord(value)) {
    return false;
  }

  return (
    typeof value.food_detected === 'boolean' &&
    hasFoodNames(value.food_names) &&
    (!value.food_detected || value.food_names !== null) &&
    isNullableNumber(value.portion_grams) &&
    hasNutrients(value.nutrients) &&
    hasConfidence(value.confidence) &&
    isStringArray(value.assumption_keys) &&
    hasAssessment(value.assessment)
  );
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

async function readJsonSafely(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

export async function analyzeImage(
  image: string,
  fetcher: typeof fetch = fetch,
): Promise<AnalysisResult> {
  let response: Response;

  try {
    response = await fetcher('/api/analyze', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({image}),
    });
  } catch {
    throw new AnalysisApiError('NETWORK_ERROR');
  }

  const body = await readJsonSafely(response);
  if (!response.ok) {
    throw new AnalysisApiError(
      stableBackendCode(body) ?? 'ANALYSIS_FAILED',
    );
  }

  if (!isAnalysisResult(body)) {
    throw new AnalysisApiError('ANALYSIS_FAILED');
  }

  return body;
}
