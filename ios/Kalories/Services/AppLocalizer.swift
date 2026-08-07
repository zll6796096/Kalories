import Foundation

enum AppLocale: String, CaseIterable, Identifiable, Sendable {
    case ja
    case zh
    case en

    var id: String { rawValue }

    var bundleName: String {
        self == .zh ? "zh-Hans" : rawValue
    }

    static func resolve(saved: String?, preferred: [String]) -> AppLocale {
        if let savedLocale = locale(from: saved) {
            return savedLocale
        }

        for identifier in preferred {
            if let preferredLocale = locale(from: identifier) {
                return preferredLocale
            }
        }

        return .ja
    }

    private static func locale(from identifier: String?) -> AppLocale? {
        guard let identifier else {
            return nil
        }

        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        guard let base = normalized.split(separator: "-", omittingEmptySubsequences: false).first,
              !base.isEmpty else {
            return nil
        }

        return AppLocale(rawValue: String(base))
    }
}

struct AppLocalizer: Sendable {
    let locale: AppLocale

    func text(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: locale.bundleName, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

struct AppLocalePreference {
    static let storageKey = "kalories.locale"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppLocale? {
        defaults.string(forKey: Self.storageKey).flatMap(AppLocale.init(rawValue:))
    }

    func save(_ locale: AppLocale) {
        defaults.set(locale.rawValue, forKey: Self.storageKey)
    }
}
