import type {Messages} from './i18n';
import type {Locale, NutrientKey, NutrientStatus} from './types';

export type NutritionUnit = 'kcal' | 'g' | 'mg';

const intlLocales: Record<Locale, string> = {
  zh: 'zh-CN',
  ja: 'ja-JP',
  en: 'en-US',
};

export function formatNutritionValue(
  value: number | null,
  unit: NutritionUnit,
  locale: Locale,
): string {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return '—';
  }

  const showDecimal = unit === 'g' && Math.abs(value) < 10;
  const formattedValue = new Intl.NumberFormat(intlLocales[locale], {
    maximumFractionDigits: showDecimal ? 1 : 0,
  }).format(value);

  return `${formattedValue} ${unit}`;
}

const standardStatusKeys: Record<NutrientStatus, keyof Messages> = {
  low: 'statusLow',
  appropriate: 'statusAppropriate',
  high: 'statusHigh',
  indeterminate: 'statusIndeterminate',
};

export function statusMessageKey(
  nutrient: NutrientKey,
  status: NutrientStatus,
): keyof Messages {
  if (nutrient === 'sugar_g' && status === 'low') {
    return 'sugarLow';
  }

  return standardStatusKeys[status];
}
