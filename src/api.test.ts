import {describe, expect, it, vi} from 'vitest';

import {AnalysisApiError, analyzeImage} from './api';
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
    calories_kcal: 640,
    protein_g: 34,
    carbs_g: 68,
    fat_g: 24,
    fiber_g: 8.4,
    sugar_g: 12,
    sodium_mg: 980,
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
  assumption_keys: ['visible_portion_only'],
  assessment: {
    score: 82,
    tier: 'balanced',
    statuses: {
      calories_kcal: 'appropriate',
      protein_g: 'appropriate',
      carbs_g: 'appropriate',
      fat_g: 'appropriate',
      fiber_g: 'appropriate',
      sugar_g: 'low',
      sodium_mg: 'high',
    },
    suggestion_keys: ['reduce_sauce'],
    scoring_reasons: ['macro_balance'],
    insufficient_data: false,
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

describe('analyzeImage', () => {
  it('posts the image and returns the complete typed analysis contract', async () => {
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockResolvedValue(response(analysisFixture));

    await expect(
      analyzeImage('data:image/jpeg;base64,AA==', fetcher),
    ).resolves.toEqual(analysisFixture);
    expect(fetcher).toHaveBeenCalledWith('/api/analyze', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({image: 'data:image/jpeg;base64,AA=='}),
    });
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
      analyzeImage('data:image/jpeg;base64,AA==', fetcher),
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
        analyzeImage('data:image/jpeg;base64,AA==', fetcher),
      ).rejects.toMatchObject({code: 'ANALYSIS_FAILED'});
    },
  );

  it('maps a rejected request to NETWORK_ERROR without leaking the cause', async () => {
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockRejectedValue(new Error('private network detail'));

    const error = await analyzeImage(
      'data:image/jpeg;base64,AA==',
      fetcher,
    ).catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(AnalysisApiError);
    expect(error).toMatchObject({code: 'NETWORK_ERROR'});
    expect(String(error)).not.toContain('private network detail');
  });

  it('maps malformed success JSON to ANALYSIS_FAILED', async () => {
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockResolvedValue(response('{not-json'));

    await expect(
      analyzeImage('data:image/jpeg;base64,AA==', fetcher),
    ).rejects.toMatchObject({code: 'ANALYSIS_FAILED'});
  });

  it('rejects a success body that does not match the analysis contract', async () => {
    const fetcher = vi.fn<typeof fetch>();
    fetcher.mockResolvedValue(response({food_detected: true}));

    await expect(
      analyzeImage('data:image/jpeg;base64,AA==', fetcher),
    ).rejects.toMatchObject({code: 'ANALYSIS_FAILED'});
  });
});
