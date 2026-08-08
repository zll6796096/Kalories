import Foundation

actor AnalysisAPIClient: AnalysisServing {
    private static let maximumResponseBytes = 256 * 1024

    private let session: URLSession
    private let configuration: AppConfiguration
    private let tokenProvider: any AppCheckTokenProviding
    private let decoder: StrictAnalysisDecoder

    init(
        session: URLSession,
        configuration: AppConfiguration,
        tokenProvider: any AppCheckTokenProviding,
        decoder: StrictAnalysisDecoder = StrictAnalysisDecoder()
    ) {
        self.session = session
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.decoder = decoder
    }

    func analyze(dataURI: String) async throws -> AnalysisResult {
        try await analyze(
            dataURI: dataURI,
            forcingTokenRefresh: false,
            mayRefreshAfterRejection: true
        )
    }

    private func analyze(
        dataURI: String,
        forcingTokenRefresh: Bool,
        mayRefreshAfterRejection: Bool
    ) async throws -> AnalysisResult {
        try Task.checkCancellation()

        let appCheckToken: String
        do {
            appCheckToken = try await tokenProvider.token(
                forcingRefresh: forcingTokenRefresh
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw AppFailure.appCheckUnavailable
        }
        guard
            !appCheckToken.isEmpty,
            appCheckToken == appCheckToken.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw AppFailure.appCheckUnavailable
        }

        let endpoint = configuration.apiBaseURL.appendingPathComponent("api/analyze")
        var request = URLRequest(url: endpoint, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        do {
            request.httpBody = try JSONEncoder().encode(AnalysisRequest(image: dataURI))
        } catch {
            throw AppFailure.analysisFailed
        }

        let redirectPolicy = AnalysisRedirectPolicy()
        let urlSession = session
        let configuredRequest = request
        let outcome: AnalysisTransportOutcome
        do {
            outcome = try await withThrowingTaskGroup(of: AnalysisTransportOutcome.self) { group in
                group.addTask {
                    let (data, response) = try await urlSession.data(
                        for: configuredRequest,
                        delegate: redirectPolicy
                    )
                    return .response(data, response)
                }
                group.addTask {
                    let didRedirect = await redirectPolicy.waitForRedirect()
                    try Task.checkCancellation()
                    guard didRedirect else {
                        throw CancellationError()
                    }
                    return .redirectRejected
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled {
                throw CancellationError()
            }
            if error.code == .timedOut {
                throw AppFailure.timeout
            }
            throw AppFailure.network
        } catch {
            throw AppFailure.network
        }

        guard case let .response(data, response) = outcome else {
            throw AppFailure.analysisFailed
        }

        guard data.count <= Self.maximumResponseBytes else {
            throw AppFailure.malformedResponse
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppFailure.analysisFailed
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let failure = Self.backendFailure(
                from: data,
                statusCode: httpResponse.statusCode
            )
            if
                failure == .appCheckFailed,
                httpResponse.statusCode == 401,
                mayRefreshAfterRejection
            {
                return try await analyze(
                    dataURI: dataURI,
                    forcingTokenRefresh: true,
                    mayRefreshAfterRejection: false
                )
            }
            throw failure
        }

        do {
            return try decoder.decode(data)
        } catch {
            throw AppFailure.malformedResponse
        }
    }

    private static func backendFailure(from data: Data, statusCode: Int) -> AppFailure {
        let code = try? JSONDecoder().decode(BackendErrorEnvelope.self, from: data).detail?.code
        switch code {
        case "INVALID_IMAGE":
            return .invalidImage
        case "UNSUPPORTED_IMAGE":
            return .unsupportedImage
        case "IMAGE_TOO_LARGE":
            return .imageTooLarge
        case "SERVICE_NOT_CONFIGURED":
            return .serviceNotConfigured
        case "RATE_LIMITED":
            return .rateLimited
        case "APP_CHECK_FAILED":
            return .appCheckFailed
        case "APP_CHECK_UNAVAILABLE":
            return .appCheckUnavailable
        case "ANALYSIS_FAILED":
            return .analysisFailed
        default:
            if statusCode == 401 {
                return .appCheckFailed
            }
            return statusCode == 429 ? .rateLimited : .analysisFailed
        }
    }
}

private enum AnalysisTransportOutcome: Sendable {
    case response(Data, URLResponse)
    case redirectRejected
}

private final class AnalysisRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let redirectEvents: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    override init() {
        (redirectEvents, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        super.init()
    }

    func waitForRedirect() async -> Bool {
        for await _ in redirectEvents {
            return true
        }
        return false
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        continuation.yield()
        completionHandler(nil)
    }

    deinit {
        continuation.finish()
    }
}

private struct AnalysisRequest: Encodable {
    let image: String
}

private struct BackendErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let code: String?
    }

    let detail: Detail?
}
