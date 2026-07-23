import {renderToStaticMarkup} from 'react-dom/server';
import {describe, expect, it} from 'vitest';

import {messages} from '../i18n';
import type {AnalysisResult} from '../types';
import {ResultScreen} from './ResultScreen';

const result: AnalysisResult = {
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
  assumption_keys: [],
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
    suggestion_keys: ['add_vegetables', 'reduce_sauce'],
    scoring_reasons: [],
    insufficient_data: false,
  },
};

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
    expect(html).toContain('82');
    expect(html).toContain('/100');
    expect(html).toContain('Balanced');

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
    expect(html).toContain(messages.en.suggestionAddVegetables);
    expect(html).toContain(messages.en.suggestionReduceSauce);
    expect(html.match(/Estimate confidence/g)?.length).toBeGreaterThanOrEqual(3);
    expect(html).toContain('Low');
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
    expect(html).not.toContain(messages.en.suggestionReduceSauce);
    expect(html).not.toContain(messages.en.suggestionReduceFat);
    expect(html).not.toContain('unknown_internal_rule');
  });

  it('renders language controls as pressed buttons rather than tabs', () => {
    const html = renderResult();

    expect(html).toContain('aria-label="Language"');
    expect(html.match(/<button/g)?.length).toBeGreaterThanOrEqual(5);
    expect(html).toContain('aria-pressed="true"');
    expect(html).not.toContain('role="tab"');
  });
});
