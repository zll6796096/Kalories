import {Camera, Download, RotateCcw} from 'lucide-react';
import {useRef, useState} from 'react';

import {LanguageSwitcher} from '../components/LanguageSwitcher';
import {formatNutritionValue, statusMessageKey} from '../formatters';
import type {Messages} from '../i18n';
import type {
  AnalysisResult,
  AppErrorCode,
  AssessmentTier,
  ConfidenceLevel,
  Locale,
  NutrientKey,
  NutrientStatus,
} from '../types';

interface ResultScreenProps {
  locale: Locale;
  text: Messages;
  data: AnalysisResult;
  capturedImage: string | null;
  onLocaleChange: (locale: Locale) => void;
  onRetry: () => void;
  onRetake: () => void;
  onSaveStart?: () => void;
  onSaveSuccess?: () => void;
  onSaveError: (code: AppErrorCode) => void;
}

const confidenceMessageKeys: Record<ConfidenceLevel, keyof Messages> = {
  low: 'confidenceLow',
  medium: 'confidenceMedium',
  high: 'confidenceHigh',
};

const tierMessageKeys: Record<AssessmentTier, keyof Messages> = {
  balanced: 'tierBalanced',
  mostly_balanced: 'tierMostlyBalanced',
  needs_attention: 'tierNeedsAttention',
  indeterminate: 'tierIndeterminate',
};

const suggestionDefinitions = {
  add_vegetables: {
    message: 'suggestionAddVegetables',
    nutrient: 'fiber_g',
  },
  reduce_sauce: {
    message: 'suggestionReduceSauce',
    nutrient: 'sodium_mg',
  },
  reduce_sweet_items: {
    message: 'suggestionReduceSweetItems',
    nutrient: 'sugar_g',
  },
  reduce_fat: {
    message: 'suggestionReduceFat',
    nutrient: 'fat_g',
  },
  add_protein: {
    message: 'suggestionAddProtein',
    nutrient: 'protein_g',
  },
  adjust_staple: {
    message: 'suggestionAdjustStaple',
    nutrient: 'carbs_g',
  },
  reduce_portion: {
    message: 'suggestionReducePortion',
    nutrient: 'calories_kcal',
  },
} as const satisfies Record<
  string,
  {message: keyof Messages; nutrient: NutrientKey}
>;

type KnownSuggestionKey = keyof typeof suggestionDefinitions;

const nutrientMessageKeys: Record<NutrientKey, keyof Messages> = {
  calories_kcal: 'calories',
  protein_g: 'protein',
  carbs_g: 'carbs',
  fat_g: 'fat',
  fiber_g: 'fiber',
  sugar_g: 'sugar',
  sodium_mg: 'sodium',
};

// Stable meal-balance priority: macros first, then fibre and secondary measures.
const positivePriority: readonly NutrientKey[] = [
  'protein_g',
  'carbs_g',
  'fat_g',
  'fiber_g',
  'calories_kcal',
  'sugar_g',
  'sodium_mg',
];

const concernFallbackPriority: readonly NutrientKey[] = [
  'sodium_mg',
  'sugar_g',
  'calories_kcal',
  'protein_g',
  'carbs_g',
  'fat_g',
  'fiber_g',
];

const assumptionMessageKeys: Readonly<Record<string, keyof Messages>> = {
  visible_portion_only: 'assumptionVisiblePortionOnly',
  portion_estimated: 'assumptionPortionEstimated',
  seasoning_estimated: 'assumptionSeasoningEstimated',
  hidden_ingredients_possible: 'assumptionHiddenIngredientsPossible',
};

type Unit = 'kcal' | 'g' | 'mg';

interface NutrientRowProps {
  nutrient: NutrientKey;
  label: string;
  unit: Unit;
  data: AnalysisResult;
  locale: Locale;
  text: Messages;
  emphasized?: boolean;
  showRail?: boolean;
}

function confidenceText(level: ConfidenceLevel, text: Messages): string {
  return text[confidenceMessageKeys[level]];
}

function knownSuggestion(key: string) {
  if (!Object.prototype.hasOwnProperty.call(suggestionDefinitions, key)) {
    return null;
  }

  return suggestionDefinitions[key as KnownSuggestionKey];
}

function localizedNutrientStatus(
  nutrient: NutrientKey,
  status: NutrientStatus,
  text: Messages,
): string {
  return `${text[nutrientMessageKeys[nutrient]]} · ${text[statusMessageKey(nutrient, status)]}`;
}

function strongestPositive(data: AnalysisResult, text: Messages): string {
  const nutrient = positivePriority.find(
    (key) => data.assessment.statuses[key] === 'appropriate',
  );

  return nutrient
    ? localizedNutrientStatus(nutrient, 'appropriate', text)
    : text.noClearPositive;
}

function mainConcern(data: AnalysisResult, text: Messages): string {
  const firstKnownSuggestion = data.assessment.suggestion_keys
    .map(knownSuggestion)
    .find((suggestion) => suggestion !== null);
  const suggestedNutrient = firstKnownSuggestion?.nutrient;
  const suggestedStatus = suggestedNutrient
    ? data.assessment.statuses[suggestedNutrient]
    : undefined;
  const nutrient =
    suggestedNutrient && suggestedStatus !== 'indeterminate'
      ? suggestedNutrient
      : concernFallbackPriority.find((key) => {
          const status = data.assessment.statuses[key];
          return status !== 'appropriate' && status !== 'indeterminate';
        });

  return nutrient
    ? localizedNutrientStatus(
        nutrient,
        data.assessment.statuses[nutrient],
        text,
      )
    : text.noMajorConcern;
}

function NutrientRow({
  nutrient,
  label,
  unit,
  data,
  locale,
  text,
  emphasized = false,
  showRail = false,
}: NutrientRowProps) {
  const status = data.assessment.statuses[nutrient];
  const statusText = text[statusMessageKey(nutrient, status)];

  return (
    <div
      className={`nutrient-row${emphasized ? ' nutrient-row-emphasized' : ''}`}
      data-nutrient={nutrient}
    >
      <div className="nutrient-label">
        <span>{label}</span>
        <small>
          {text.confidence}: {confidenceText(data.confidence.nutrients[nutrient], text)}
        </small>
      </div>
      <strong>{formatNutritionValue(data.nutrients[nutrient], unit, locale)}</strong>
      <span className={`status-label status-${status}`}>{statusText}</span>
      {showRail && (
        <div
          className={`status-rail status-rail-${status}`}
          data-status={status}
          aria-hidden="true"
        >
          {(['low', 'appropriate', 'high'] as const).map((railStatus) => (
            <span
              className={`status-rail-segment status-rail-segment-${railStatus}${
                status === railStatus ? ' status-rail-segment-active' : ''
              }`}
              key={railStatus}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export function ResultScreen({
  locale,
  text,
  data,
  capturedImage,
  onLocaleChange,
  onRetry,
  onRetake,
  onSaveStart,
  onSaveSuccess,
  onSaveError,
}: ResultScreenProps) {
  const resultRef = useRef<HTMLElement>(null);
  const saveInProgressRef = useRef(false);
  const [isSaving, setIsSaving] = useState(false);
  const scoreIsAvailable =
    typeof data.assessment.score === 'number' &&
    Number.isFinite(data.assessment.score) &&
    data.assessment.tier !== 'indeterminate' &&
    !data.assessment.insufficient_data;
  const displayedTier = scoreIsAvailable ? data.assessment.tier : 'indeterminate';
  const tierText = text[tierMessageKeys[displayedTier]];
  const shouldOfferRetry =
    !data.food_detected ||
    data.assessment.tier === 'indeterminate' ||
    data.assessment.insufficient_data;
  const foodName = data.food_names?.[locale] || text.detectedFood;
  const visibleSuggestions = data.assessment.suggestion_keys
    .flatMap((key) => {
      const suggestion = knownSuggestion(key);
      return suggestion ? [text[suggestion.message]] : [];
    })
    .slice(0, 2);
  const visibleAssumptions = [
    ...new Set(
      data.assumption_keys.flatMap((key) => {
        const messageKey = assumptionMessageKeys[key];
        return messageKey ? [text[messageKey]] : [];
      }),
    ),
  ];

  const handleSave = async () => {
    if (saveInProgressRef.current) {
      return;
    }

    saveInProgressRef.current = true;
    setIsSaving(true);

    try {
      onSaveStart?.();
      if (!resultRef.current) {
        throw new Error('Result element is unavailable');
      }

      const {default: html2canvas} = await import('html2canvas');
      const canvas = await html2canvas(resultRef.current, {
        backgroundColor: '#f5f5f7',
        scale: Math.min(window.devicePixelRatio || 1, 2),
        useCORS: true,
      });
      const link = document.createElement('a');
      link.download = `kalories-result-${Date.now()}.png`;
      link.href = canvas.toDataURL('image/png');
      link.click();
      link.remove();
      onSaveSuccess?.();
    } catch {
      onSaveError('SAVE_FAILED');
    } finally {
      saveInProgressRef.current = false;
      setIsSaving(false);
    }
  };

  return (
    <main className="result-page" ref={resultRef}>
      <header className="result-hero">
        <div className="result-toolbar">
          <span className="wordmark">{text.appName}</span>
          <LanguageSwitcher
            locale={locale}
            label={text.languageLabel}
            onChange={onLocaleChange}
          />
        </div>
        {capturedImage && (
          <img className="result-photo" src={capturedImage} alt={foodName} />
        )}
        <div className="food-identity">
          <p className="eyebrow">{text.detectedFood}</p>
          <h1>{foodName}</h1>
          <span className="confidence-badge">
            {text.confidence}: {confidenceText(data.confidence.overall, text)}
          </span>
        </div>
      </header>

      <section className="result-summary" aria-labelledby="health-summary-title">
        <div>
          <p className="section-label" id="health-summary-title">
            {text.estimatedScore}
          </p>
          <h2>{tierText}</h2>
        </div>
        <div
          className={`score-display tier-${displayedTier}`}
          aria-label={`${text.estimatedScore}: ${scoreIsAvailable ? data.assessment.score : tierText}`}
        >
          {scoreIsAvailable ? (
            <>
              <strong>{data.assessment.score}</strong>
              <span>/100</span>
            </>
          ) : (
            <strong>—</strong>
          )}
        </div>
        <div className="result-findings">
          <div className="result-finding">
            <span>{text.strongestPositive}</span>
            <p>{strongestPositive(data, text)}</p>
          </div>
          <div className="result-finding">
            <span>{text.mainConcern}</span>
            <p>{mainConcern(data, text)}</p>
          </div>
        </div>
      </section>

      <section className="energy-summary" aria-label={text.calories}>
        <NutrientRow
          nutrient="calories_kcal"
          label={text.calories}
          unit="kcal"
          data={data}
          locale={locale}
          text={text}
          emphasized
        />
      </section>

      <section
        className="macro-list"
        aria-label={`${text.protein}, ${text.carbs}, ${text.fat}, ${text.fiber}`}
      >
        <NutrientRow
          nutrient="protein_g"
          label={text.protein}
          unit="g"
          data={data}
          locale={locale}
          text={text}
          showRail
        />
        <NutrientRow
          nutrient="carbs_g"
          label={text.carbs}
          unit="g"
          data={data}
          locale={locale}
          text={text}
          showRail
        />
        <NutrientRow
          nutrient="fat_g"
          label={text.fat}
          unit="g"
          data={data}
          locale={locale}
          text={text}
          showRail
        />
        <NutrientRow
          nutrient="fiber_g"
          label={text.fiber}
          unit="g"
          data={data}
          locale={locale}
          text={text}
          showRail
        />
      </section>

      <section
        className="secondary-nutrients"
        aria-label={`${text.sugar}, ${text.sodium}, ${text.portion}`}
      >
        <NutrientRow
          nutrient="sugar_g"
          label={text.sugar}
          unit="g"
          data={data}
          locale={locale}
          text={text}
        />
        <NutrientRow
          nutrient="sodium_mg"
          label={text.sodium}
          unit="mg"
          data={data}
          locale={locale}
          text={text}
        />
        <div className="nutrient-row portion-row" data-nutrient="portion_grams">
          <div className="nutrient-label">
            <span>{text.portion}</span>
            <small>
              {text.confidence}: {confidenceText(data.confidence.portion, text)}
            </small>
          </div>
          <strong>{formatNutritionValue(data.portion_grams, 'g', locale)}</strong>
        </div>
      </section>

      {visibleSuggestions.length > 0 && (
        <section className="advice-card" aria-labelledby="advice-title">
          <p className="section-label" id="advice-title">
            {text.adviceTitle}
          </p>
          <ul>
            {visibleSuggestions.map((suggestion) => (
              <li key={suggestion}>{suggestion}</li>
            ))}
          </ul>
        </section>
      )}

      <footer className="result-footer">
        {visibleAssumptions.length > 0 && (
          <div className="uncertainty-block">
            <p className="section-label">{text.assumptionsTitle}</p>
            <ul>
              {visibleAssumptions.map((assumption) => (
                <li key={assumption}>{assumption}</li>
              ))}
            </ul>
          </div>
        )}
        <div className="reference-note">
          <p>{text.disclaimer}</p>
          <p>{text.referenceBasis}</p>
        </div>
        <div className="result-actions">
          <button
            className="primary-button"
            type="button"
            data-action="save-result"
            aria-busy={isSaving}
            disabled={isSaving}
            onClick={handleSave}
          >
            <Download aria-hidden="true" size={19} />
            {text.saveResult}
          </button>
          <button className="secondary-button" type="button" onClick={onRetake}>
            <Camera aria-hidden="true" size={19} />
            {text.retake}
          </button>
          {shouldOfferRetry && (
            <button className="text-button" type="button" onClick={onRetry}>
              <RotateCcw aria-hidden="true" size={18} />
              {text.retry}
            </button>
          )}
        </div>
      </footer>
    </main>
  );
}
