import Foundation
import FirebaseAppCheck
import FirebaseCore

protocol AppCheckTokenProviding: Sendable {
    func token(forcingRefresh: Bool) async throws -> String
}

enum AppCheckProviderMode: Equatable, Sendable {
    case appAttest
    case debug
}

enum AppCheckProviderSelection {
    static func mode(
        isDebugBuild: Bool,
        environment: [String: String]
    ) -> AppCheckProviderMode {
        if
            isDebugBuild,
            environment["KALORIES_APP_CHECK_DEBUG"] == "1"
        {
            return .debug
        }
        return .appAttest
    }
}

struct FirebaseConfigurationIdentity: Equatable, Sendable {
    static let expectedBundleID = "com.ryuaistudio.kalories"

    let projectID: String
    let googleAppID: String

    init(bundleID: String, projectID: String, googleAppID: String) throws {
        let projectPattern = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/
        let appIDPattern = /^1:[0-9]{6,}:ios:[A-Za-z0-9]+$/
        guard
            bundleID == Self.expectedBundleID,
            projectID.wholeMatch(of: projectPattern) != nil,
            googleAppID.wholeMatch(of: appIDPattern) != nil
        else {
            throw AppFailure.invalidConfiguration
        }
        self.projectID = projectID
        self.googleAppID = googleAppID
    }
}

final class FirebaseAppCheckTokenProvider: AppCheckTokenProviding, @unchecked Sendable {
    private let appCheck: AppCheck

    init(appCheck: AppCheck) {
        self.appCheck = appCheck
    }

    func token(forcingRefresh: Bool) async throws -> String {
        let token = try await appCheck.token(forcingRefresh: forcingRefresh)
        return token.token
    }
}

@MainActor
enum FirebaseAppCheckBootstrap {
    static func configure(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> any AppCheckTokenProviding {
        guard
            let options = FirebaseOptions.defaultOptions(),
            let projectID = options.projectID
        else {
            throw AppFailure.invalidConfiguration
        }
        _ = try FirebaseConfigurationIdentity(
            bundleID: options.bundleID,
            projectID: projectID,
            googleAppID: options.googleAppID
        )
        guard bundle.bundleIdentifier == FirebaseConfigurationIdentity.expectedBundleID else {
            throw AppFailure.invalidConfiguration
        }

#if DEBUG
        let isDebugBuild = true
#else
        let isDebugBuild = false
#endif
        switch AppCheckProviderSelection.mode(
            isDebugBuild: isDebugBuild,
            environment: environment
        ) {
        case .appAttest:
            AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        case .debug:
#if DEBUG
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
#else
            throw AppFailure.invalidConfiguration
#endif
        }

        FirebaseApp.configure(options: options)
        return FirebaseAppCheckTokenProvider(appCheck: AppCheck.appCheck())
    }
}
