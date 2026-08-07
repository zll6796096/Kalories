import Foundation

actor AnalysisAPIClient: AnalysisServing {
    private static let maximumResponseBytes = 256 * 1024

    private let session: URLSession
    private let configuration: AppConfiguration
    private let decoder: StrictAnalysisDecoder

    init(
        session: URLSession,
        configuration: AppConfiguration,
        decoder: StrictAnalysisDecoder = StrictAnalysisDecoder()
    ) {
        self.session = session
        self.configuration = configuration
        self.decoder = decoder
    }

    func analyze(dataURI: String) async throws -> AnalysisResult {
        try Task.checkCancellation()

        let endpoint = configuration.apiBaseURL.appendingPathComponent("api/analyze")
        var request = URLRequest(url: endpoint, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(AnalysisRequest(image: dataURI))
        } catch {
            throw AppFailure.analysisFailed
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled, Task.isCancelled {
                throw CancellationError()
            }
            if error.code == .timedOut {
                throw AppFailure.timeout
            }
            throw AppFailure.network
        } catch {
            throw AppFailure.network
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppFailure.analysisFailed
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw Self.backendFailure(from: data, statusCode: httpResponse.statusCode)
        }

        guard data.count <= Self.maximumResponseBytes else {
            throw AppFailure.malformedResponse
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
        case "ANALYSIS_FAILED":
            return .analysisFailed
        default:
            return statusCode == 429 ? .rateLimited : .analysisFailed
        }
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
