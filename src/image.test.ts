import {describe, expect, it} from 'vitest';

import {
  MAX_DECODED_IMAGE_BYTES,
  MAX_REQUEST_BODY_BYTES,
  decodedBase64ByteLength,
  fitWithinDimensions,
  isWithinAnalysisLimits,
  parseImageDataUrl,
  prepareImageForAnalysis,
  type ImagePreparationRuntime,
} from './image';

describe('parseImageDataUrl', () => {
  it.each(['image/jpeg', 'image/png', 'image/webp'] as const)(
    'parses supported %s data URLs',
    (mimeType) => {
      expect(parseImageDataUrl(`data:${mimeType};base64,AA==`)).toEqual({
        mimeType,
        base64: 'AA==',
      });
    },
  );

  it('rejects an unsupported image format with a stable code', () => {
    expect(() =>
      parseImageDataUrl('data:image/gif;base64,AA=='),
    ).toThrowError(
      expect.objectContaining({
        code: 'UNSUPPORTED_IMAGE',
      }),
    );
  });

  it.each([
    'not-a-data-url',
    'data:image/jpeg,AA==',
    'data:image/jpeg;base64,',
    'data:image/jpeg;base64,%%%',
  ])('rejects malformed input %s', (input) => {
    expect(() => parseImageDataUrl(input)).toThrowError(
      expect.objectContaining({
        code: 'INVALID_IMAGE',
      }),
    );
  });
});

describe('decodedBase64ByteLength', () => {
  it.each([
    ['AA==', 1],
    ['AAA=', 2],
    ['AAAA', 3],
    ['AQIDBAU=', 5],
  ])('reports the decoded length of %s as %i bytes', (base64, bytes) => {
    expect(decodedBase64ByteLength(base64)).toBe(bytes);
  });

  it('rejects invalid base64 instead of estimating it', () => {
    expect(() => decodedBase64ByteLength('A===')).toThrowError(
      expect.objectContaining({
        code: 'INVALID_IMAGE',
      }),
    );
  });
});

describe('fitWithinDimensions', () => {
  it('fits a landscape image to the longest edge without distortion', () => {
    expect(fitWithinDimensions(4000, 2000)).toEqual({
      width: 1600,
      height: 800,
    });
  });

  it('fits a portrait image to the longest edge without distortion', () => {
    expect(fitWithinDimensions(2000, 4000)).toEqual({
      width: 800,
      height: 1600,
    });
  });

  it('does not upscale an already-small image', () => {
    expect(fitWithinDimensions(800, 600)).toEqual({
      width: 800,
      height: 600,
    });
  });
});

describe('isWithinAnalysisLimits', () => {
  it('accepts only when decoded bytes and the JSON request envelope fit', () => {
    const small = `data:image/jpeg;base64,${'A'.repeat(1024)}`;
    const decodedOversizedBase64 = 'A'.repeat(
      Math.ceil((MAX_DECODED_IMAGE_BYTES + 1) / 3) * 4,
    );
    const envelopeOversizedBase64 = 'A'.repeat(MAX_REQUEST_BODY_BYTES);

    expect(isWithinAnalysisLimits(small)).toBe(true);
    expect(
      isWithinAnalysisLimits(
        `data:image/jpeg;base64,${decodedOversizedBase64}`,
      ),
    ).toBe(false);
    expect(
      isWithinAnalysisLimits(
        `data:image/jpeg;base64,${envelopeOversizedBase64}`,
      ),
    ).toBe(false);
  });
});

describe('prepareImageForAnalysis', () => {
  it('uses bounded quality attempts and returns only a payload within limits', async () => {
    const attempts: Array<{
      width: number;
      height: number;
      quality: number;
    }> = [];
    const prepared = 'data:image/jpeg;base64,AA==';
    const runtime: ImagePreparationRuntime = {
      load: async () => ({width: 4000, height: 2000, source: {}}),
      encode: (_source, width, height, quality) => {
        attempts.push({width, height, quality});
        return attempts.length === 3 ? prepared : 'invalid-output';
      },
    };

    await expect(
      prepareImageForAnalysis(
        'data:image/jpeg;base64,AA==',
        runtime,
      ),
    ).resolves.toBe(prepared);
    expect(attempts).toEqual([
      {width: 1600, height: 800, quality: 0.82},
      {width: 1600, height: 800, quality: 0.68},
      {width: 1600, height: 800, quality: 0.54},
    ]);
    expect(isWithinAnalysisLimits(prepared)).toBe(true);
  });

  it('stops after twelve failed encoding attempts', async () => {
    let attempts = 0;
    const runtime: ImagePreparationRuntime = {
      load: async () => ({width: 4000, height: 2000, source: {}}),
      encode: () => {
        attempts += 1;
        return 'invalid-output';
      },
    };

    await expect(
      prepareImageForAnalysis(
        'data:image/jpeg;base64,AA==',
        runtime,
      ),
    ).rejects.toMatchObject({code: 'IMAGE_TOO_LARGE'});
    expect(attempts).toBe(12);
  });
});
