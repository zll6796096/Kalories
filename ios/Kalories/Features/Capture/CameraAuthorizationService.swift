import AVFoundation
import Observation

enum CameraAuthorizationStatus: Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case unknown
}

protocol CameraAuthorizing: Sendable {
    func authorizationStatus() -> CameraAuthorizationStatus
    func requestAccess() async -> Bool
}

struct CameraAuthorizationService: CameraAuthorizing {
    func authorizationStatus() -> CameraAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

@MainActor
@Observable
final class CameraPresentationController {
    private final class RequestToken {}

    private(set) var isPresented = false
    private(set) var failure: AppFailure?

    @ObservationIgnored
    private let authorization: any CameraAuthorizing

    @ObservationIgnored
    private var currentRequest: RequestToken?

    init(authorization: any CameraAuthorizing) {
        self.authorization = authorization
    }

    func requestPresentation() async {
        guard !isPresented, currentRequest == nil, !Task.isCancelled else {
            return
        }

        let request = RequestToken()
        currentRequest = request
        failure = nil
        defer {
            if currentRequest === request {
                currentRequest = nil
            }
        }

        switch authorization.authorizationStatus() {
        case .authorized:
            present(for: request)
        case .denied, .restricted, .unknown:
            failClosed(for: request)
        case .notDetermined:
            let granted = await authorization.requestAccess()
            guard canComplete(request) else {
                return
            }
            if granted {
                present(for: request)
            } else {
                failClosed(for: request)
            }
        }
    }

    func reset() {
        currentRequest = nil
        isPresented = false
        failure = nil
    }

    private func canComplete(_ request: RequestToken) -> Bool {
        currentRequest === request && !Task.isCancelled
    }

    private func present(for request: RequestToken) {
        guard canComplete(request) else {
            return
        }
        isPresented = true
    }

    private func failClosed(for request: RequestToken) {
        guard canComplete(request) else {
            return
        }
        isPresented = false
        failure = .cameraDenied
    }
}
