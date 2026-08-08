import XCTest
@testable import Kalories

#if DEBUG
@MainActor
final class UITestFixturesTests: XCTestCase {
    func testAppEnvironmentFixtureReturnsBeforeFirebaseBootstrap() throws {
        var bootstrapCalls = 0

        let environment = try AppEnvironment.live(
            bundle: Bundle(for: Self.self),
            arguments: ["Kalories", "--ui-testing", "--fixture-success"],
            appCheckBootstrap: {
                bootstrapCalls += 1
                throw AppFailure.appCheckUnavailable
            }
        )

        XCTAssertEqual(bootstrapCalls, 0)
        XCTAssertEqual(environment.privacyURL.host, "kalories.invalid")
    }

    func testEnvironmentIsInactiveWithoutUITesting() throws {
        let argumentSets = [
            ["Kalories"],
            ["Kalories", "--fixture-success"],
            ["Kalories", "--fixture-unknown"],
        ]

        for arguments in argumentSets {
            XCTAssertNil(
                try UITestFixtures.environmentIfRequested(arguments: arguments),
                "Unexpected fixture environment for \(arguments)"
            )
        }
    }

    func testEnvironmentAcceptsExactlyOneRecognizedFixtureMode() throws {
        let argumentSets = [
            ["Kalories", "--ui-testing", "--fixture-success"],
            [
                "Kalories", "--ui-testing", "--fixture-timeout",
                "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP",
            ],
        ]

        for arguments in argumentSets {
            XCTAssertNotNil(
                try UITestFixtures.environmentIfRequested(arguments: arguments),
                "Expected fixture environment for \(arguments)"
            )
        }
    }

    func testEnvironmentRejectsMissingDuplicateUnknownAndAmbiguousFixtureModes() {
        let argumentSets = [
            ["Kalories", "--ui-testing"],
            ["Kalories", "--ui-testing", "--fixture-success", "--fixture-timeout"],
            ["Kalories", "--ui-testing", "--fixture-success", "--fixture-success"],
            ["Kalories", "--ui-testing", "--fixture-timeout", "--fixture-timeout"],
            ["Kalories", "--ui-testing", "--fixture-unknown"],
            ["Kalories", "--ui-testing", "--fixture-success", "--fixture-unknown"],
        ]

        for arguments in argumentSets {
            XCTAssertThrowsError(
                try UITestFixtures.environmentIfRequested(arguments: arguments),
                "Expected invalid configuration for \(arguments)"
            ) { error in
                XCTAssertEqual(error as? AppFailure, .invalidConfiguration)
            }
        }
    }
}
#endif
