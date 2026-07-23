import {describe, expect, it} from 'vitest';

import {
  LOCALE_STORAGE_KEY,
  messages,
  persistLocale,
  resolveLocale,
} from './i18n';
import * as i18n from './i18n';

const expectedMessageKeys = [
  'appName',
  'languageLabel',
  'introEyebrow',
  'introTitle',
  'introBody',
  'startCamera',
  'cameraTitle',
  'cameraHint',
  'cameraReady',
  'capture',
  'analyzingEyebrow',
  'analyzingTitle',
  'analyzingBody',
  'detectedFood',
  'confidence',
  'confidenceLow',
  'confidenceMedium',
  'confidenceHigh',
  'assumptionsTitle',
  'assumptionVisiblePortionOnly',
  'assumptionPortionEstimated',
  'assumptionSeasoningEstimated',
  'assumptionHiddenIngredientsPossible',
  'estimatedScore',
  'tierBalanced',
  'tierMostlyBalanced',
  'tierNeedsAttention',
  'tierIndeterminate',
  'calories',
  'protein',
  'carbs',
  'fat',
  'fiber',
  'sugar',
  'sodium',
  'portion',
  'statusLow',
  'statusAppropriate',
  'statusHigh',
  'statusIndeterminate',
  'sugarLow',
  'adviceTitle',
  'suggestionAddVegetables',
  'suggestionReduceSauce',
  'suggestionReduceSweetItems',
  'suggestionReduceFat',
  'suggestionAddProtein',
  'suggestionAdjustStaple',
  'suggestionReducePortion',
  'saveResult',
  'retake',
  'retry',
  'disclaimer',
  'referenceBasis',
  'errorCameraDenied',
  'errorCaptureFailed',
  'errorInvalidImage',
  'errorUnsupportedImage',
  'errorImageTooLarge',
  'errorNoFood',
  'errorServiceNotConfigured',
  'errorAnalysisFailed',
  'errorNetwork',
  'errorSaveFailed',
] as const;

describe('locale resolution', () => {
  it('maps app locales to standards-compatible document language tags', () => {
    const documentLanguage = (
      i18n as unknown as {
        documentLanguage?: (locale: 'zh' | 'ja' | 'en') => string;
      }
    ).documentLanguage;

    expect(documentLanguage).toBeTypeOf('function');
    if (!documentLanguage) {
      return;
    }
    expect({
      zh: documentLanguage('zh'),
      ja: documentLanguage('ja'),
      en: documentLanguage('en'),
    }).toEqual({zh: 'zh-CN', ja: 'ja', en: 'en'});
  });

  it('uses a saved supported locale before device preferences', () => {
    expect(resolveLocale('zh', ['en-US', 'ja-JP'])).toBe('zh');
  });

  it('uses the first supported device locale after skipping unsupported locales', () => {
    expect(resolveLocale(null, ['fr-FR', 'EN-gb', 'ja-JP'])).toBe('en');
  });

  it('falls back to Japanese when no supported locale is available', () => {
    expect(resolveLocale('fr', ['de-DE', 'ko-KR'])).toBe('ja');
  });

  it('persists the selected locale under the product storage key', () => {
    const stored: Record<string, string> = {};
    const originalWindow = globalThis.window;
    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: {
        localStorage: {
          setItem(key: string, value: string) {
            stored[key] = value;
          },
        },
      },
    });

    try {
      persistLocale('en');
      expect(LOCALE_STORAGE_KEY).toBe('kalories.locale');
      expect(stored).toEqual({'kalories.locale': 'en'});
    } finally {
      Object.defineProperty(globalThis, 'window', {
        configurable: true,
        value: originalWindow,
      });
    }
  });
});

describe('message dictionaries', () => {
  it.each(['zh', 'ja', 'en'] as const)(
    '%s contains exactly the complete message contract',
    (locale) => {
      expect(Object.keys(messages[locale])).toEqual(expectedMessageKeys);
    },
  );

  it('contains the approved nutrition and reference terminology', () => {
    expect(messages.zh.estimatedScore).toBe('估算健康分');
    expect(messages.ja.fiber).toBe('食物繊維');
    expect(messages.en.referenceBasis).toBe(
      'Based on the Dietary Reference Intakes for Japanese (2025) and WHO guidance.',
    );
  });

  it('contains the exact localized language control labels', () => {
    expect({
      zh: messages.zh.languageLabel,
      ja: messages.ja.languageLabel,
      en: messages.en.languageLabel,
    }).toEqual({zh: '语言', ja: '言語', en: 'Language'});
  });

  it('contains the exact approved assumption copy in every language', () => {
    expect({
      zh: {
        assumptionsTitle: messages.zh.assumptionsTitle,
        visiblePortionOnly: messages.zh.assumptionVisiblePortionOnly,
        portionEstimated: messages.zh.assumptionPortionEstimated,
        seasoningEstimated: messages.zh.assumptionSeasoningEstimated,
        hiddenIngredientsPossible:
          messages.zh.assumptionHiddenIngredientsPossible,
      },
      ja: {
        assumptionsTitle: messages.ja.assumptionsTitle,
        visiblePortionOnly: messages.ja.assumptionVisiblePortionOnly,
        portionEstimated: messages.ja.assumptionPortionEstimated,
        seasoningEstimated: messages.ja.assumptionSeasoningEstimated,
        hiddenIngredientsPossible:
          messages.ja.assumptionHiddenIngredientsPossible,
      },
      en: {
        assumptionsTitle: messages.en.assumptionsTitle,
        visiblePortionOnly: messages.en.assumptionVisiblePortionOnly,
        portionEstimated: messages.en.assumptionPortionEstimated,
        seasoningEstimated: messages.en.assumptionSeasoningEstimated,
        hiddenIngredientsPossible:
          messages.en.assumptionHiddenIngredientsPossible,
      },
    }).toEqual({
      zh: {
        assumptionsTitle: '估算前提',
        visiblePortionOnly: '仅估算照片中可见的份量。',
        portionEstimated: '份量根据外观估算。',
        seasoningEstimated: '调味料用量为估算值。',
        hiddenIngredientsPossible: '可能含有照片中看不见的食材。',
      },
      ja: {
        assumptionsTitle: '推定の前提',
        visiblePortionOnly: '写真に写っている量のみを推定しています。',
        portionEstimated: '量は見た目から推定しています。',
        seasoningEstimated: '調味料の量を推定しています。',
        hiddenIngredientsPossible:
          '写真に見えない材料が含まれる可能性があります。',
      },
      en: {
        assumptionsTitle: 'Estimation assumptions',
        visiblePortionOnly: 'Only the visible portion is estimated.',
        portionEstimated: 'Portion size is estimated visually.',
        seasoningEstimated: 'Seasoning amounts are estimated.',
        hiddenIngredientsPossible:
          'Ingredients not visible in the photo may be present.',
      },
    });
  });
});
