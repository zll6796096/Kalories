import {readdirSync, readFileSync} from 'node:fs';
import {extname} from 'node:path';

import {renderToStaticMarkup} from 'react-dom/server';
import {describe, expect, it, vi} from 'vitest';

import App from './App';

const sourceRoot = new URL('.', import.meta.url);

function runtimeSources(directory: URL): string[] {
  return readdirSync(directory, {withFileTypes: true}).flatMap((entry) => {
    const child = new URL(`${entry.name}${entry.isDirectory() ? '/' : ''}`, directory);
    if (entry.isDirectory()) {
      return runtimeSources(child);
    }
    if (!['.ts', '.tsx'].includes(extname(entry.name)) || entry.name.includes('.test.')) {
      return [];
    }
    return [readFileSync(child, 'utf8')];
  });
}

describe('public web access boundary', () => {
  it('renders a localized iOS-only explanation and legal navigation', () => {
    vi.stubGlobal('navigator', {languages: ['ja-JP']});
    vi.stubGlobal('window', undefined);

    const html = renderToStaticMarkup(<App />);

    expect(html).toContain('写真分析はiOS版でご利用いただけます。');
    expect(html).toContain('このWebページでは写真の送信や分析を行いません。');
    expect(html).toContain('href="/privacy/"');
    expect(html).toContain('href="/support/"');
    expect(html).not.toContain('type="file"');
    expect(html).not.toContain('<video');
  });

  it('contains no executable browser analysis or camera path', () => {
    const runtimeSource = runtimeSources(sourceRoot).join('\n');

    expect(runtimeSource).not.toContain('/api/analyze');
    expect(runtimeSource).not.toMatch(/\bfetch\s*\(/);
    expect(runtimeSource).not.toContain('react-webcam');
    expect(runtimeSource).not.toContain('getUserMedia');
    expect(runtimeSource).not.toContain('getScreenshot');
  });
});
