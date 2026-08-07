import SwiftUI
import UIKit

struct RootView: View {
    let environment: AppEnvironment

    private var flow: AppFlowModel { environment.flow }
    private var localizer: AppLocalizer { environment.localizer }

    @ViewBuilder
    var body: some View {
        switch flow.screen {
        case .capture, .preview:
            CaptureView(
                flow: flow,
                localizer: localizer,
                cameraPresentation: environment.cameraPresentation,
                privacyURL: environment.privacyURL,
                supportURL: environment.supportURL
            )
        case .analyzing:
            AnalyzingView(flow: flow, localizer: localizer)
        case .result:
            ResultPlaceholderView(
                image: flow.selectedImage,
                flow: flow,
                localizer: localizer
            )
        case let .failure(failure):
            FailureView(failure: failure, flow: flow, localizer: localizer)
        }
    }
}

private struct ResultPlaceholderView: View {
    let image: UIImage?
    let flow: AppFlowModel
    let localizer: AppLocalizer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }

                Button {
                    flow.retake()
                } label: {
                    Text(localizer.text("retake"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct FailureView: View {
    let failure: AppFailure
    let flow: AppFlowModel
    let localizer: AppLocalizer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(localizer.text("appName"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("app.title")

                Text(localizer.text(localizationKey))
                    .font(.title2.bold())
                    .accessibilityIdentifier(
                        failure == .timeout ? "error.timeout" : "error.message"
                    )

                if flow.selectedImage != nil {
                    Button {
                        flow.retry()
                    } label: {
                        Text(localizer.text("retry"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("error.retry")
                }

                Button {
                    flow.retake()
                } label: {
                    Text(localizer.text("retake"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var localizationKey: String {
        switch failure {
        case .cameraDenied:
            "errorCameraDenied"
        case .captureFailed:
            "errorCaptureFailed"
        case .invalidImage:
            "errorInvalidImage"
        case .unsupportedImage:
            "errorUnsupportedImage"
        case .imageTooLarge:
            "errorImageTooLarge"
        case .noFood:
            "errorNoFood"
        case .serviceNotConfigured:
            "errorServiceNotConfigured"
        case .analysisFailed:
            "errorAnalysisFailed"
        case .network:
            "errorNetwork"
        case .timeout:
            "errorTimeout"
        case .rateLimited:
            "errorRateLimited"
        case .malformedResponse:
            "errorAnalysisFailed"
        case .invalidConfiguration:
            "errorServiceNotConfigured"
        }
    }
}
