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
    private(set) var screen: AppScreen = .capture
    private(set) var selectedImage: UIImage?

    @ObservationIgnored
    private var analysisTask: Task<Void, Never>?

    @ObservationIgnored
    private let service: any AnalysisServing

    @ObservationIgnored
    private let processor: any ImageProcessing

    @ObservationIgnored
    private var generation: UInt = 0

    init(service: any AnalysisServing, processor: any ImageProcessing) {
        self.service = service
        self.processor = processor
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

        let dataURI: String
        do {
            dataURI = try processor.dataURI(for: selectedImage)
        } catch let failure as AppFailure {
            screen = .failure(failure)
            return
        } catch {
            screen = .failure(.analysisFailed)
            return
        }

        screen = .analyzing
        let operation = generation
        let service = service

        analysisTask = Task { [weak self] in
            do {
                let result = try await service.analyze(dataURI: dataURI)
                try Task.checkCancellation()
                self?.complete(
                    operation: operation,
                    with: result.foodDetected ? .result(result) : .failure(.noFood)
                )
            } catch is CancellationError {
                self?.clearTask(for: operation)
            } catch let failure as AppFailure {
                guard !Task.isCancelled else {
                    self?.clearTask(for: operation)
                    return
                }
                self?.complete(operation: operation, with: .failure(failure))
            } catch {
                guard !Task.isCancelled else {
                    self?.clearTask(for: operation)
                    return
                }
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
        generation &+= 1
        analysisTask?.cancel()
        analysisTask = nil
    }

    private func complete(operation: UInt, with screen: AppScreen) {
        guard operation == generation, !Task.isCancelled else {
            return
        }
        self.screen = screen
        analysisTask = nil
    }

    private func clearTask(for operation: UInt) {
        guard operation == generation else {
            return
        }
        analysisTask = nil
    }
}
