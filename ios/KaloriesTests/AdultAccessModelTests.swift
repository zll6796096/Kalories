import XCTest
@testable import Kalories

final class AdultAccessModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var registrationDomain: [String: Any]!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "AdultAccessModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        registrationDomain = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        var cleanRegistrationDomain = registrationDomain!
        cleanRegistrationDomain.removeValue(forKey: AdultAccessPreference.storageKey)
        defaults.setVolatileDomain(
            cleanRegistrationDomain,
            forName: UserDefaults.registrationDomain
        )
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults.setVolatileDomain(registrationDomain, forName: UserDefaults.registrationDomain)
        defaults = nil
        registrationDomain = nil
        suiteName = nil
    }

    @MainActor
    func testStorageKeyIsVersionedAndMissingValueDeniesAccess() {
        XCTAssertEqual(
            AdultAccessPreference.storageKey,
            "kalories.adult-access.confirmed.v1"
        )
        XCTAssertFalse(AdultAccessModel(preference: makePreference()).isConfirmed)
    }

    @MainActor
    func testRegisteredDefaultTrueWithoutPersistentValueDeniesAccess() {
        defaults.register(defaults: [AdultAccessPreference.storageKey: true])

        XCTAssertNil(
            defaults.persistentDomain(forName: suiteName)?[AdultAccessPreference.storageKey]
        )
        XCTAssertFalse(AdultAccessModel(preference: makePreference()).isConfirmed)
    }

    @MainActor
    func testOnlyLiteralTrueGrantsAccess() {
        for value in [false, "true", 1] as [Any] {
            defaults.removeObject(forKey: AdultAccessPreference.storageKey)
            defaults.set(value, forKey: AdultAccessPreference.storageKey)
            XCTAssertFalse(
                AdultAccessModel(preference: makePreference()).isConfirmed
            )
        }
        defaults.removeObject(forKey: AdultAccessPreference.storageKey)
        defaults.set(true, forKey: AdultAccessPreference.storageKey)
        XCTAssertTrue(AdultAccessModel(preference: makePreference()).isConfirmed)
    }

    @MainActor
    func testConfirmPersistsOnlyOneBooleanAndUpdatesState() throws {
        let model = AdultAccessModel(preference: makePreference())
        model.confirm()

        XCTAssertTrue(model.isConfirmed)
        let domain = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(domain.count, 1)
        XCTAssertEqual(domain[AdultAccessPreference.storageKey] as? Bool, true)
    }

    private func makePreference() -> AdultAccessPreference {
        AdultAccessPreference(defaults: defaults, persistentDomainName: suiteName)
    }
}
