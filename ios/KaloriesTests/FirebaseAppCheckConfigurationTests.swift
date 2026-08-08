import XCTest
@testable import Kalories

final class FirebaseAppCheckConfigurationTests: XCTestCase {
    func testReleaseAndOrdinaryDebugSelectOnlyAppAttest() {
        XCTAssertEqual(
            AppCheckProviderSelection.mode(
                isDebugBuild: false,
                environment: ["KALORIES_APP_CHECK_DEBUG": "1"]
            ),
            .appAttest
        )
        XCTAssertEqual(
            AppCheckProviderSelection.mode(
                isDebugBuild: true,
                environment: [:]
            ),
            .appAttest
        )
        XCTAssertEqual(
            AppCheckProviderSelection.mode(
                isDebugBuild: true,
                environment: ["KALORIES_APP_CHECK_DEBUG": "true"]
            ),
            .appAttest
        )
    }

    func testDebugProviderRequiresTheExactDebugBuildOptIn() {
        XCTAssertEqual(
            AppCheckProviderSelection.mode(
                isDebugBuild: true,
                environment: ["KALORIES_APP_CHECK_DEBUG": "1"]
            ),
            .debug
        )
    }

    func testFirebaseIdentityRequiresTheExactBundleAndBoundedIdentifiers() throws {
        let identity = try FirebaseConfigurationIdentity(
            bundleID: "com.ryuaistudio.kalories",
            projectID: "kalories-project",
            googleAppID: "1:123456789:ios:abcdef123456"
        )

        XCTAssertEqual(identity.projectID, "kalories-project")
        XCTAssertEqual(identity.googleAppID, "1:123456789:ios:abcdef123456")

        let invalidValues = [
            ("com.example.wrong", "kalories-project", "1:123456789:ios:abcdef123456"),
            ("com.ryuaistudio.kalories", "", "1:123456789:ios:abcdef123456"),
            ("com.ryuaistudio.kalories", "kalories project", "1:123456789:ios:abcdef123456"),
            ("com.ryuaistudio.kalories", "kalories-project", "not-an-app-id"),
            ("com.ryuaistudio.kalories", "kalories-project", "1:123456789:android:abcdef"),
        ]
        for (bundleID, projectID, googleAppID) in invalidValues {
            XCTAssertThrowsError(
                try FirebaseConfigurationIdentity(
                    bundleID: bundleID,
                    projectID: projectID,
                    googleAppID: googleAppID
                )
            ) { error in
                XCTAssertEqual(error as? AppFailure, .invalidConfiguration)
            }
        }
    }
}
