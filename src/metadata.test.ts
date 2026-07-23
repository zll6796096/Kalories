import {existsSync, readFileSync} from 'node:fs';

import {describe, expect, it} from 'vitest';

const indexHtml = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const faviconUrl = new URL('../public/favicon.svg', import.meta.url);
const metadata = JSON.parse(
  readFileSync(new URL('../metadata.json', import.meta.url), 'utf8'),
) as {
  name?: unknown;
  description?: unknown;
  requestFramePermissions?: unknown;
};
const packageManifest = JSON.parse(
  readFileSync(new URL('../package.json', import.meta.url), 'utf8'),
) as {name?: unknown};

describe('product metadata', () => {
  it('uses the Kalories identity across product and npm manifests', () => {
    expect(metadata.name).toBe('Kalories');
    expect(typeof metadata.description).toBe('string');
    expect((metadata.description as string).trim()).not.toBe('');
    expect(metadata.requestFramePermissions).toEqual(['camera']);
    expect(Object.keys(metadata).sort()).toEqual([
      'description',
      'name',
      'requestFramePermissions',
    ]);
    expect(packageManifest.name).toBe('kalories');
    expect(indexHtml).toContain('<html lang="ja">');
    expect(indexHtml).toContain('<title>Kalories</title>');
    expect(indexHtml).toContain('<link rel="icon" href="/favicon.svg"');
  });

  it('keeps the favicon self-contained and script-free', () => {
    expect(existsSync(faviconUrl)).toBe(true);
    if (!existsSync(faviconUrl)) {
      return;
    }
    const faviconSvg = readFileSync(faviconUrl, 'utf8');

    expect(faviconSvg).toContain('<svg');
    expect(faviconSvg).toContain('</svg>');
    expect(faviconSvg).not.toContain('<script');
    expect(faviconSvg).not.toMatch(/(?:href|src)=["']https?:\/\//);
  });
});
