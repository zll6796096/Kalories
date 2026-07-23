import {renderToStaticMarkup} from 'react-dom/server';
import {describe, expect, it} from 'vitest';

import canonicalAnalysisFixture from '../../tests/fixtures/canonical_analysis_result.json';
import {messages} from '../i18n';
import type {AnalysisResult} from '../types';
import {ResultScreen} from './ResultScreen';

const result = canonicalAnalysisFixture as AnalysisResult;

const renderResult = (data: AnalysisResult = result) =>
  renderToStaticMarkup(
    <ResultScreen
      locale="en"
      text={messages.en}
      data={data}
      capturedImage="data:image/jpeg;base64,meal"
      onLocaleChange={() => undefined}
      onRetry={() => undefined}
      onRetake={() => undefined}
      onSaveError={() => undefined}
    />,
  );

describe('ResultScreen', () => {
  it('renders the complete localized result as one continuous page in reading order', () => {
    const html = renderResult();
    const sections = [
      'result-hero',
      'result-summary',
      'energy-summary',
      'macro-list',
      'secondary-nutrients',
      'advice-card',
      'result-footer',
    ];

    expect(html).toContain('<main class="result-page"');
    expect(html).toContain('Grilled salmon set');
    expect(html).toContain('64');
    expect(html).toContain('/100');
    expect(html).toContain('Mostly balanced');

    for (const value of [
      '640 kcal',
      '34 g',
      '68 g',
      '24 g',
      '8.4 g',
      '12 g',
      '980 mg',
      '420 g',
    ]) {
      expect(html).toContain(value);
    }

    for (let index = 1; index < sections.length; index += 1) {
      expect(html.indexOf(`class="${sections[index - 1]}`)).toBeLessThan(
        html.indexOf(`class="${sections[index]}`),
      );
    }

    expect(html).toContain(messages.en.disclaimer);
    expect(html).toContain(messages.en.referenceBasis);
    expect(html).toContain(messages.en.suggestionReduceSauce);
    expect(html).toContain(messages.en.suggestionAdjustStaple);
    expect(html.match(/Estimate confidence/g)?.length).toBeGreaterThanOrEqual(9);
    expect(html).toContain('Low');
    expect(html).toContain(
      'aria-label="Protein, Carbohydrates, Fat, Dietary fibre"',
    );
    expect(html).toContain(
      'aria-label="Sugars, Sodium, Estimated portion"',
    );
    expect(html).not.toContain('role="tab"');
    expect(html).not.toContain('role="dialog"');
    expect(html).not.toContain('<details');
  });

  it('uses an em dash for missing values and never fabricates zero', () => {
    const html = renderResult({
      ...result,
      nutrients: {...result.nutrients, sugar_g: null},
      assessment: {
        ...result.assessment,
        statuses: {...result.assessment.statuses, sugar_g: 'indeterminate'},
      },
    });
    const sugarRow = html.slice(
      html.indexOf('data-nutrient="sugar_g"'),
      html.indexOf('data-nutrient="sodium_mg"'),
    );

    expect(sugarRow).toContain('—');
    expect(sugarRow).not.toContain('0 g');
  });

  it('states when a score cannot be assessed without showing a false scale', () => {
    const html = renderResult({
      ...result,
      assessment: {
        ...result.assessment,
        score: null,
        tier: 'balanced',
        insufficient_data: true,
      },
    });

    expect(html).toContain(messages.en.tierIndeterminate);
    expect(html).toContain('—');
    expect(html).not.toContain('/100');
    expect(html).toContain(messages.en.retry);
  });

  it('limits advice to two known localized messages and hides unknown keys', () => {
    const html = renderResult({
      ...result,
      assessment: {
        ...result.assessment,
        suggestion_keys: [
          'unknown_internal_rule',
          'add_vegetables',
          'reduce_sauce',
          'reduce_fat',
        ],
      },
    });

    expect(html).toContain(messages.en.suggestionAddVegetables);
    expect(html).toContain(messages.en.suggestionReduceSauce);
    expect(html).not.toContain(messages.en.suggestionReduceFat);
    expect(html).not.toContain('unknown_internal_rule');
  });

  it('shows all localized assumptions, de-duplicates them, and hides unknown keys', () => {
    const html = renderResult({
      ...result,
      assumption_keys: [
        'visible_portion_only',
        'portion_estimated',
        'seasoning_estimated',
        'hidden_ingredients_possible',
        'visible_portion_only',
        'internal_provider_note',
      ],
    });

    expect(html).toContain(messages.en.assumptionsTitle);
    expect(html).toContain(messages.en.assumptionVisiblePortionOnly);
    expect(html).toContain(messages.en.assumptionPortionEstimated);
    expect(html).toContain(messages.en.assumptionSeasoningEstimated);
    expect(html).toContain(messages.en.assumptionHiddenIngredientsPossible);
    expect(
      html.match(
        new RegExp(messages.en.assumptionVisiblePortionOnly.replace('.', '\\.'), 'g'),
      )?.length,
    ).toBe(1);
    expect(html).not.toContain('internal_provider_note');
    expect(html.indexOf('class="uncertainty-block"')).toBeGreaterThan(
      html.indexOf('class="result-footer"'),
    );
    expect(html.indexOf('class="uncertainty-block"')).toBeLessThan(
      html.indexOf('class="reference-note"'),
    );
  });

  it('hides uncertainty and advice blocks when there is no known visible content', () => {
    const html = renderResult({
      ...result,
      assumption_keys: [],
      assessment: {
        ...result.assessment,
        suggestion_keys: [],
      },
    });

    expect(html).not.toContain('class="uncertainty-block"');
    expect(html).not.toContain('class="advice-card"');
    expect(html).not.toContain(messages.en.assumptionsTitle);
    expect(html).not.toContain(messages.en.adviceTitle);
  });

  it.each([
    [
      'zh',
      messages.zh.assumptionsTitle,
      messages.zh.assumptionVisiblePortionOnly,
      '语言',
    ],
    [
      'ja',
      messages.ja.assumptionsTitle,
      messages.ja.assumptionVisiblePortionOnly,
      '言語',
    ],
    [
      'en',
      messages.en.assumptionsTitle,
      messages.en.assumptionVisiblePortionOnly,
      'Language',
    ],
  ] as const)(
    'switches assumption copy to %s without changing analysis data',
    (locale, title, assumption, languageLabel) => {
      const html = renderToStaticMarkup(
        <ResultScreen
          locale={locale}
          text={messages[locale]}
          data={{...result, assumption_keys: ['visible_portion_only']}}
          capturedImage={null}
          onLocaleChange={() => undefined}
          onRetry={() => undefined}
          onRetake={() => undefined}
          onSaveError={() => undefined}
        />,
      );

      expect(html).toContain(title);
      expect(html).toContain(assumption);
      expect(html).toContain('640 kcal');
      expect(html).toContain(`aria-label="${languageLabel}"`);
    },
  );

  it('renders language controls as pressed buttons rather than tabs', () => {
    const html = renderResult();

    expect(html).toContain('aria-label="Language"');
    expect(html.match(/<button/g)?.length).toBeGreaterThanOrEqual(5);
    expect(html).toContain('aria-pressed="true"');
    expect(html).not.toContain('role="tab"');
  });

  it('keeps the shared canonical evaluator output visible', () => {
    const html = renderResult();
    const proteinRow = html.slice(
      html.indexOf('data-nutrient="protein_g"'),
      html.indexOf('data-nutrient="carbs_g"'),
    );
    const carbsRow = html.slice(
      html.indexOf('data-nutrient="carbs_g"'),
      html.indexOf('data-nutrient="fat_g"'),
    );
    const sodiumRow = html.slice(
      html.indexOf('data-nutrient="sodium_mg"'),
      html.indexOf('data-nutrient="portion_grams"'),
    );

    expect(result.assessment.score).toBe(64);
    expect(result.assessment.tier).toBe('mostly_balanced');
    expect(result.assessment.statuses.protein_g).toBe('high');
    expect(result.assessment.statuses.carbs_g).toBe('low');
    expect(result.assessment.statuses.fat_g).toBe('high');
    expect(result.assessment.statuses.sodium_mg).toBe('high');
    expect(result.assessment.suggestion_keys).toEqual([
      'reduce_sauce',
      'adjust_staple',
    ]);
    expect(html).toContain('64');
    expect(html).toContain(messages.en.tierMostlyBalanced);
    expect(proteinRow).toContain(messages.en.statusHigh);
    expect(carbsRow).toContain(messages.en.statusLow);
    expect(sodiumRow).toContain(messages.en.statusHigh);
    expect(html).toContain(messages.en.suggestionReduceSauce);
    expect(html).toContain(messages.en.suggestionAdjustStaple);
  });

  it('renders the save action initially enabled and not busy', () => {
    const html = renderResult();
    const saveButton = html.slice(
      html.indexOf('data-action="save-result"'),
      html.indexOf(messages.en.saveResult) + messages.en.saveResult.length,
    );

    expect(saveButton).toContain('aria-busy="false"');
    expect(saveButton).not.toContain('disabled=""');
  });
});
