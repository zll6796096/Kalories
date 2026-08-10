import UIKit
import XCTest
@testable import Kalories

@MainActor
final class CameraAuthorizationTests: XCTestCase {
    func testRetryPolicyIsExhaustiveAndAllowsOnlyTransientAnalysisFailures() {
        let expectations: [(AppFailure, Bool)] = [
            (.cameraDenied, false),
            (.captureFailed, false),
            (.invalidImage, false),
            (.unsupportedImage, false),
            (.imageTooLarge, false),
            (.noFood, false),
            (.serviceNotConfigured, false),
            (.analysisFailed, true),
            (.appCheckFailed, true),
            (.appCheckUnavailable, true),
            (.network, true),
            (.timeout, true),
            (.rateLimited, true),
            (.malformedResponse, true),
            (.invalidConfiguration, false),
        ]

        for (failure, expected) in expectations {
            XCTAssertEqual(failure.isRetryable, expected, "Unexpected retry policy for \(failure)")
        }
    }

    func testCameraPickerCoordinatorCompletesOnceAndNeverDismissesControllersDirectly() {
        var outcomes: [CameraPickerOutcome] = []
        let coordinator = CameraPicker.Coordinator { outcomes.append($0) }
        let unavailableController = DismissRecordingViewController()
        let picker = UIImagePickerController()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }

        coordinator.cameraUnavailable(unavailableController)
        coordinator.cameraUnavailable(unavailableController)
        coordinator.imagePickerControllerDidCancel(picker)
        coordinator.imagePickerController(
            picker,
            didFinishPickingMediaWithInfo: [.originalImage: image]
        )

        XCTAssertEqual(outcomes.count, 1)
        guard case .failure(.captureFailed) = outcomes.first else {
            return XCTFail("Expected the first unavailable callback to win")
        }
        XCTAssertEqual(unavailableController.dismissCallCount, 0)
    }

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
        let authorization = RecordingCameraAuthorizer(status: .authorized)
        let controller = CameraPresentationController(authorization: authorization)

        await controller.requestPresentation()

        XCTAssertTrue(controller.isPresented)
        XCTAssertNil(controller.failure)
        XCTAssertEqual(authorization.statusCallCount, 1)
        XCTAssertEqual(authorization.requestCallCount, 0)
    }

    func testDeniedAndRestrictedStatusesNeverPresentOrRequestAccess() async {
        for status in [CameraAuthorizationStatus.denied, .restricted] {
            let authorization = RecordingCameraAuthorizer(status: status)
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
            let accessCall = makeControlledAccessCall(label: "result-\(requestResult)")
            let authorization = RecordingCameraAuthorizer(status: .notDetermined, call: accessCall)
            let controller = CameraPresentationController(authorization: authorization)

            let request = Task { await controller.requestPresentation() }
            await fulfillment(of: [accessCall.started], timeout: 1)
            accessCall.resume(returning: requestResult)
            await fulfillment(of: [accessCall.completed], timeout: 1)
            await request.value

            XCTAssertEqual(controller.isPresented, requestResult)
            XCTAssertEqual(controller.failure, requestResult ? nil : .cameraDenied)
            XCTAssertEqual(authorization.statusCallCount, 1)
            XCTAssertEqual(authorization.requestCallCount, 1)
        }
    }

    func testResetInvalidatesSuspendedRequestAndIgnoresLateGrantedResult() async {
        let accessCall = makeControlledAccessCall(label: "reset-late-grant")
        let authorization = RecordingCameraAuthorizer(status: .notDetermined, call: accessCall)
        let controller = CameraPresentationController(authorization: authorization)
        let request = Task { await controller.requestPresentation() }
        await fulfillment(of: [accessCall.started], timeout: 1)

        controller.reset()
        accessCall.resume(returning: true)

        await fulfillment(of: [accessCall.completed], timeout: 1)
        await request.value
        XCTAssertFalse(controller.isPresented)
        XCTAssertNil(controller.failure)
        XCTAssertEqual(authorization.statusCallCount, 1)
        XCTAssertEqual(authorization.requestCallCount, 1)
    }

    func testDuplicatePresentationRequestReturnsWhileFirstRequestIsSuspended() async {
        let accessCall = makeControlledAccessCall(label: "duplicate")
        let authorization = RecordingCameraAuthorizer(status: .notDetermined, call: accessCall)
        let controller = CameraPresentationController(authorization: authorization)
        let firstRequest = Task { await controller.requestPresentation() }
        await fulfillment(of: [accessCall.started], timeout: 1)

        let duplicateReturned = expectation(description: "duplicate request returned")
        let duplicateRequest = Task {
            await controller.requestPresentation()
            duplicateReturned.fulfill()
        }

        await fulfillment(of: [duplicateReturned], timeout: 1)
        XCTAssertEqual(authorization.statusCallCount, 1)
        XCTAssertEqual(authorization.requestCallCount, 1)

        accessCall.resume(returning: true)
        await fulfillment(of: [accessCall.completed], timeout: 1)
        await firstRequest.value
        await duplicateRequest.value
        XCTAssertTrue(controller.isPresented)
        XCTAssertNil(controller.failure)
    }

    func testCancelledCallerIgnoresLateGrantedResult() async {
        let accessCall = makeControlledAccessCall(label: "cancel-late-grant")
        let authorization = RecordingCameraAuthorizer(status: .notDetermined, call: accessCall)
        let controller = CameraPresentationController(authorization: authorization)
        let request = Task { await controller.requestPresentation() }
        await fulfillment(of: [accessCall.started], timeout: 1)

        request.cancel()
        accessCall.resume(returning: true)

        await fulfillment(of: [accessCall.completed], timeout: 1)
        await request.value
        XCTAssertFalse(controller.isPresented)
        XCTAssertNil(controller.failure)
        XCTAssertEqual(authorization.statusCallCount, 1)
        XCTAssertEqual(authorization.requestCallCount, 1)
    }

    func testUnknownStatusFailsClosedWithoutRequestingAccess() async {
        let authorization = RecordingCameraAuthorizer(status: .unknown)
        let controller = CameraPresentationController(authorization: authorization)

        await controller.requestPresentation()

        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(controller.failure, .cameraDenied)
        XCTAssertEqual(authorization.statusCallCount, 1)
        XCTAssertEqual(authorization.requestCallCount, 0)
    }

    func testResetDismissesPresentationAndClearsFailureIdempotently() async {
        let authorization = RecordingCameraAuthorizer(status: .authorized)
        let controller = CameraPresentationController(authorization: authorization)
        await controller.requestPresentation()
        XCTAssertTrue(controller.isPresented)

        controller.reset()
        controller.reset()

        XCTAssertFalse(controller.isPresented)
        XCTAssertNil(controller.failure)
        XCTAssertEqual(authorization.statusCallCount, 1)
        XCTAssertEqual(authorization.requestCallCount, 0)

        let deniedAuthorization = RecordingCameraAuthorizer(status: .denied)
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

    private func makeControlledAccessCall(label: String) -> ControlledCameraAccessCall {
        let call = ControlledCameraAccessCall(label: label)
        addTeardownBlock {
            call.finishForCleanup()
        }
        return call
    }
}

private final class RecordingCameraAuthorizer: CameraAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private let statusValue: CameraAuthorizationStatus
    private let call: ControlledCameraAccessCall?
    private var statusCalls = 0
    private var requestCalls = 0

    init(status: CameraAuthorizationStatus, call: ControlledCameraAccessCall? = nil) {
        statusValue = status
        self.call = call
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
        let call = lock.withLock {
            requestCalls += 1
            return self.call
        }
        return await call?.run() ?? false
    }
}

private final class ControlledCameraAccessCall: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var bufferedResult: Bool?
    private var didStart = false
    private var didResolve = false
    private var didComplete = false

    let started: XCTestExpectation
    let completed: XCTestExpectation

    init(label: String) {
        started = XCTestExpectation(description: "camera access started: \(label)")
        completed = XCTestExpectation(description: "camera access completed: \(label)")
    }

    func run() async -> Bool {
        guard markStarted() else {
            return false
        }
        let result = await withCheckedContinuation { continuation in
            install(continuation)
        }
        markCompleted()
        return result
    }

    func resume(returning result: Bool) {
        finish(with: result)
    }

    func finishForCleanup() {
        finish(with: false)
    }

    private func markStarted() -> Bool {
        lock.lock()
        guard !didStart else {
            lock.unlock()
            return false
        }
        didStart = true
        lock.unlock()
        started.fulfill()
        return true
    }

    private func install(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.lock()
        if let bufferedResult {
            self.bufferedResult = nil
            didResolve = true
            lock.unlock()
            continuation.resume(returning: bufferedResult)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func finish(with result: Bool) {
        lock.lock()
        guard !didResolve, bufferedResult == nil else {
            lock.unlock()
            return
        }
        if let continuation {
            self.continuation = nil
            didResolve = true
            lock.unlock()
            continuation.resume(returning: result)
        } else {
            bufferedResult = result
            lock.unlock()
        }
    }

    private func markCompleted() {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()
        completed.fulfill()
    }
}

@MainActor
private final class DismissRecordingViewController: UIViewController {
    private(set) var dismissCallCount = 0

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissCallCount += 1
        completion?()
    }
}
