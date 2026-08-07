import Foundation

struct AppConfiguration: Sendable {
    let apiBaseURL: URL

    init(apiBaseURL: URL) throws {
        guard
            let components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false),
            components.scheme == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil,
            components.port == nil,
            components.path.isEmpty || components.path == "/",
            components.query == nil,
            components.fragment == nil
        else {
            throw AppFailure.invalidConfiguration
        }
        self.apiBaseURL = apiBaseURL
    }

    static func from(bundle: Bundle = .main) throws -> AppConfiguration {
        guard
            let scheme = bundle.object(forInfoDictionaryKey: "KaloriesAPIScheme") as? String,
            let host = bundle.object(forInfoDictionaryKey: "KaloriesAPIHost") as? String,
            scheme == "https",
            !host.isEmpty,
            let url = URL(string: "\(scheme)://\(host)")
        else {
            throw AppFailure.invalidConfiguration
        }
        return try AppConfiguration(apiBaseURL: url)
    }
}

enum AppFailure: Error, Equatable, Sendable {
    case cameraDenied, captureFailed, invalidImage, unsupportedImage
    case imageTooLarge, noFood, serviceNotConfigured, analysisFailed
    case network, timeout, rateLimited, malformedResponse, invalidConfiguration
}

protocol AnalysisServing: Sendable {
    func analyze(dataURI: String) async throws -> AnalysisResult
}
