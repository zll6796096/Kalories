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
