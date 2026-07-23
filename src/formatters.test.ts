import {describe, expect, it} from 'vitest';

import {formatNutritionValue, statusMessageKey} from './formatters';

describe('formatNutritionValue', () => {
  it.each([null, Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY])(
    'renders missing or non-finite value %s as an em dash',
    (value) => {
      expect(formatNutritionValue(value, 'g', 'en')).toBe('—');
    },
  );

  it('renders present gram values with a localized unit', () => {
    expect(formatNutritionValue(36, 'g', 'en')).toBe('36 g');
  });

  it('rounds milligram values to a whole localized number', () => {
    expect(formatNutritionValue(920.4, 'mg', 'zh')).toBe('920 mg');
  });

  it('keeps one decimal place for gram values below ten', () => {
    expect(formatNutritionValue(8.6, 'g', 'ja')).toBe('8.6 g');
  });

  it('rounds calories to a whole localized number', () => {
    expect(formatNutritionValue(612.7, 'kcal', 'en')).toBe('613 kcal');
  });
});

describe('statusMessageKey', () => {
  it('uses a contextual label for low sugar', () => {
    expect(statusMessageKey('sugar_g', 'low')).toBe('sugarLow');
  });

  it('uses the standard low label for other nutrients', () => {
    expect(statusMessageKey('protein_g', 'low')).toBe('statusLow');
  });

  it.each([
    ['appropriate', 'statusAppropriate'],
    ['high', 'statusHigh'],
    ['indeterminate', 'statusIndeterminate'],
  ] as const)('maps %s to %s', (status, key) => {
    expect(statusMessageKey('sodium_mg', status)).toBe(key);
  });
});
