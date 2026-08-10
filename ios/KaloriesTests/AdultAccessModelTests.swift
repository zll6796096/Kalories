import XCTest
@testable import Kalories

final class AdultAccessModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "AdultAccessModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    @MainActor
    func testStorageKeyIsVersionedAndMissingValueDeniesAccess() {
        XCTAssertEqual(
            AdultAccessPreference.storageKey,
            "kalories.adult-access.confirmed.v1"
        )
        XCTAssertFalse(AdultAccessModel(preference: .init(defaults: defaults)).isConfirmed)
    }

    @MainActor
    func testOnlyLiteralTrueGrantsAccess() {
        for value in [false, "true", 1] as [Any] {
            defaults.removeObject(forKey: AdultAccessPreference.storageKey)
            defaults.set(value, forKey: AdultAccessPreference.storageKey)
            XCTAssertFalse(
                AdultAccessModel(preference: .init(defaults: defaults)).isConfirmed
            )
        }
        defaults.removeObject(forKey: AdultAccessPreference.storageKey)
        defaults.set(true, forKey: AdultAccessPreference.storageKey)
        XCTAssertTrue(AdultAccessModel(preference: .init(defaults: defaults)).isConfirmed)
    }

    @MainActor
    func testConfirmPersistsOnlyOneBooleanAndUpdatesState() throws {
        let model = AdultAccessModel(preference: .init(defaults: defaults))
        model.confirm()

        XCTAssertTrue(model.isConfirmed)
        let domain = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(domain.count, 1)
        XCTAssertEqual(domain[AdultAccessPreference.storageKey] as? Bool, true)
    }
}
