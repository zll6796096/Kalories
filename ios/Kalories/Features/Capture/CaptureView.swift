import PhotosUI
import SwiftUI
import UIKit

struct LibrarySelectionGeneration {
    private var value = 0

    mutating func begin() -> Int {
        value &+= 1
        return value
    }

    mutating func invalidate() {
        value &+= 1
    }

    func isCurrent(_ candidate: Int) -> Bool {
        candidate == value
    }
}

struct CaptureView: View {
    let flow: AppFlowModel
    let localizer: AppLocalizer
    let cameraPresentation: CameraPresentationController
    let privacyURL: URL
    let supportURL: URL

    @Environment(\.openURL) private var openURL
    @State private var librarySelection: PhotosPickerItem?
    @State private var libraryLoadTask: Task<Void, Never>?
    @State private var librarySelectionGeneration = LibrarySelectionGeneration()
    @State private var captureFailure: AppFailure?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(localizer.text("appName"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("app.title")

                if let image = flow.selectedImage {
                    preview(image)
                } else {
                    captureOptions
                }

                if let failure = captureFailure ?? cameraPresentation.failure {
                    failureView(failure)
                }

                footer
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .fullScreenCover(
            isPresented: Binding(
                get: { cameraPresentation.isPresented },
                set: { isPresented in
                    if !isPresented {
                        cameraPresentation.reset()
                    }
                }
            ),
            onDismiss: cameraPresentation.reset
        ) {
            CameraPicker(completion: handleCameraOutcome)
                .ignoresSafeArea()
        }
        .onChange(of: librarySelection) { _, selectedItem in
            guard let selectedItem else {
                return
            }
            startLibraryImageLoad(from: selectedItem)
        }
    }

    private var captureOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(localizer.text("cameraTitle"))
                    .font(.largeTitle.bold())
                Text(localizer.text("introBody"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    requestCameraPresentation()
                } label: {
                    Label(localizer.text("startCamera"), systemImage: "camera")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("capture.camera")

                PhotosPicker(selection: $librarySelection, matching: .images) {
                    Label(localizer.text("choosePhoto"), systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("capture.library")
            }

            Text(localizer.text("cameraHint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func preview(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(localizer.text("cameraReady"))
                .font(.title.bold())

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel(localizer.text("cameraReady"))

            Text(localizer.text("consentNotice"))
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                captureFailure = nil
                flow.analyze()
            } label: {
                Text(localizer.text("analyzePhoto"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("capture.analyze")

            Button {
                clearSelection()
            } label: {
                Text(localizer.text("retake"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private func failureView(_ failure: AppFailure) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(captureFailureText(failure))
                .font(.callout)
                .foregroundStyle(.red)
                .accessibilityIdentifier(
                    failure == .cameraDenied ? "error.cameraDenied" : "error.captureFailed"
                )

            if failure == .cameraDenied {
                Button(localizer.text("openSettings")) {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                }
                .frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 20) {
            Link(localizer.text("privacyPolicy"), destination: privacyURL)
                .frame(minHeight: 44)
            Link(localizer.text("support"), destination: supportURL)
                .frame(minHeight: 44)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    private func requestCameraPresentation() {
        cancelLibraryImageLoad()
        captureFailure = nil
        cameraPresentation.reset()

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            captureFailure = .captureFailed
            return
        }

        Task { await cameraPresentation.requestPresentation() }
    }

    private func handleCameraOutcome(_ outcome: CameraPickerOutcome) {
        cancelLibraryImageLoad()
        cameraPresentation.reset()
        switch outcome {
        case let .image(image):
            captureFailure = nil
            flow.select(image)
        case .cancelled:
            break
        case let .failure(failure):
            captureFailure = failure
        }
    }

    private func startLibraryImageLoad(from item: PhotosPickerItem) {
        libraryLoadTask?.cancel()
        let generation = librarySelectionGeneration.begin()
        libraryLoadTask = Task {
            await loadLibraryImage(from: item, generation: generation)
        }
    }

    private func loadLibraryImage(from item: PhotosPickerItem, generation: Int) async {
        do {
            let image = try await item
                .loadTransferable(type: Data.self)
                .flatMap(UIImage.init(data:))
            guard
                !Task.isCancelled,
                librarySelectionGeneration.isCurrent(generation)
            else {
                return
            }

            libraryLoadTask = nil
            librarySelection = nil
            guard let image else {
                captureFailure = .captureFailed
                return
            }
            captureFailure = nil
            cameraPresentation.reset()
            flow.select(image)
        } catch {
            guard
                !Task.isCancelled,
                librarySelectionGeneration.isCurrent(generation)
            else {
                return
            }
            libraryLoadTask = nil
            librarySelection = nil
            captureFailure = .captureFailed
        }
    }

    private func clearSelection() {
        cancelLibraryImageLoad()
        captureFailure = nil
        cameraPresentation.reset()
        flow.retake()
    }

    private func cancelLibraryImageLoad() {
        librarySelectionGeneration.invalidate()
        libraryLoadTask?.cancel()
        libraryLoadTask = nil
        librarySelection = nil
    }

    private func captureFailureText(_ failure: AppFailure) -> String {
        failure == .cameraDenied
            ? localizer.text("errorCameraDenied")
            : localizer.text("errorCaptureFailed")
    }
}
