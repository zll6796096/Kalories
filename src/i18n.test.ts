import {describe, expect, it} from 'vitest';

import {
  LOCALE_STORAGE_KEY,
  messages,
  persistLocale,
  resolveLocale,
} from './i18n';

const expectedMessageKeys = [
  'appName',
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
});
