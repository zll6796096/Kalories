import type {Locale} from '../types';

interface LanguageSwitcherProps {
  locale: Locale;
  label: string;
  onChange: (locale: Locale) => void;
}

const languageOptions: ReadonlyArray<{locale: Locale; label: string}> = [
  {locale: 'zh', label: '中文'},
  {locale: 'ja', label: '日本語'},
  {locale: 'en', label: 'EN'},
];

export function LanguageSwitcher({
  locale,
  label,
  onChange,
}: LanguageSwitcherProps) {
  return (
    <div className="language-switcher" role="group" aria-label={label}>
      {languageOptions.map((option) => (
        <button
          key={option.locale}
          className="language-option"
          type="button"
          aria-pressed={locale === option.locale}
          onClick={() => onChange(option.locale)}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}
