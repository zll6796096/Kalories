import {existsSync, readFileSync} from 'node:fs';

import {describe, expect, it} from 'vitest';

const indexHtml = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const faviconUrl = new URL('../public/favicon.svg', import.meta.url);

describe('product metadata', () => {
  it('uses the Kalories title, Japanese fallback language, and product icon', () => {
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
