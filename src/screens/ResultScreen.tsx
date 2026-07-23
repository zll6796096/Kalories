import {Camera, Download, RotateCcw} from 'lucide-react';
import {useRef} from 'react';

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
} from '../types';

interface ResultScreenProps {
  locale: Locale;
  text: Messages;
  data: AnalysisResult;
  capturedImage: string | null;
  onLocaleChange: (locale: Locale) => void;
  onRetry: () => void;
  onRetake: () => void;
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

const suggestionMessageKeys: Readonly<Record<string, keyof Messages>> = {
  add_vegetables: 'suggestionAddVegetables',
  reduce_sauce: 'suggestionReduceSauce',
  reduce_sweet_items: 'suggestionReduceSweetItems',
  reduce_fat: 'suggestionReduceFat',
  add_protein: 'suggestionAddProtein',
  adjust_staple: 'suggestionAdjustStaple',
  reduce_portion: 'suggestionReducePortion',
};

type Unit = 'kcal' | 'g' | 'mg';

interface NutrientRowProps {
  nutrient: NutrientKey;
  label: string;
  unit: Unit;
  data: AnalysisResult;
  locale: Locale;
  text: Messages;
  showConfidence?: boolean;
  emphasized?: boolean;
}

function confidenceText(level: ConfidenceLevel, text: Messages): string {
  return text[confidenceMessageKeys[level]];
}

function NutrientRow({
  nutrient,
  label,
  unit,
  data,
  locale,
  text,
  showConfidence = false,
  emphasized = false,
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
        {showConfidence && (
          <small>
            {text.confidence}: {confidenceText(data.confidence.nutrients[nutrient], text)}
          </small>
        )}
      </div>
      <strong>{formatNutritionValue(data.nutrients[nutrient], unit, locale)}</strong>
      <span className={`status-label status-${status}`}>{statusText}</span>
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
  onSaveError,
}: ResultScreenProps) {
  const resultRef = useRef<HTMLElement>(null);
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
      const messageKey = suggestionMessageKeys[key];
      return messageKey ? [text[messageKey]] : [];
    })
    .slice(0, 2);

  const handleSave = async () => {
    try {
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
    } catch {
      onSaveError('SAVE_FAILED');
    }
  };

  return (
    <main className="result-page" ref={resultRef}>
      <header className="result-hero">
        <div className="result-toolbar">
          <span className="wordmark">{text.appName}</span>
          <LanguageSwitcher locale={locale} onChange={onLocaleChange} />
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

      <section className="macro-list" aria-label={`${text.protein}, ${text.carbs}`}>
        <NutrientRow
          nutrient="protein_g"
          label={text.protein}
          unit="g"
          data={data}
          locale={locale}
          text={text}
        />
        <NutrientRow
          nutrient="carbs_g"
          label={text.carbs}
          unit="g"
          data={data}
          locale={locale}
          text={text}
        />
        <NutrientRow
          nutrient="fat_g"
          label={text.fat}
          unit="g"
          data={data}
          locale={locale}
          text={text}
        />
        <NutrientRow
          nutrient="fiber_g"
          label={text.fiber}
          unit="g"
          data={data}
          locale={locale}
          text={text}
        />
      </section>

      <section className="secondary-nutrients" aria-label={`${text.sugar}, ${text.sodium}`}>
        <NutrientRow
          nutrient="sugar_g"
          label={text.sugar}
          unit="g"
          data={data}
          locale={locale}
          text={text}
          showConfidence
        />
        <NutrientRow
          nutrient="sodium_mg"
          label={text.sodium}
          unit="mg"
          data={data}
          locale={locale}
          text={text}
          showConfidence
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

      <section className="advice-card" aria-labelledby="advice-title">
        <p className="section-label" id="advice-title">
          {text.adviceTitle}
        </p>
        {visibleSuggestions.length > 0 && (
          <ul>
            {visibleSuggestions.map((suggestion) => (
              <li key={suggestion}>{suggestion}</li>
            ))}
          </ul>
        )}
      </section>

      <footer className="result-footer">
        <div className="reference-note">
          <p>{text.disclaimer}</p>
          <p>{text.referenceBasis}</p>
        </div>
        <div className="result-actions">
          <button className="primary-button" type="button" onClick={handleSave}>
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
