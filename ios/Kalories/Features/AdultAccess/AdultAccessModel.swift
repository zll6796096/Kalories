import CoreFoundation
import Foundation
import Observation

struct AdultAccessPreference {
    static let storageKey = "kalories.adult-access.confirmed.v1"

    private let defaults: UserDefaults
    private let persistentDomainName: String?

    init(
        defaults: UserDefaults = .standard,
        persistentDomainName: String? = Bundle.main.bundleIdentifier
    ) {
        self.defaults = defaults
        self.persistentDomainName = persistentDomainName
    }

    func load() -> Bool {
        guard
            let persistentDomainName,
            let value = defaults.persistentDomain(forName: persistentDomainName)?[Self.storageKey]
        else {
            return false
        }
        guard CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else {
            return false
        }
        return (value as? Bool) == true
    }

    func confirm() {
        defaults.set(true, forKey: Self.storageKey)
    }
}

@MainActor
@Observable
final class AdultAccessModel {
    private(set) var isConfirmed: Bool

    @ObservationIgnored
    private let preference: AdultAccessPreference

    init(preference: AdultAccessPreference) {
        self.preference = preference
        isConfirmed = preference.load()
    }

    func confirm() {
        preference.confirm()
        isConfirmed = preference.load()
    }
}
