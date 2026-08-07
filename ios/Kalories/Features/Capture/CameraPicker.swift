import SwiftUI
import UIKit

enum CameraPickerOutcome {
    case image(UIImage)
    case cancelled
    case failure(AppFailure)
}

struct CameraPicker: UIViewControllerRepresentable {
    let completion: @MainActor (CameraPickerOutcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return UnavailableCameraViewController { [weak coordinator = context.coordinator] controller in
                coordinator?.cameraUnavailable(controller)
            }
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let completion: @MainActor (CameraPickerOutcome) -> Void
        private var didComplete = false

        init(completion: @escaping @MainActor (CameraPickerOutcome) -> Void) {
            self.completion = completion
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish(.cancelled, picker: picker)
        }

        func cameraUnavailable(_ controller: UIViewController) {
            finish(.failure(.captureFailed), picker: controller)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard
                let image = info[.originalImage] as? UIImage,
                image.size.width.isFinite,
                image.size.height.isFinite,
                image.size.width > 0,
                image.size.height > 0,
                image.cgImage != nil || image.ciImage != nil
            else {
                finish(.failure(.captureFailed), picker: picker)
                return
            }

            finish(.image(image), picker: picker)
        }

        private func finish(_ outcome: CameraPickerOutcome, picker: UIViewController) {
            guard !didComplete else {
                return
            }
            didComplete = true
            picker.dismiss(animated: true)
            completion(outcome)
        }
    }
}

@MainActor
private final class UnavailableCameraViewController: UIViewController {
    private let onFirstAppearance: @MainActor (UIViewController) -> Void
    private var didAppear = false

    init(onFirstAppearance: @escaping @MainActor (UIViewController) -> Void) {
        self.onFirstAppearance = onFirstAppearance
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = .systemBackground
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAppear else {
            return
        }
        didAppear = true
        onFirstAppearance(self)
    }
}
