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
    private(set) var isPresented = false
    private(set) var failure: AppFailure?

    @ObservationIgnored
    private let authorization: any CameraAuthorizing

    @ObservationIgnored
    private var isRequestInFlight = false

    init(authorization: any CameraAuthorizing) {
        self.authorization = authorization
    }

    func requestPresentation() async {
        guard !isPresented, !isRequestInFlight else {
            return
        }

        failure = nil
        isRequestInFlight = true
        defer { isRequestInFlight = false }

        switch authorization.authorizationStatus() {
        case .authorized:
            isPresented = true
        case .denied, .restricted, .unknown:
            failClosed()
        case .notDetermined:
            if await authorization.requestAccess() {
                isPresented = true
            } else {
                failClosed()
            }
        }
    }

    func reset() {
        isPresented = false
        failure = nil
    }

    private func failClosed() {
        isPresented = false
        failure = .cameraDenied
    }
}
