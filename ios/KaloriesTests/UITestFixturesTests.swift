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

    func testEnvironmentRejectsDuplicateAdultAccessArguments() {
        let argumentSets = [
            [
                "Kalories", "--ui-testing", "--fixture-success",
                "--adult-access-confirmed", "--adult-access-confirmed",
            ],
            [
                "Kalories", "--ui-testing", "--fixture-success",
                "--reset-adult-access", "--reset-adult-access",
            ],
        ]

        assertInvalidConfigurations(argumentSets)
    }

    func testEnvironmentRejectsContradictoryAdultAccessArguments() {
        assertInvalidConfigurations([
            [
                "Kalories", "--ui-testing", "--fixture-success",
                "--adult-access-confirmed", "--reset-adult-access",
            ],
        ])
    }

    func testEnvironmentRejectsAdultAccessArgumentsOutsideUITesting() {
        assertInvalidConfigurations([
            ["Kalories", "--adult-access"],
            ["Kalories", "--adult-access-confirmed"],
            ["Kalories", "--reset-adult-access"],
            ["Kalories", "--fixture-success", "--adult-access-confirmed"],
            ["Kalories", "--fixture-success", "--reset-adult-access"],
        ])
    }

    func testEnvironmentRejectsUnknownAdultAccessArgument() {
        assertInvalidConfigurations([
            [
                "Kalories", "--ui-testing", "--fixture-success",
                "--adult-access",
            ],
            [
                "Kalories", "--ui-testing", "--fixture-success",
                "--adult-access-unknown",
            ],
            [
                "Kalories", "--ui-testing", "--fixture-success",
                "--adult-access=confirmed",
            ],
        ])
    }

    private func assertInvalidConfigurations(
        _ argumentSets: [[String]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for arguments in argumentSets {
            XCTAssertThrowsError(
                try UITestFixtures.environmentIfRequested(arguments: arguments),
                "Expected invalid configuration for \(arguments)",
                file: file,
                line: line
            ) { error in
                XCTAssertEqual(
                    error as? AppFailure,
                    .invalidConfiguration,
                    file: file,
                    line: line
                )
            }
        }
    }
}
#endif
