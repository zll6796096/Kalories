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
const repositoryFile = (name: string) =>
  new URL(`../${name}`, import.meta.url);
const readRepositoryFile = (name: string) => {
  const url = repositoryFile(name);
  return existsSync(url) ? readFileSync(url, 'utf8') : '';
};

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

describe('Python deployment metadata', () => {
  it('ignores the canonical and legacy local Python environments', () => {
    const ignoreRules = readRepositoryFile('.gitignore')
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith('#'));

    expect(ignoreRules).toContain('.venv/');
    expect(ignoreRules).toContain('venv/');
  });

  it('targets Python 3.12 for deployment and clean verification', () => {
    expect(existsSync(repositoryFile('.python-version'))).toBe(true);
    expect(readRepositoryFile('.python-version').trim()).toBe('3.12');
  });

  it('keeps only the seven human-maintained direct dependencies in requirements.in', () => {
    expect(existsSync(repositoryFile('requirements.in'))).toBe(true);
    expect(
      readRepositoryFile('requirements.in')
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean),
    ).toEqual([
      'fastapi',
      'uvicorn',
      'google-genai',
      'python-multipart',
      'pydantic',
      'python-dotenv',
      'Pillow>=11,<13',
    ]);
  });

  it('uses requirements.txt as the exact deployment lock', () => {
    expect(existsSync(repositoryFile('requirements.lock'))).toBe(false);
    const lines = readRepositoryFile('requirements.txt')
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith('#'));

    expect(lines.length).toBeGreaterThan(7);
    expect(
      lines.every((line) =>
        /^[A-Za-z0-9_.-]+==[A-Za-z0-9][A-Za-z0-9.!+_-]*$/.test(line),
      ),
    ).toBe(true);
    expect(lines.some((line) => /(?:^|[\s])(?:-e|--editable|--find-links)\b/.test(line))).toBe(
      false,
    );
    expect(lines.some((line) => /(?:file:|https?:|git\+)/i.test(line))).toBe(
      false,
    );

    const packageNames = new Set(
      lines.map((line) => line.split('==', 1)[0].toLowerCase().replaceAll('_', '-')),
    );
    for (const excludedPackage of [
      'pip',
      'setuptools',
      'wheel',
      'pip-audit',
      'pytest',
      'ruff',
    ]) {
      expect(packageNames.has(excludedPackage), excludedPackage).toBe(false);
    }
    for (const directPackage of [
      'fastapi',
      'uvicorn',
      'google-genai',
      'python-multipart',
      'pydantic',
      'python-dotenv',
      'pillow',
    ]) {
      expect(packageNames.has(directPackage), directPackage).toBe(true);
    }
  });
});
