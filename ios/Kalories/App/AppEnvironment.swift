import Foundation

@MainActor
struct AppEnvironment {
    struct Links: Equatable, Sendable {
        let privacy: URL
        let support: URL
    }

    let flow: AppFlowModel
    let localizer: AppLocalizer
    let cameraPresentation: CameraPresentationController
    let privacyURL: URL
    let supportURL: URL

    static func live(bundle: Bundle = .main) throws -> AppEnvironment {
#if DEBUG
        if let fixtureEnvironment = try UITestFixtures.environmentIfRequested() {
            return fixtureEnvironment
        }
#endif

        let configuration = try AppConfiguration.from(bundle: bundle)
        let links = try links(for: configuration)
        let localePreference = AppLocalePreference(defaults: .standard)
        let locale = AppLocale.resolve(
            saved: localePreference.load()?.rawValue,
            preferred: Locale.preferredLanguages
        )

        let session = URLSession(configuration: .default)
        let service = AnalysisAPIClient(session: session, configuration: configuration)
        let processor = ImageProcessor()
        let flow = AppFlowModel(service: service, processor: processor)
        let cameraPresentation = CameraPresentationController(
            authorization: CameraAuthorizationService()
        )

        return AppEnvironment(
            flow: flow,
            localizer: AppLocalizer(locale: locale),
            cameraPresentation: cameraPresentation,
            privacyURL: links.privacy,
            supportURL: links.support
        )
    }

    static func links(for configuration: AppConfiguration) throws -> Links {
        let privacy = try directoryURL(path: "/privacy/", configuration: configuration)
        let support = try directoryURL(path: "/support/", configuration: configuration)
        return Links(privacy: privacy, support: support)
    }

    private static func directoryURL(
        path: String,
        configuration: AppConfiguration
    ) throws -> URL {
        guard var components = URLComponents(
            url: configuration.apiBaseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw AppFailure.invalidConfiguration
        }
        components.path = path

        guard
            let url = components.url,
            url.scheme == configuration.apiBaseURL.scheme,
            url.host == configuration.apiBaseURL.host,
            url.port == configuration.apiBaseURL.port,
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil
        else {
            throw AppFailure.invalidConfiguration
        }
        return url
    }
}
