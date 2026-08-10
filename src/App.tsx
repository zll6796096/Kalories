import {useEffect, useState} from 'react';
import {ShieldCheck, Sparkles, Smartphone} from 'lucide-react';

import {LanguageSwitcher} from './components/LanguageSwitcher';
import {
  documentLanguage,
  messages,
  persistLocale,
  resolveLocale,
  webMessages,
} from './i18n';
import type {Locale} from './types';

export default function App() {
  const [locale, setLocale] = useState<Locale>(() => resolveLocale());
  const text = messages[locale];
  const webText = webMessages[locale];

  useEffect(() => {
    document.documentElement.lang = documentLanguage(locale);
  }, [locale]);

  const handleLocaleChange = (nextLocale: Locale) => {
    setLocale(nextLocale);
    persistLocale(nextLocale);
  };

  return (
    <main className="public-page">
      <header className="public-toolbar">
        <span className="wordmark">{text.appName}</span>
        <LanguageSwitcher
          locale={locale}
          label={text.languageLabel}
          onChange={handleLocaleChange}
        />
      </header>

      <section className="public-hero" aria-labelledby="public-title">
        <div className="brand-mark" aria-hidden="true">
          <Sparkles strokeWidth={1.8} />
        </div>
        <p className="eyebrow">{text.introEyebrow}</p>
        <h1 id="public-title">{text.introTitle}</h1>
        <p className="hero-copy">{text.introBody}</p>
      </section>

      <section className="availability-card" aria-labelledby="availability-title">
        <Smartphone aria-hidden="true" />
        <div>
          <h2 id="availability-title">{webText.iosOnlyTitle}</h2>
          <p>{webText.noWebUpload}</p>
        </div>
      </section>

      <section className="trust-note" aria-label={webText.integrityTitle}>
        <ShieldCheck aria-hidden="true" />
        <div>
          <h2>{webText.integrityTitle}</h2>
          <p>{webText.integrityBody}</p>
        </div>
      </section>

      <nav className="public-links" aria-label={webText.legalNavigation}>
        <a href="/privacy/">{webText.privacy}</a>
        <a href="/support/">{webText.support}</a>
      </nav>
    </main>
  );
}
