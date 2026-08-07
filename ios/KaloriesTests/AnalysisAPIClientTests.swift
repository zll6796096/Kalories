import Foundation
import XCTest
@testable import Kalories

final class AnalysisAPIClientTests: XCTestCase {
    private let expectedOrigin = "https://kalories-sxielk4wua-an.a.run.app"

    override func tearDown() {
        URLProtocolStub.clear()
        super.tearDown()
    }

    func testAnalyzeSendsExactRequestContract() async throws {
        let capturedRequest = LockedBox<URLRequest?>(nil)
        let capturedBody = LockedBox<Data?>(nil)
        let responseData = canonicalData()
        URLProtocolStub.setHandler { request in
            capturedRequest.set(request)
            capturedBody.set(try requestBodyData(from: request))
            return makeStubbedResponse(for: request, statusCode: 200, data: responseData)
        }
        let dataURI = "data:image/jpeg;base64,AQID"

        _ = try await makeClient().analyze(dataURI: dataURI)

        let request = try XCTUnwrap(capturedRequest.value)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "\(expectedOrigin)/api/analyze")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 25)
        let body = try XCTUnwrap(capturedBody.value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["image"])
        XCTAssertEqual(object["image"] as? String, dataURI)
    }

    func testAnalyzeDecodesCanonicalSuccess() async throws {
        stub(statusCode: 200, data: canonicalData())

        let result = try await makeClient().analyze(dataURI: "data:image/jpeg;base64,AQID")

        XCTAssertTrue(result.foodDetected)
        XCTAssertEqual(result.foodNames?.ja, "焼き鮭定食")
        XCTAssertEqual(result.assessment.score, 64)
    }

    func testAnalyzeMapsInvalidImage() async {
        await assertBackendError(code: "INVALID_IMAGE", statusCode: 400, equals: .invalidImage)
    }

    func testAnalyzeMapsUnsupportedImage() async {
        await assertBackendError(code: "UNSUPPORTED_IMAGE", statusCode: 415, equals: .unsupportedImage)
    }

    func testAnalyzeMapsImageTooLarge() async {
        await assertBackendError(code: "IMAGE_TOO_LARGE", statusCode: 413, equals: .imageTooLarge)
    }

    func testAnalyzeMapsRateLimitedCodeAndStatusFallback() async {
        await assertBackendError(code: "RATE_LIMITED", statusCode: 503, equals: .rateLimited)
        await assertBackendError(code: nil, statusCode: 429, equals: .rateLimited)
        await assertBackendError(code: "UNKNOWN", statusCode: 429, equals: .rateLimited)
    }

    func testAnalyzeMapsServiceNotConfigured() async {
        await assertBackendError(
            code: "SERVICE_NOT_CONFIGURED",
            statusCode: 503,
            equals: .serviceNotConfigured
        )
    }

    func testAnalyzeMapsAnalysisFailedAndUnknownFallback() async {
        await assertBackendError(code: "ANALYSIS_FAILED", statusCode: 500, equals: .analysisFailed)
        await assertBackendError(code: "UNKNOWN", statusCode: 500, equals: .analysisFailed)
        await assertBackendError(code: nil, statusCode: 500, equals: .analysisFailed)
    }

    func testAnalyzeMapsMalformedAndContractInvalidSuccessResponses() async {
        stub(statusCode: 200, data: Data("not-json".utf8))
        await assertAnalyzeThrows(.malformedResponse)

        stub(statusCode: 200, data: Data("{}".utf8))
        await assertAnalyzeThrows(.malformedResponse)
    }

    func testAnalyzeRejectsSuccessResponseAboveMaximumSize() async {
        var oversized = canonicalData()
        oversized.append(Data(repeating: 0x20, count: (256 * 1024 + 1) - oversized.count))
        XCTAssertEqual(oversized.count, 256 * 1024 + 1)
        stub(statusCode: 200, data: oversized)

        await assertAnalyzeThrows(.malformedResponse)
    }

    func testAnalyzeMapsTimedOutTransportError() async {
        stub(error: URLError(.timedOut))

        await assertAnalyzeThrows(.timeout)
    }

    func testAnalyzeMapsOtherTransportError() async {
        stub(error: URLError(.notConnectedToInternet))

        await assertAnalyzeThrows(.network)
    }

    func testAnalyzeCancellationCancelsUnderlyingLoading() async throws {
        let loadingStarted = expectation(description: "URL loading started")
        let loadingStopped = expectation(description: "URL loading stopped")
        loadingStopped.assertForOverFulfill = true
        URLProtocolStub.setHandler { _ in
            loadingStarted.fulfill()
            return nil
        }
        URLProtocolStub.setStopObserver {
            loadingStopped.fulfill()
        }
        let client = makeClient()
        let task = Task {
            try await client.analyze(dataURI: "data:image/jpeg;base64,AQID")
        }
        await fulfillment(of: [loadingStarted], timeout: 2)

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation remains cancellation rather than a network failure.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        await fulfillment(of: [loadingStopped], timeout: 2)
    }

    func testAppConfigurationLoadsExpectedHTTPSOriginFromAppBundle() throws {
        let configuration = try AppConfiguration.from()

        XCTAssertEqual(configuration.apiBaseURL.absoluteString, expectedOrigin)
    }

    func testAppConfigurationRejectsMissingAndUnsafeOrigins() throws {
        XCTAssertThrowsError(try AppConfiguration.from(bundle: Bundle(for: Self.self))) { error in
            XCTAssertEqual(error as? AppFailure, .invalidConfiguration)
        }

        let invalidOrigins = [
            (scheme: "http", host: "example.com"),
            (scheme: "https", host: "user@example.com"),
            (scheme: "https", host: "example.com:443"),
            (scheme: "https", host: "example.com/prefix"),
            (scheme: "https", host: "example.com?redirect=1"),
            (scheme: "https", host: "example.com#fragment"),
            (scheme: "https", host: ""),
        ]

        for origin in invalidOrigins {
            let bundle = try makeBundle(scheme: origin.scheme, host: origin.host)
            XCTAssertThrowsError(try AppConfiguration.from(bundle: bundle), "\(origin)") { error in
                XCTAssertEqual(error as? AppFailure, .invalidConfiguration)
            }
        }
    }

    private func makeClient() -> AnalysisAPIClient {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: sessionConfiguration)
        let configuration = AppConfiguration(apiBaseURL: URL(string: expectedOrigin)!)
        return AnalysisAPIClient(session: session, configuration: configuration)
    }

    private func stub(statusCode: Int, data: Data) {
        URLProtocolStub.setHandler { request in
            makeStubbedResponse(for: request, statusCode: statusCode, data: data)
        }
    }

    private func stub(error: Error) {
        URLProtocolStub.setHandler { _ in
            throw error
        }
    }

    private func assertBackendError(
        code: String?,
        statusCode: Int,
        equals expected: AppFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let detail: Any = code.map { ["code": $0] } ?? [:]
        let data = try! JSONSerialization.data(
            withJSONObject: ["detail": detail],
            options: [.sortedKeys]
        )
        stub(statusCode: statusCode, data: data)
        await assertAnalyzeThrows(expected, file: file, line: line)
    }

    private func assertAnalyzeThrows(
        _ expected: AppFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await makeClient().analyze(dataURI: "data:image/jpeg;base64,AQID")
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AppFailure, expected, file: file, line: line)
        }
    }

    private func canonicalData() -> Data {
        let url = Bundle(for: Self.self).url(
            forResource: "canonical_analysis_result",
            withExtension: "json"
        )!
        return try! Data(contentsOf: url)
    }

    private func makeBundle(scheme: String, host: String) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(
            at: bundleURL,
            withIntermediateDirectories: false
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.ryuaistudio.kalories.tests.\(UUID().uuidString)",
            "KaloriesAPIScheme": scheme,
            "KaloriesAPIHost": host,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"), options: .atomic)
        return try XCTUnwrap(Bundle(url: bundleURL))
    }
}

private func makeStubbedResponse(
    for request: URLRequest,
    statusCode: Int,
    data: Data
) -> URLProtocolStub.StubbedResponse {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
    return URLProtocolStub.StubbedResponse(response: response, data: data)
}

private func requestBodyData(from request: URLRequest) throws -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 {
            return data
        }
        data.append(contentsOf: buffer.prefix(count))
    }
}
