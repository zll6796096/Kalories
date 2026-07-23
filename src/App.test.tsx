import {renderToStaticMarkup} from 'react-dom/server';
import {afterEach, describe, expect, it, vi} from 'vitest';

import App, {
  appModelReducer,
  createInitialAppModel,
  errorMessageKey,
  imageForRetry,
} from './App';
import type {AnalysisResult, AppErrorCode} from './types';

const result: AnalysisResult = {
  food_detected: true,
  food_names: {zh: '饭', ja: 'ご飯', en: 'Rice'},
  portion_grams: 180,
  nutrients: {
    calories_kcal: 300,
    protein_g: 6,
    carbs_g: 65,
    fat_g: 1,
    fiber_g: 1,
    sugar_g: 0,
    sodium_mg: 5,
  },
  confidence: {
    overall: 'medium',
    portion: 'medium',
    nutrients: {
      calories_kcal: 'medium',
      protein_g: 'medium',
      carbs_g: 'medium',
      fat_g: 'medium',
      fiber_g: 'medium',
      sugar_g: 'low',
      sodium_mg: 'low',
    },
  },
  assumption_keys: [],
  assessment: {
    score: 62,
    tier: 'mostly_balanced',
    statuses: {
      calories_kcal: 'low',
      protein_g: 'low',
      carbs_g: 'high',
      fat_g: 'low',
      fiber_g: 'low',
      sugar_g: 'low',
      sodium_mg: 'low',
    },
    suggestion_keys: ['add_protein'],
    scoring_reasons: [],
    insufficient_data: false,
  },
};

const allErrorCodes: AppErrorCode[] = [
  'CAMERA_DENIED',
  'CAPTURE_FAILED',
  'INVALID_IMAGE',
  'UNSUPPORTED_IMAGE',
  'IMAGE_TOO_LARGE',
  'NO_FOOD',
  'SERVICE_NOT_CONFIGURED',
  'ANALYSIS_FAILED',
  'NETWORK_ERROR',
  'SAVE_FAILED',
];

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('app orchestration model', () => {
  it('maps every stable error code to a localized message key', () => {
    expect(allErrorCodes.map(errorMessageKey)).toEqual([
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
    ]);
  });

  it('changes locale without mutating nutrition, image, error, or request state', () => {
    const before = {
      ...createInitialAppModel('ja'),
      appState: 'result' as const,
      analysisResult: result,
      capturedImage: 'same-photo',
      error: 'NO_FOOD' as const,
      latestRequestId: 7,
    };

    const after = appModelReducer(before, {
      type: 'locale-changed',
      locale: 'en',
    });

    expect(after).toEqual({...before, locale: 'en'});
  });

  it('retake explicitly clears the image, result, and error', () => {
    const before = {
      ...createInitialAppModel('ja'),
      appState: 'result' as const,
      analysisResult: result,
      capturedImage: 'same-photo',
      error: 'SAVE_FAILED' as const,
      latestRequestId: 3,
    };

    expect(
      appModelReducer(before, {type: 'retake', nextRequestId: 4}),
    ).toEqual(createInitialAppModel('ja', 4, 'camera'));
  });

  it('uses the unchanged original photo for retry', () => {
    const model = {
      ...createInitialAppModel('en'),
      capturedImage: 'data:image/jpeg;base64,original',
    };

    expect(imageForRetry(model)).toBe(
      'data:image/jpeg;base64,original',
    );
  });

  it('ignores a late response from an older analysis request', () => {
    const current = {
      ...createInitialAppModel('ja'),
      appState: 'analyzing' as const,
      capturedImage: 'new-photo',
      latestRequestId: 2,
    };

    expect(
      appModelReducer(current, {
        type: 'analysis-succeeded',
        requestId: 1,
        result,
      }),
    ).toBe(current);
  });

  it('keeps a no-food response honest and visible on the result page', () => {
    const noFood = {
      ...result,
      food_detected: false,
      food_names: null,
    };
    const analyzing = {
      ...createInitialAppModel('ja'),
      appState: 'analyzing' as const,
      capturedImage: 'same-photo',
      latestRequestId: 1,
    };

    expect(
      appModelReducer(analyzing, {
        type: 'analysis-succeeded',
        requestId: 1,
        result: noFood,
      }),
    ).toMatchObject({
      appState: 'result',
      analysisResult: noFood,
      capturedImage: 'same-photo',
      error: 'NO_FOOD',
    });
  });

  it('renders the Japanese intro safely without browser globals', () => {
    vi.stubGlobal('navigator', undefined);
    vi.stubGlobal('window', undefined);

    expect(renderToStaticMarkup(<App />)).toContain(
      '一枚の写真から、食事をもっと理解する。',
    );
  });
});
