import {afterEach, describe, expect, it, vi} from 'vitest';

import {
  ANALYSIS_TIMEOUT_MS,
  AnalysisApiError,
  analyzeImage,
} from './api';
import type {AnalysisResult} from './types';

const analysisFixture: AnalysisResult = {
  food_detected: true,
  food_names: {
    zh: '烤鲑鱼套餐',
    ja: '焼き鮭定食',
    en: 'Grilled salmon set',
  },
  portion_grams: 420,
  nutrients: {
    calories_kcal: 600,
    protein_g: 25,
    carbs_g: 82,
    fat_g: 18,
    fiber_g: 7,
    sugar_g: 8,
    sodium_mg: 500,
  },
  confidence: {
    overall: 'high',
    portion: 'medium',
    nutrients: {
      calories_kcal: 'high',
      protein_g: 'high',
      carbs_g: 'medium',
      fat_g: 'medium',
      fiber_g: 'medium',
      sugar_g: 'low',
      sodium_mg: 'low',
    },
  },
  assumption_keys: [
    'visible_portion_only',
    'portion_estimated',
    'seasoning_estimated',
    'hidden_ingredients_possible',
  ],
  assessment: {
    score: 100,
    tier: 'balanced',
    statuses: {
      calories_kcal: 'appropriate',
      protein_g: 'appropriate',
      carbs_g: 'appropriate',
      fat_g: 'appropriate',
      fiber_g: 'appropriate',
      sugar_g: 'low',
      sodium_mg: 'appropriate',
    },
    suggestion_keys: [],
    scoring_reasons: [],
    insufficient_data: false,
  },
};

const noFoodFixture: AnalysisResult = {
  ...analysisFixture,
  food_detected: false,
  food_names: null,
  portion_grams: null,
  nutrients: {
    calories_kcal: null,
    protein_g: null,
    carbs_g: null,
    fat_g: null,
    fiber_g: null,
    sugar_g: null,
    sodium_mg: null,
  },
  assessment: {
    score: null,
    tier: 'indeterminate',
    statuses: {
      calories_kcal: 'indeterminate',
      protein_g: 'indeterminate',
      carbs_g: 'indeterminate',
      fat_g: 'indeterminate',
      fiber_g: 'indeterminate',
      sugar_g: 'indeterminate',
      sodium_mg: 'indeterminate',
    },
    suggestion_keys: [],
    scoring_reasons: [],
    insufficient_data: true,
  },
};

function response(body: unknown, status = 200): Response {
  return new Response(
    typeof body === 'string' ? body : JSON.stringify(body),
    {
      status,
      headers: {'Content-Type': 'application/json'},
    },
  );
}

function cloneFixture<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function pendingFetch(): ReturnType<typeof vi.fn<typeof fetch>> {
  return vi.fn<typeof fetch>((_input, init) => {
    return new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener(
        'abort',
        () => reject(new Error('aborted transport detail')),
        {once: true},
      );
    });
  });
}

afterEach(() => {
  vi.useRealTimers();
});

describe('analyzeImage', () => {
  it('posts the image and returns the complete typed analysis contract', async () => {
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockResolvedValue(response(analysisFixture));

    await expect(
      analyzeImage('data:image/jpeg;base64,AA==', {fetcher}),
    ).resolves.toEqual(analysisFixture);
    expect(fetcher).toHaveBeenCalledWith('/api/analyze', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({image: 'data:image/jpeg;base64,AA=='}),
      signal: expect.any(AbortSignal),
    });
  });

  it('accepts the normalized no-food response produced by the backend', async () => {
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockResolvedValue(response(noFoodFixture));

    await expect(
      analyzeImage('data:image/jpeg;base64,AA==', {fetcher}),
    ).resolves.toEqual(noFoodFixture);
  });

  it.each([
    'INVALID_IMAGE',
    'UNSUPPORTED_IMAGE',
    'IMAGE_TOO_LARGE',
    'SERVICE_NOT_CONFIGURED',
    'ANALYSIS_FAILED',
  ] as const)('preserves the stable backend error code %s', async (code) => {
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockResolvedValue(response({detail: {code}}, 400));

    await expect(
      analyzeImage('data:image/jpeg;base64,AA==', {fetcher}),
    ).rejects.toMatchObject({code});
  });

  it.each([
    [{detail: {code: 'RATE_LIMITED'}}, 'unknown code'],
    [{detail: 'invalid shape'}, 'malformed body'],
    ['not-json', 'non-JSON body'],
  ] as const)(
    'maps %s failure to ANALYSIS_FAILED (%s)',
    async (body, _description) => {
      const fetcher = vi.fn<typeof fetch>();
      fetcher.mockResolvedValue(response(body, 500));

      await expect(
        analyzeImage('data:image/jpeg;base64,AA==', {fetcher}),
      ).rejects.toMatchObject({code: 'ANALYSIS_FAILED'});
    },
  );

  it('maps a rejected request to NETWORK_ERROR without leaking the cause', async () => {
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockRejectedValue(new Error('private network detail'));

    const error = await analyzeImage(
      'data:image/jpeg;base64,AA==',
      {fetcher},
    ).catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(AnalysisApiError);
    expect(error).toMatchObject({code: 'NETWORK_ERROR'});
    expect(String(error)).not.toContain('private network detail');
  });

  it('maps malformed success JSON to ANALYSIS_FAILED', async () => {
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockResolvedValue(response('{not-json'));

    await expect(
      analyzeImage('data:image/jpeg;base64,AA==', {fetcher}),
    ).rejects.toMatchObject({code: 'ANALYSIS_FAILED'});
  });

  it.each([true, false])(
    'maps a transport failure while reading a response body to NETWORK_ERROR (ok=%s)',
    async (ok) => {
      const fetcher = vi.fn<typeof fetch>();
      fetcher.mockResolvedValue({
        ok,
        json: vi.fn().mockRejectedValue(new TypeError('terminated')),
      } as unknown as Response);

      const error = await analyzeImage('data:image/jpeg;base64,AA==', {
        fetcher,
      }).catch((caught: unknown) => caught);

      expect(error).toMatchObject({code: 'NETWORK_ERROR'});
      expect(String(error)).not.toContain('terminated');
    },
  );

  it('rejects a success body that does not match the analysis contract', async () => {
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockResolvedValue(response({food_detected: true}));

    await expect(
      analyzeImage('data:image/jpeg;base64,AA==', {fetcher}),
    ).rejects.toMatchObject({code: 'ANALYSIS_FAILED'});
  });

  it('rejects extra keys at every response object level', async () => {
    const malformed: unknown[] = [
      {...analysisFixture, unexpected: true},
      {
        ...analysisFixture,
        food_names: {...analysisFixture.food_names, unexpected: true},
      },
      {
        ...analysisFixture,
        nutrients: {...analysisFixture.nutrients, unexpected: 1},
      },
      {
        ...analysisFixture,
        confidence: {...analysisFixture.confidence, unexpected: 'high'},
      },
      {
        ...analysisFixture,
        confidence: {
          ...analysisFixture.confidence,
          nutrients: {
            ...analysisFixture.confidence.nutrients,
            unexpected: 'high',
          },
        },
      },
      {
        ...analysisFixture,
        assessment: {...analysisFixture.assessment, unexpected: true},
      },
      {
        ...analysisFixture,
        assessment: {
          ...analysisFixture.assessment,
          statuses: {
            ...analysisFixture.assessment.statuses,
            unexpected: 'appropriate',
          },
        },
      },
    ];

    for (const body of malformed) {
      const fetcher = vi.fn<typeof fetch>();
      fetcher.mockResolvedValue(response(body));
      await expect(
        analyzeImage('data:image/jpeg;base64,AA==', {fetcher}),
      ).rejects.toMatchObject({code: 'ANALYSIS_FAILED'});
    }
  });

  it('rejects out-of-range values, invalid names, and invalid assumptions', async () => {
    const negativePortion = cloneFixture(analysisFixture);
    negativePortion.portion_grams = -1;
    const excessiveCalories = cloneFixture(analysisFixture);
    excessiveCalories.nutrients.calories_kcal = 10_001;
    const excessiveProtein = cloneFixture(analysisFixture);
    excessiveProtein.nutrients.protein_g = 2_001;
    const excessiveSodium = cloneFixture(analysisFixture);
    excessiveSodium.nutrients.sodium_mg = 100_001;
    const emptyName = cloneFixture(analysisFixture);
    emptyName.food_names!.ja = ' ';
    const longName = cloneFixture(analysisFixture);
    longName.food_names!.en = 'x'.repeat(121);
    const duplicateAssumption = cloneFixture(analysisFixture);
    duplicateAssumption.assumption_keys = [
      'visible_portion_only',
      'visible_portion_only',
    ];
    const invalidAssumption = cloneFixture(analysisFixture);
    invalidAssumption.assumption_keys = ['untrusted'];

    for (const body of [
      negativePortion,
      excessiveCalories,
      excessiveProtein,
      excessiveSodium,
      emptyName,
      longName,
      duplicateAssumption,
      invalidAssumption,
    ]) {
      const fetcher = vi.fn<typeof fetch>();
      fetcher.mockResolvedValue(response(body));
      await expect(
        analyzeImage('data:image/jpeg;base64,AA==', {fetcher}),
      ).rejects.toMatchObject({code: 'ANALYSIS_FAILED'});
    }
  });

  it('rejects contradictory normalized no-food responses', async () => {
    const withNames = cloneFixture(noFoodFixture);
    withNames.food_names = analysisFixture.food_names;
    const withPortion = cloneFixture(noFoodFixture);
    withPortion.portion_grams = 1;
    const withNutrient = cloneFixture(noFoodFixture);
    withNutrient.nutrients.fiber_g = 1;
    const withScore = cloneFixture(noFoodFixture);
    withScore.assessment.score = 0;
    const withStatus = cloneFixture(noFoodFixture);
    withStatus.assessment.statuses.sodium_mg = 'appropriate';
    const withSuggestion = cloneFixture(noFoodFixture);
    withSuggestion.assessment.suggestion_keys = ['reduce_sauce'];
    const markedSufficient = cloneFixture(noFoodFixture);
    markedSufficient.assessment.insufficient_data = false;

    for (const body of [
      withNames,
      withPortion,
      withNutrient,
      withScore,
      withStatus,
      withSuggestion,
      markedSufficient,
    ]) {
      const fetcher = vi.fn<typeof fetch>();
      fetcher.mockResolvedValue(response(body));
      await expect(
        analyzeImage('data:image/jpeg;base64,AA==', {fetcher}),
      ).rejects.toMatchObject({code: 'ANALYSIS_FAILED'});
    }
  });

  it('rejects incoherent food assessment fields', async () => {
    const wrongTier = cloneFixture(analysisFixture);
    wrongTier.assessment.score = 79;
    wrongTier.assessment.tier = 'balanced';
    const contradictoryInsufficient = cloneFixture(analysisFixture);
    contradictoryInsufficient.assessment.insufficient_data = true;
    const impossibleStatus = cloneFixture(analysisFixture);
    impossibleStatus.nutrients.fiber_g = null;
    impossibleStatus.assessment.score = null;
    impossibleStatus.assessment.tier = 'indeterminate';
    impossibleStatus.assessment.insufficient_data = true;
    impossibleStatus.assessment.statuses.fiber_g = 'appropriate';
    const lowConfidenceScore = cloneFixture(analysisFixture);
    lowConfidenceScore.confidence.overall = 'low';

    for (const body of [
      wrongTier,
      contradictoryInsufficient,
      impossibleStatus,
      lowConfidenceScore,
    ]) {
      const fetcher = vi.fn<typeof fetch>();
      fetcher.mockResolvedValue(response(body));
      await expect(
        analyzeImage('data:image/jpeg;base64,AA==', {fetcher}),
      ).rejects.toMatchObject({code: 'ANALYSIS_FAILED'});
    }
  });

  it('aborts a half-open request at the client timeout', async () => {
    vi.useFakeTimers();
    const fetcher = pendingFetch();
    const request = analyzeImage('data:image/jpeg;base64,AA==', {
      fetcher,
      timeoutMs: ANALYSIS_TIMEOUT_MS,
    });
    const rejection = expect(request).rejects.toMatchObject({
      code: 'NETWORK_ERROR',
    });

    await vi.advanceTimersByTimeAsync(ANALYSIS_TIMEOUT_MS);
    await rejection;
    expect(fetcher.mock.calls[0][1]?.signal?.aborted).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('forwards an external abort and clears the timeout', async () => {
    vi.useFakeTimers();
    const fetcher = pendingFetch();
    const controller = new AbortController();
    const request = analyzeImage('data:image/jpeg;base64,AA==', {
      fetcher,
      signal: controller.signal,
    });
    const rejection = expect(request).rejects.toMatchObject({
      code: 'NETWORK_ERROR',
    });

    controller.abort();
    await rejection;
    expect(fetcher.mock.calls[0][1]?.signal?.aborted).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('clears its timeout after a successful response', async () => {
    vi.useFakeTimers();
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockResolvedValue(response(analysisFixture));

    await analyzeImage('data:image/jpeg;base64,AA==', {fetcher});

    expect(vi.getTimerCount()).toBe(0);
  });
});
