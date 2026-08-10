import Observation
import UIKit

enum AppScreen {
    case capture
    case preview
    case analyzing
    case result(AnalysisResult)
    case failure(AppFailure)
}

@MainActor
@Observable
final class AppFlowModel {
    private final class OperationToken {}

    private(set) var screen: AppScreen = .capture
    private(set) var selectedImage: UIImage?

    @ObservationIgnored
    private var analysisTask: Task<Void, Never>?

    @ObservationIgnored
    private let service: any AnalysisServing

    @ObservationIgnored
    private let processor: any ImageProcessing

    @ObservationIgnored
    private var currentOperation: OperationToken?

    init(service: any AnalysisServing, processor: any ImageProcessing) {
        self.service = service
        self.processor = processor
    }

    deinit {
        analysisTask?.cancel()
    }

    func select(_ image: UIImage) {
        invalidateAnalysis()
        selectedImage = image
        screen = .preview
    }

    func analyze() {
        invalidateAnalysis()

        guard let selectedImage else {
            screen = .failure(.invalidImage)
            return
        }

        let operation = OperationToken()
        let service = service
        let processor = processor
        var pendingImage: UIImage? = selectedImage
        currentOperation = operation
        screen = .analyzing

        analysisTask = Task { @MainActor [weak self] in
            guard self?.canRun(operation: operation) == true else {
                return
            }

            do {
                let dataURI = try Self.process(
                    pendingImage: &pendingImage,
                    using: processor
                )
                guard self?.canRun(operation: operation) == true else {
                    return
                }

                let result = try await service.analyze(dataURI: dataURI)
                self?.complete(
                    operation: operation,
                    with: result.foodDetected ? .result(result) : .failure(.noFood)
                )
            } catch is CancellationError {
                self?.complete(operation: operation, with: .failure(.analysisFailed))
            } catch let failure as AppFailure {
                self?.complete(operation: operation, with: .failure(failure))
            } catch {
                self?.complete(operation: operation, with: .failure(.analysisFailed))
            }
        }
    }

    func retry() {
        analyze()
    }

    func cancelAnalysis() {
        invalidateAnalysis()
        screen = selectedImage == nil ? .capture : .preview
    }

    func retake() {
        invalidateAnalysis()
        selectedImage = nil
        screen = .capture
    }

    private func invalidateAnalysis() {
        currentOperation = nil
        analysisTask?.cancel()
        analysisTask = nil
    }

    private func canRun(operation: OperationToken) -> Bool {
        currentOperation === operation && !Task.isCancelled
    }

    private func complete(operation: OperationToken, with screen: AppScreen) {
        guard canRun(operation: operation) else {
            return
        }
        self.screen = screen
        currentOperation = nil
        analysisTask = nil
    }

    private static func process(
        pendingImage: inout UIImage?,
        using processor: any ImageProcessing
    ) throws -> String {
        guard let image = pendingImage else {
            throw AppFailure.invalidImage
        }
        defer { pendingImage = nil }
        return try processor.dataURI(for: image)
    }
}
