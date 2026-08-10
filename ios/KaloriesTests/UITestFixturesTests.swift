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

    func testScreenshotModesReturnBeforeFirebaseBootstrap() throws {
        let defaults = UserDefaults.standard
        let persistentDomainName = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let storageKey = AdultAccessPreference.storageKey
        let originalPersistentValue = defaults
            .persistentDomain(forName: persistentDomainName)?[storageKey]
        defer {
            defaults.removeObject(forKey: storageKey)
            if let originalPersistentValue {
                defaults.set(originalPersistentValue, forKey: storageKey)
            }
        }

        let modes = [
            "--fixture-screenshot-capture",
            "--fixture-screenshot-preview",
            "--fixture-screenshot-summary",
            "--fixture-screenshot-nutrition",
            "--fixture-screenshot-uncertainty",
        ]

        for mode in modes {
            defaults.removeObject(forKey: storageKey)
            XCTAssertNil(
                defaults.persistentDomain(forName: persistentDomainName)?[storageKey],
                mode
            )

            var unconfirmedBootstrapCalls = 0
            let unconfirmedEnvironment = try AppEnvironment.live(
                bundle: Bundle(for: Self.self),
                arguments: [
                    "Kalories",
                    "--ui-testing",
                    mode,
                ],
                appCheckBootstrap: {
                    unconfirmedBootstrapCalls += 1
                    throw AppFailure.appCheckUnavailable
                }
            )

            XCTAssertEqual(unconfirmedBootstrapCalls, 0, mode)
            XCTAssertFalse(unconfirmedEnvironment.adultAccess.isConfirmed, mode)

            defaults.removeObject(forKey: storageKey)
            XCTAssertNil(
                defaults.persistentDomain(forName: persistentDomainName)?[storageKey],
                mode
            )

            var confirmedBootstrapCalls = 0
            let confirmedEnvironment = try AppEnvironment.live(
                bundle: Bundle(for: Self.self),
                arguments: [
                    "Kalories",
                    "--ui-testing",
                    "--adult-access-confirmed",
                    mode,
                ],
                appCheckBootstrap: {
                    confirmedBootstrapCalls += 1
                    throw AppFailure.appCheckUnavailable
                }
            )

            XCTAssertEqual(confirmedBootstrapCalls, 0, mode)
            XCTAssertTrue(confirmedEnvironment.adultAccess.isConfirmed, mode)
            XCTAssertTrue(UITestFixtures.isScreenshotMode(arguments: [mode]), mode)
            XCTAssertEqual(confirmedEnvironment.privacyURL.host, "kalories.invalid", mode)
        }
    }

    func testScreenshotModeRecognitionIsExact() {
        XCTAssertFalse(UITestFixtures.isScreenshotMode(arguments: []))
        XCTAssertFalse(UITestFixtures.isScreenshotMode(arguments: ["--fixture-success"]))
        XCTAssertFalse(
            UITestFixtures.isScreenshotMode(arguments: ["--fixture-screenshot-unknown"])
        )
        XCTAssertFalse(
            UITestFixtures.isScreenshotMode(arguments: ["--fixture-screenshot-result"])
        )
        for mode in [
            "--fixture-screenshot-capture",
            "--fixture-screenshot-preview",
            "--fixture-screenshot-summary",
            "--fixture-screenshot-nutrition",
            "--fixture-screenshot-uncertainty",
        ] {
            XCTAssertTrue(UITestFixtures.isScreenshotMode(arguments: [mode]), mode)
        }
    }

    func testResultScreenshotFrameRecognitionIsExactAndFailClosed() {
        XCTAssertEqual(
            UITestFixtures.resultScreenshotFrame(
                arguments: ["--fixture-screenshot-summary"]
            ),
            .summary
        )
        XCTAssertEqual(
            UITestFixtures.resultScreenshotFrame(
                arguments: ["--fixture-screenshot-nutrition"]
            ),
            .nutrition
        )
        XCTAssertEqual(
            UITestFixtures.resultScreenshotFrame(
                arguments: ["--fixture-screenshot-uncertainty"]
            ),
            .uncertainty
        )

        let rejectedArgumentSets = [
            [String](),
            ["--fixture-screenshot-result"],
            ["--fixture-screenshot-unknown"],
            ["--fixture-screenshot-summary", "--fixture-screenshot-summary"],
            ["--fixture-screenshot-summary", "--fixture-screenshot-nutrition"],
            ["--fixture-screenshot-nutrition", "--fixture-screenshot-uncertainty"],
            ["--fixture-screenshot-summary", "--fixture-success"],
        ]
        for arguments in rejectedArgumentSets {
            XCTAssertNil(
                UITestFixtures.resultScreenshotFrame(arguments: arguments),
                "Unexpected screenshot frame for \(arguments)"
            )
        }
    }

    func testScreenshotPreviewUsesLandscapeSyntheticMealImage() throws {
        let environment = try XCTUnwrap(
            UITestFixtures.environmentIfRequested(
                arguments: [
                    "Kalories",
                    "--ui-testing",
                    "--fixture-screenshot-preview",
                ]
            )
        )
        let image = try XCTUnwrap(environment.flow.selectedImage)

        XCTAssertEqual(image.size, CGSize(width: 960, height: 360))
        XCTAssertGreaterThan(image.size.width, image.size.height * 2)
        XCTAssertEqual(image.scale, 1)
        XCTAssertEqual(image.cgImage?.alphaInfo, .noneSkipLast)
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
            [
                "Kalories", "--ui-testing",
                "--fixture-screenshot-capture", "--fixture-success",
            ],
            [
                "Kalories", "--ui-testing",
                "--fixture-screenshot-preview", "--fixture-screenshot-summary",
            ],
            [
                "Kalories", "--ui-testing",
                "--fixture-screenshot-summary", "--fixture-screenshot-nutrition",
            ],
            [
                "Kalories", "--ui-testing",
                "--fixture-screenshot-nutrition", "--fixture-screenshot-uncertainty",
            ],
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
