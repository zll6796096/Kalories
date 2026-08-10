import CoreFoundation
import Foundation
import Observation

struct AdultAccessPreference {
    static let storageKey = "kalories.adult-access.confirmed.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Bool {
        guard let value = defaults.object(forKey: Self.storageKey) else {
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
        isConfirmed = true
    }
}
