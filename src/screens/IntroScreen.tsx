import {Camera, Sparkles} from 'lucide-react';

import {LanguageSwitcher} from '../components/LanguageSwitcher';
import type {Messages} from '../i18n';
import type {Locale} from '../types';

interface IntroScreenProps {
  locale: Locale;
  text: Messages;
  onLocaleChange: (locale: Locale) => void;
  onStart: () => void;
}

export function IntroScreen({
  locale,
  text,
  onLocaleChange,
  onStart,
}: IntroScreenProps) {
  return (
    <main className="app-screen intro-screen">
      <header className="screen-toolbar">
        <span className="wordmark">{text.appName}</span>
        <LanguageSwitcher locale={locale} onChange={onLocaleChange} />
      </header>

      <section className="intro-card" aria-labelledby="intro-title">
        <div className="brand-mark" aria-hidden="true">
          <Sparkles strokeWidth={1.8} />
        </div>
        <p className="eyebrow">{text.introEyebrow}</p>
        <h1 id="intro-title">{text.introTitle}</h1>
        <p className="screen-copy">{text.introBody}</p>
        <button className="primary-button" type="button" onClick={onStart}>
          <Camera aria-hidden="true" size={20} />
          {text.startCamera}
        </button>
      </section>
    </main>
  );
}
