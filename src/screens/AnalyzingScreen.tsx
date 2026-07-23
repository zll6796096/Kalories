import {ScanLine} from 'lucide-react';

import {LanguageSwitcher} from '../components/LanguageSwitcher';
import type {Messages} from '../i18n';
import type {Locale} from '../types';

interface AnalyzingScreenProps {
  locale: Locale;
  text: Messages;
  capturedImage: string | null;
  onLocaleChange: (locale: Locale) => void;
}

export function AnalyzingScreen({
  locale,
  text,
  capturedImage,
  onLocaleChange,
}: AnalyzingScreenProps) {
  return (
    <main className="app-screen analyzing-screen">
      <header className="screen-toolbar">
        <span className="wordmark">{text.appName}</span>
        <LanguageSwitcher
          locale={locale}
          label={text.languageLabel}
          onChange={onLocaleChange}
        />
      </header>

      <section className="analyzing-card" aria-labelledby="analyzing-title">
        <div className="analysis-image-wrap">
          {capturedImage ? (
            <img
              className="analysis-image"
              src={capturedImage}
              alt={text.analyzingTitle}
            />
          ) : (
            <div className="analysis-placeholder" aria-hidden="true" />
          )}
          <div className="analysis-scan-line" aria-hidden="true" />
        </div>
        <div className="analysis-copy">
          <span className="analysis-icon" aria-hidden="true">
            <ScanLine />
          </span>
          <p className="eyebrow">{text.analyzingEyebrow}</p>
          <h1 id="analyzing-title">{text.analyzingTitle}</h1>
          <p className="screen-copy">{text.analyzingBody}</p>
          <div
            className="analysis-progress"
            role="progressbar"
            aria-label={text.analyzingTitle}
          >
            <span />
          </div>
        </div>
      </section>
    </main>
  );
}
