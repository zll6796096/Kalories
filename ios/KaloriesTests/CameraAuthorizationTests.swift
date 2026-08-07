import XCTest
@testable import Kalories

@MainActor
final class CameraAuthorizationTests: XCTestCase {
    func testLibrarySelectionGenerationRejectsOlderLoadsAndRetakeInvalidatesCurrentLoad() {
        var generation = LibrarySelectionGeneration()

        let firstLoad = generation.begin()
        let secondLoad = generation.begin()

        XCTAssertFalse(generation.isCurrent(firstLoad))
        XCTAssertTrue(generation.isCurrent(secondLoad))

        generation.invalidate()

        XCTAssertFalse(generation.isCurrent(secondLoad))
    }

    func testEnvironmentLinksUseTheValidatedOriginAndDirectoryPaths() throws {
        let configuration = try AppConfiguration(
            apiBaseURL: XCTUnwrap(URL(string: "https://kalories-sxielk4wua-an.a.run.app"))
        )

        let links = try AppEnvironment.links(for: configuration)

        XCTAssertEqual(
            links.privacy,
            URL(string: "https://kalories-sxielk4wua-an.a.run.app/privacy/")
        )
        XCTAssertEqual(
            links.support,
            URL(string: "https://kalories-sxielk4wua-an.a.run.app/support/")
        )
        XCTAssertEqual(links.privacy.scheme, configuration.apiBaseURL.scheme)
        XCTAssertEqual(links.privacy.host, configuration.apiBaseURL.host)
        XCTAssertEqual(links.support.scheme, configuration.apiBaseURL.scheme)
        XCTAssertEqual(links.support.host, configuration.apiBaseURL.host)
    }

    func testAuthorizedStatusPresentsWithoutRequestingAccess() async {
        let authorization = RecordingCameraAuthorizer(status: .authorized, requestResult: false)
        let controller = CameraPresentationController(authorization: authorization)

        await controller.requestPresentation()

        XCTAssertTrue(controller.isPresented)
        XCTAssertNil(controller.failure)
        XCTAssertEqual(authorization.statusCallCount, 1)
        XCTAssertEqual(authorization.requestCallCount, 0)
    }

    func testDeniedAndRestrictedStatusesNeverPresentOrRequestAccess() async {
        for status in [CameraAuthorizationStatus.denied, .restricted] {
            let authorization = RecordingCameraAuthorizer(status: status, requestResult: true)
            let controller = CameraPresentationController(authorization: authorization)

            await controller.requestPresentation()

            XCTAssertFalse(controller.isPresented)
            XCTAssertEqual(controller.failure, .cameraDenied)
            XCTAssertEqual(authorization.statusCallCount, 1)
            XCTAssertEqual(authorization.requestCallCount, 0)
        }
    }

    func testNotDeterminedPresentsOnlyWhenRequestAccessReturnsTrue() async {
        for requestResult in [true, false] {
            let authorization = RecordingCameraAuthorizer(
                status: .notDetermined,
                requestResult: requestResult
            )
            let controller = CameraPresentationController(authorization: authorization)

            await controller.requestPresentation()

            XCTAssertEqual(controller.isPresented, requestResult)
            XCTAssertEqual(controller.failure, requestResult ? nil : .cameraDenied)
            XCTAssertEqual(authorization.statusCallCount, 1)
            XCTAssertEqual(authorization.requestCallCount, 1)
        }
    }

    func testUnknownStatusFailsClosedWithoutRequestingAccess() async {
        let authorization = RecordingCameraAuthorizer(status: .unknown, requestResult: true)
        let controller = CameraPresentationController(authorization: authorization)

        await controller.requestPresentation()

        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(controller.failure, .cameraDenied)
        XCTAssertEqual(authorization.statusCallCount, 1)
        XCTAssertEqual(authorization.requestCallCount, 0)
    }

    func testResetDismissesPresentationAndClearsFailureIdempotently() async {
        let authorization = RecordingCameraAuthorizer(status: .authorized, requestResult: false)
        let controller = CameraPresentationController(authorization: authorization)
        await controller.requestPresentation()
        XCTAssertTrue(controller.isPresented)

        controller.reset()
        controller.reset()

        XCTAssertFalse(controller.isPresented)
        XCTAssertNil(controller.failure)
        XCTAssertEqual(authorization.statusCallCount, 1)
        XCTAssertEqual(authorization.requestCallCount, 0)

        let deniedAuthorization = RecordingCameraAuthorizer(status: .denied, requestResult: true)
        let deniedController = CameraPresentationController(authorization: deniedAuthorization)
        await deniedController.requestPresentation()
        XCTAssertEqual(deniedController.failure, .cameraDenied)

        deniedController.reset()
        deniedController.reset()

        XCTAssertFalse(deniedController.isPresented)
        XCTAssertNil(deniedController.failure)
        XCTAssertEqual(deniedAuthorization.statusCallCount, 1)
        XCTAssertEqual(deniedAuthorization.requestCallCount, 0)
    }
}

private final class RecordingCameraAuthorizer: CameraAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private let statusValue: CameraAuthorizationStatus
    private let requestResult: Bool
    private var statusCalls = 0
    private var requestCalls = 0

    init(status: CameraAuthorizationStatus, requestResult: Bool) {
        statusValue = status
        self.requestResult = requestResult
    }

    var statusCallCount: Int {
        lock.withLock { statusCalls }
    }

    var requestCallCount: Int {
        lock.withLock { requestCalls }
    }

    func authorizationStatus() -> CameraAuthorizationStatus {
        lock.withLock {
            statusCalls += 1
            return statusValue
        }
    }

    func requestAccess() async -> Bool {
        lock.withLock {
            requestCalls += 1
            return requestResult
        }
    }
}
