import Foundation
import Observation
import UIKit
import XCTest
@testable import Kalories

@MainActor
final class AppFlowModelTests: XCTestCase {
    func testInitialStateIsCaptureWithoutSelectedImage() {
        let model = makeModel()

        assertCapture(model.screen)
        XCTAssertNil(model.selectedImage)
    }

    func testSelectRetainsExactImageAndShowsPreview() {
        let model = makeModel()
        let image = makeImage(color: .red)

        model.select(image)

        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === image)
    }

    func testAnalyzeWithoutImageShowsInvalidImageWithoutCallingDependencies() {
        let processor = RecordingImageProcessor(results: [.success("unused")])
        let service = ControlledAnalysisService(calls: [])
        let model = makeModel(service: service, processor: processor)

        model.analyze()

        assertFailure(.invalidImage, on: model.screen)
        XCTAssertEqual(processor.images.count, 0)
        XCTAssertEqual(service.callCount, 0)
    }

    func testAnalyzeShowsAnalyzingWhileServiceIsSuspended() async {
        let call = ControlledAnalysisCall(cancellation: .cooperative)
        let service = ControlledAnalysisService(calls: [call])
        let model = makeModel(service: service)
        model.select(makeImage(color: .orange))

        model.analyze()
        await fulfillment(of: [call.started], timeout: 1)

        assertAnalyzing(model.screen)

        model.cancelAnalysis()
        await fulfillment(of: [call.cancellationObserved, call.resolved], timeout: 1)
    }

    func testAnalyzeShowsAnalyzingBeforeImageProcessingBegins() async {
        let call = ControlledAnalysisCall(cancellation: .cooperative)
        let service = ControlledAnalysisService(calls: [call])
        var observedScreen: AppScreen?
        let modelReference = WeakAppFlowModelReference()
        let processor = RecordingImageProcessor(
            results: [.success("data:image")],
            onProcess: { observedScreen = modelReference.value?.screen }
        )
        let model = makeModel(service: service, processor: processor)
        modelReference.value = model
        model.select(makeImage(color: .systemOrange))

        model.analyze()
        await fulfillment(of: [call.started], timeout: 1)

        if let observedScreen {
            assertAnalyzing(observedScreen)
        } else {
            XCTFail("Expected the processor invocation to observe screen state")
        }

        model.cancelAnalysis()
        await fulfillment(of: [call.cancellationObserved, call.resolved], timeout: 1)
    }

    func testCancelBeforeTaskStartsSkipsImageProcessing() async {
        let processed = expectation(description: "processor must not run")
        processed.isInverted = true
        let executorAdvanced = expectation(description: "main actor advanced")
        let processor = RecordingImageProcessor(
            results: [.success("unused")],
            onProcess: { processed.fulfill() }
        )
        let service = ControlledAnalysisService(calls: [])
        let image = makeImage(color: .red)
        let model = makeModel(service: service, processor: processor)
        model.select(image)

        model.analyze()
        model.cancelAnalysis()
        Task { @MainActor in executorAdvanced.fulfill() }

        await fulfillment(of: [executorAdvanced, processed], timeout: 0.05)
        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === image)
        XCTAssertTrue(processor.images.isEmpty)
        XCTAssertEqual(service.callCount, 0)
    }

    func testRetakeBeforeTaskStartsSkipsProcessingAndReleasesImage() async throws {
        let processed = expectation(description: "processor must not run")
        processed.isInverted = true
        let executorAdvanced = expectation(description: "main actor advanced")
        let processor = RecordingImageProcessor(
            results: [.success("unused")],
            onProcess: { processed.fulfill() }
        )
        let service = ControlledAnalysisService(calls: [])
        var image: UIImage? = makeImage(color: .brown)
        weak let weakImage = image
        let model = makeModel(service: service, processor: processor)
        model.select(try XCTUnwrap(image))

        model.analyze()
        model.retake()
        image = nil
        Task { @MainActor in executorAdvanced.fulfill() }

        await fulfillment(of: [executorAdvanced, processed], timeout: 0.05)
        assertCapture(model.screen)
        XCTAssertNil(model.selectedImage)
        XCTAssertNil(weakImage)
        XCTAssertTrue(processor.images.isEmpty)
        XCTAssertEqual(service.callCount, 0)
    }

    func testSelectingNewImageBeforeTaskStartsSkipsOldImageProcessingAndReleasesIt() async throws {
        let processed = expectation(description: "processor must not run")
        processed.isInverted = true
        let executorAdvanced = expectation(description: "main actor advanced")
        let processor = RecordingImageProcessor(
            results: [.success("unused")],
            onProcess: { processed.fulfill() }
        )
        let service = ControlledAnalysisService(calls: [])
        var oldImage: UIImage? = makeImage(color: .red)
        weak let weakOldImage = oldImage
        let newImage = makeImage(color: .blue)
        let model = makeModel(service: service, processor: processor)
        model.select(try XCTUnwrap(oldImage))

        model.analyze()
        model.select(newImage)
        oldImage = nil
        Task { @MainActor in executorAdvanced.fulfill() }

        await fulfillment(of: [executorAdvanced, processed], timeout: 0.05)
        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === newImage)
        XCTAssertNil(weakOldImage)
        XCTAssertTrue(processor.images.isEmpty)
        XCTAssertEqual(service.callCount, 0)
    }

    func testRepeatedAnalyzeBeforeTasksStartOnlyLatestProcessesAndCallsService() async {
        let processed = expectation(description: "only latest processor call")
        processed.expectedFulfillmentCount = 1
        let processor = RecordingImageProcessor(
            results: [.success("data:latest")],
            onProcess: { processed.fulfill() }
        )
        let call = ControlledAnalysisCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [call])
        let image = makeImage(color: .systemPink)
        let model = makeModel(service: service, processor: processor)
        model.select(image)

        model.analyze()
        model.analyze()

        await fulfillment(of: [processed, call.started], timeout: 1)
        XCTAssertEqual(processor.images.count, 1)
        XCTAssertTrue(processor.images[0] === image)
        XCTAssertEqual(service.dataURIs, ["data:latest"])

        let terminal = screenChangeExpectation(for: model, description: "latest result")
        let expected = makeFoodResult(name: "最新", score: 95)
        call.succeed(expected)
        await fulfillment(of: [call.resolved, terminal], timeout: 1)
        XCTAssertEqual(result(from: model.screen), expected)
    }

    func testSuccessfulAnalysisShowsCompleteResultAndRetainsImage() async {
        let result = makeFoodResult(name: "焼き鮭定食", score: 64)
        let call = ControlledAnalysisCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [call])
        let image = makeImage(color: .green)
        let model = makeModel(service: service)
        model.select(image)

        model.analyze()
        await fulfillment(of: [call.started], timeout: 1)
        let terminal = screenChangeExpectation(for: model, description: "success result")
        call.succeed(result)
        await fulfillment(of: [call.resolved, terminal], timeout: 1)

        XCTAssertEqual(self.result(from: model.screen), result)
        XCTAssertTrue(model.selectedImage === image)
    }

    func testNormalizedNoFoodResultShowsNoFoodAndRetainsImage() async {
        let call = ControlledAnalysisCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [call])
        let image = makeImage(color: .yellow)
        let model = makeModel(service: service)
        model.select(image)

        model.analyze()
        await fulfillment(of: [call.started], timeout: 1)
        let terminal = screenChangeExpectation(for: model, description: "no-food failure")
        call.succeed(makeNoFoodResult())
        await fulfillment(of: [call.resolved, terminal], timeout: 1)

        assertFailure(.noFood, on: model.screen)
        XCTAssertTrue(model.selectedImage === image)
    }

    func testRetryReusesExactImageAndRunsProcessorAndServiceAgain() async {
        let firstCall = ControlledAnalysisCall(cancellation: .nonCooperative)
        let secondCall = ControlledAnalysisCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [firstCall, secondCall])
        let processor = RecordingImageProcessor(results: [
            .success("data:first"),
            .success("data:second"),
        ])
        let image = makeImage(color: .blue)
        let model = makeModel(service: service, processor: processor)
        model.select(image)

        model.analyze()
        await fulfillment(of: [firstCall.started], timeout: 1)
        let firstTerminal = screenChangeExpectation(for: model, description: "first failure")
        firstCall.fail(AppFailure.network)
        await fulfillment(of: [firstCall.resolved, firstTerminal], timeout: 1)

        model.retry()
        await fulfillment(of: [secondCall.started], timeout: 1)
        let expected = makeFoodResult(name: "再試行", score: 72)
        let secondTerminal = screenChangeExpectation(for: model, description: "retry result")
        secondCall.succeed(expected)
        await fulfillment(of: [secondCall.resolved, secondTerminal], timeout: 1)

        XCTAssertEqual(service.dataURIs, ["data:first", "data:second"])
        XCTAssertEqual(processor.images.count, 2)
        XCTAssertTrue(processor.images[0] === image)
        XCTAssertTrue(processor.images[1] === image)
        XCTAssertTrue(model.selectedImage === image)
    }

    func testServiceFailuresPropagateExactly() async {
        let failures: [AppFailure] = [
            .network,
            .timeout,
            .rateLimited,
            .malformedResponse,
            .analysisFailed,
        ]

        for expected in failures {
            let call = ControlledAnalysisCall(cancellation: .nonCooperative)
            let service = ControlledAnalysisService(calls: [call])
            let model = makeModel(service: service)
            model.select(makeImage(color: .purple))

            model.analyze()
            await fulfillment(of: [call.started], timeout: 1)
            let terminal = screenChangeExpectation(
                for: model,
                description: "service failure \(expected)"
            )
            call.fail(expected)
            await fulfillment(of: [call.resolved, terminal], timeout: 1)

            assertFailure(expected, on: model.screen)
        }
    }

    func testProcessingAppFailurePropagatesWithoutCallingService() async {
        let service = ControlledAnalysisService(calls: [])
        let processor = RecordingImageProcessor(results: [.failure(AppFailure.invalidImage)])
        let model = makeModel(service: service, processor: processor)
        model.select(makeImage(color: .brown))

        model.analyze()
        let terminal = screenChangeExpectation(for: model, description: "processing failure")
        await fulfillment(of: [terminal], timeout: 1)

        assertFailure(.invalidImage, on: model.screen)
        XCTAssertEqual(service.callCount, 0)
    }

    func testUnknownProcessingAndServiceErrorsMapToAnalysisFailed() async {
        do {
            let service = ControlledAnalysisService(calls: [])
            let processor = RecordingImageProcessor(results: [.failure(TestDoubleError.unknown)])
            let model = makeModel(service: service, processor: processor)
            model.select(makeImage(color: .cyan))

            model.analyze()
            let terminal = screenChangeExpectation(
                for: model,
                description: "unknown processing failure"
            )
            await fulfillment(of: [terminal], timeout: 1)

            assertFailure(.analysisFailed, on: model.screen)
            XCTAssertEqual(service.callCount, 0)
        }

        do {
            let call = ControlledAnalysisCall(cancellation: .nonCooperative)
            let service = ControlledAnalysisService(calls: [call])
            let model = makeModel(service: service)
            model.select(makeImage(color: .magenta))

            model.analyze()
            await fulfillment(of: [call.started], timeout: 1)
            let terminal = screenChangeExpectation(
                for: model,
                description: "unknown service failure"
            )
            call.fail(TestDoubleError.unknown)
            await fulfillment(of: [call.resolved, terminal], timeout: 1)

            assertFailure(.analysisFailed, on: model.screen)
        }
    }

    func testCancelAnalysisReturnsToPreviewAndCooperativelyCancelsService() async {
        let call = ControlledAnalysisCall(cancellation: .cooperative)
        let service = ControlledAnalysisService(calls: [call])
        let image = makeImage(color: .gray)
        let model = makeModel(service: service)
        model.select(image)
        model.analyze()
        await fulfillment(of: [call.started], timeout: 1)

        model.cancelAnalysis()
        await fulfillment(of: [call.cancellationObserved, call.resolved], timeout: 1)

        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === image)
    }

    func testRetakeClearsImageAndStaleSuccessCannotRestoreResult() async {
        let call = ControlledAnalysisCall(cancellation: .nonCooperative)
        let model = makeModel(service: ControlledAnalysisService(calls: [call]))
        model.select(makeImage(color: .darkGray))
        model.analyze()
        await fulfillment(of: [call.started], timeout: 1)

        model.retake()

        assertCapture(model.screen)
        XCTAssertNil(model.selectedImage)
        await fulfillment(of: [call.cancellationObserved], timeout: 1)

        let staleMutation = invertedScreenChangeExpectation(
            for: model,
            description: "stale retake result"
        )
        call.succeed(makeFoodResult(name: "古い結果", score: 1))
        await fulfillment(of: [call.resolved], timeout: 1)
        await fulfillment(of: [staleMutation], timeout: 0.05)

        assertCapture(model.screen)
        XCTAssertNil(model.selectedImage)
    }

    func testCancelledNonCooperativeErrorsCannotOverwritePreview() async {
        let errors: [any Error] = [AppFailure.timeout, TestDoubleError.unknown]

        for error in errors {
            let call = ControlledAnalysisCall(cancellation: .nonCooperative)
            let image = makeImage(color: .lightGray)
            let model = makeModel(service: ControlledAnalysisService(calls: [call]))
            model.select(image)
            model.analyze()
            await fulfillment(of: [call.started], timeout: 1)

            model.cancelAnalysis()
            await fulfillment(of: [call.cancellationObserved], timeout: 1)
            let staleMutation = invertedScreenChangeExpectation(
                for: model,
                description: "stale cancellation error"
            )
            call.fail(error)
            await fulfillment(of: [call.resolved], timeout: 1)
            await fulfillment(of: [staleMutation], timeout: 0.05)

            assertPreview(model.screen)
            XCTAssertTrue(model.selectedImage === image)
        }
    }

    func testSelectingNewImageCancelsOldOperationAndStaleSuccessCannotOverwritePreview() async {
        let call = ControlledAnalysisCall(cancellation: .nonCooperative)
        let model = makeModel(service: ControlledAnalysisService(calls: [call]))
        let oldImage = makeImage(color: .red)
        let newImage = makeImage(color: .blue)
        model.select(oldImage)
        model.analyze()
        await fulfillment(of: [call.started], timeout: 1)

        model.select(newImage)
        await fulfillment(of: [call.cancellationObserved], timeout: 1)

        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === newImage)

        let staleMutation = invertedScreenChangeExpectation(
            for: model,
            description: "stale old-image success"
        )
        call.succeed(makeFoodResult(name: "古い画像", score: 3))
        await fulfillment(of: [call.resolved], timeout: 1)
        await fulfillment(of: [staleMutation], timeout: 0.05)

        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === newImage)
    }

    func testRepeatedAnalyzeIsLatestOperationWins() async {
        let firstCall = ControlledAnalysisCall(cancellation: .nonCooperative)
        let secondCall = ControlledAnalysisCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [firstCall, secondCall])
        let model = makeModel(
            service: service,
            processor: RecordingImageProcessor(results: [
                .success("data:first"),
                .success("data:second"),
            ])
        )
        model.select(makeImage(color: .systemPink))
        model.analyze()
        await fulfillment(of: [firstCall.started], timeout: 1)

        model.analyze()
        await fulfillment(of: [firstCall.cancellationObserved, secondCall.started], timeout: 1)

        let latest = makeFoodResult(name: "最新", score: 95)
        let latestTerminal = screenChangeExpectation(for: model, description: "latest result")
        secondCall.succeed(latest)
        await fulfillment(of: [secondCall.resolved, latestTerminal], timeout: 1)

        let staleMutation = invertedScreenChangeExpectation(
            for: model,
            description: "older repeated result"
        )
        firstCall.succeed(makeFoodResult(name: "旧", score: 4))
        await fulfillment(of: [firstCall.resolved], timeout: 1)
        await fulfillment(of: [staleMutation], timeout: 0.05)

        XCTAssertEqual(result(from: model.screen), latest)
        XCTAssertEqual(service.dataURIs, ["data:first", "data:second"])
    }

    func testCurrentProcessorCancellationErrorMapsToAnalysisFailed() async {
        let service = ControlledAnalysisService(calls: [])
        let processor = RecordingImageProcessor(results: [.failure(CancellationError())])
        let model = makeModel(service: service, processor: processor)
        model.select(makeImage(color: .cyan))

        model.analyze()
        let terminal = screenChangeExpectation(
            for: model,
            description: "processor cancellation failure"
        )
        await fulfillment(of: [terminal], timeout: 0.2)

        assertFailure(.analysisFailed, on: model.screen)
        XCTAssertEqual(service.callCount, 0)
    }

    func testCurrentServiceCancellationErrorMapsToAnalysisFailed() async {
        let call = ControlledAnalysisCall(cancellation: .nonCooperative)
        let model = makeModel(service: ControlledAnalysisService(calls: [call]))
        model.select(makeImage(color: .magenta))
        model.analyze()
        await fulfillment(of: [call.started], timeout: 1)

        let terminal = screenChangeExpectation(
            for: model,
            description: "service cancellation failure"
        )
        call.fail(CancellationError())
        await fulfillment(of: [call.resolved, terminal], timeout: 0.2)

        assertFailure(.analysisFailed, on: model.screen)
    }

    func testDeinitCancelsServiceAndReleasesSelectedImage() async throws {
        let call = ControlledAnalysisCall(cancellation: .cooperative)
        let service = ControlledAnalysisService(calls: [call])
        let processor = NonRetainingImageProcessor()
        var image: UIImage? = UIImage()
        weak let weakImage = image
        var model: AppFlowModel? = makeModel(service: service, processor: processor)
        weak let weakModel = model
        model?.select(try XCTUnwrap(image))
        model?.analyze()
        await fulfillment(of: [processor.processed, call.started], timeout: 1)

        image = nil
        XCTAssertNotNil(weakImage, "The model should retain the selected image before deinit")
        model = nil

        XCTAssertNil(weakModel)
        XCTAssertNil(weakImage, "The flow task must release its processed image before service await")
        await fulfillment(of: [call.cancellationObserved], timeout: 0.2)

        call.fail(CancellationError())
        await fulfillment(of: [call.resolved], timeout: 1)
    }

    private func makeModel(
        service: any AnalysisServing = ControlledAnalysisService(calls: []),
        processor: any ImageProcessing = RecordingImageProcessor(results: [.success("data:image")])
    ) -> AppFlowModel {
        AppFlowModel(service: service, processor: processor)
    }

    private func makeImage(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private func makeFoodResult(name: String, score: Int) -> AnalysisResult {
        AnalysisResult(
            foodDetected: true,
            foodNames: FoodNames(zh: name, ja: name, en: name),
            portionGrams: 420,
            nutrients: NutrientValues(
                caloriesKcal: 640,
                proteinG: 34,
                carbsG: 68,
                fatG: 24,
                fiberG: 8.4,
                sugarG: 12,
                sodiumMg: 980
            ),
            confidence: Confidence(
                overall: .high,
                portion: .medium,
                nutrients: NutrientConfidence(
                    caloriesKcal: .high,
                    proteinG: .high,
                    carbsG: .high,
                    fatG: .medium,
                    fiberG: .medium,
                    sugarG: .low,
                    sodiumMg: .low
                )
            ),
            assumptionKeys: [.visiblePortionOnly, .seasoningEstimated],
            assessment: Assessment(
                score: score,
                tier: .mostlyBalanced,
                statuses: NutrientStatuses(
                    caloriesKcal: .appropriate,
                    proteinG: .high,
                    carbsG: .low,
                    fatG: .high,
                    fiberG: .appropriate,
                    sugarG: .appropriate,
                    sodiumMg: .high
                ),
                suggestionKeys: [.reduceSauce, .adjustStaple],
                scoringReasons: [.proteinHigh, .sodiumHigh],
                insufficientData: false
            )
        )
    }

    private func makeNoFoodResult() -> AnalysisResult {
        AnalysisResult(
            foodDetected: false,
            foodNames: nil,
            portionGrams: nil,
            nutrients: NutrientValues(
                caloriesKcal: nil,
                proteinG: nil,
                carbsG: nil,
                fatG: nil,
                fiberG: nil,
                sugarG: nil,
                sodiumMg: nil
            ),
            confidence: Confidence(
                overall: .low,
                portion: .low,
                nutrients: NutrientConfidence(
                    caloriesKcal: .low,
                    proteinG: .low,
                    carbsG: .low,
                    fatG: .low,
                    fiberG: .low,
                    sugarG: .low,
                    sodiumMg: .low
                )
            ),
            assumptionKeys: [],
            assessment: Assessment(
                score: nil,
                tier: .indeterminate,
                statuses: NutrientStatuses(
                    caloriesKcal: .indeterminate,
                    proteinG: .indeterminate,
                    carbsG: .indeterminate,
                    fatG: .indeterminate,
                    fiberG: .indeterminate,
                    sugarG: .indeterminate,
                    sodiumMg: .indeterminate
                ),
                suggestionKeys: [],
                scoringReasons: [],
                insufficientData: true
            )
        )
    }

    private func screenChangeExpectation(
        for model: AppFlowModel,
        description: String
    ) -> XCTestExpectation {
        let changed = expectation(description: description)
        withObservationTracking {
            _ = model.screen
        } onChange: {
            changed.fulfill()
        }
        return changed
    }

    private func invertedScreenChangeExpectation(
        for model: AppFlowModel,
        description: String
    ) -> XCTestExpectation {
        let changed = screenChangeExpectation(for: model, description: description)
        changed.isInverted = true
        return changed
    }

    private func assertCapture(
        _ screen: AppScreen,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .capture = screen else {
            return XCTFail("Expected capture, got \(screen)", file: file, line: line)
        }
    }

    private func assertPreview(
        _ screen: AppScreen,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .preview = screen else {
            return XCTFail("Expected preview, got \(screen)", file: file, line: line)
        }
    }

    private func assertAnalyzing(
        _ screen: AppScreen,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .analyzing = screen else {
            return XCTFail("Expected analyzing, got \(screen)", file: file, line: line)
        }
    }

    private func assertFailure(
        _ expected: AppFailure,
        on screen: AppScreen,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(failure(from: screen), expected, file: file, line: line)
    }

    private func result(from screen: AppScreen) -> AnalysisResult? {
        guard case let .result(result) = screen else { return nil }
        return result
    }

    private func failure(from screen: AppScreen) -> AppFailure? {
        guard case let .failure(failure) = screen else { return nil }
        return failure
    }
}

@MainActor
private final class WeakAppFlowModelReference {
    weak var value: AppFlowModel?
}

@MainActor
private final class RecordingImageProcessor: ImageProcessing {
    private var results: [Result<String, any Error>]
    private let onProcess: @MainActor () -> Void
    private(set) var images: [UIImage] = []

    init(
        results: [Result<String, any Error>],
        onProcess: @escaping @MainActor () -> Void = {}
    ) {
        self.results = results
        self.onProcess = onProcess
    }

    func dataURI(for image: UIImage) throws -> String {
        onProcess()
        images.append(image)
        guard !results.isEmpty else {
            throw TestDoubleError.unexpectedCall
        }
        return try results.removeFirst().get()
    }
}

@MainActor
private final class NonRetainingImageProcessor: ImageProcessing {
    let processed = XCTestExpectation(description: "image processing completed")

    func dataURI(for image: UIImage) throws -> String {
        processed.fulfill()
        return "data:image"
    }
}

private final class ControlledAnalysisService: AnalysisServing, @unchecked Sendable {
    private let lock = NSLock()
    private let calls: [ControlledAnalysisCall]
    private var nextCallIndex = 0
    private var recordedDataURIs: [String] = []

    init(calls: [ControlledAnalysisCall]) {
        self.calls = calls
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return nextCallIndex
    }

    var dataURIs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedDataURIs
    }

    func analyze(dataURI: String) async throws -> AnalysisResult {
        let call = try takeNextCall(dataURI: dataURI)
        return try await call.run()
    }

    private func takeNextCall(dataURI: String) throws -> ControlledAnalysisCall {
        lock.lock()
        defer { lock.unlock() }
        guard nextCallIndex < calls.count else {
            throw TestDoubleError.unexpectedCall
        }
        let call = calls[nextCallIndex]
        nextCallIndex += 1
        recordedDataURIs.append(dataURI)
        return call
    }
}

private final class ControlledAnalysisCall: @unchecked Sendable {
    enum CancellationBehavior {
        case cooperative
        case nonCooperative
    }

    private let lock = NSLock()
    private let cancellationBehavior: CancellationBehavior
    private var continuation: CheckedContinuation<AnalysisResult, any Error>?
    private var bufferedResult: Result<AnalysisResult, any Error>?
    private var didStart = false
    private var didObserveCancellation = false
    private var didResolve = false

    let started: XCTestExpectation
    let cancellationObserved: XCTestExpectation
    let resolved: XCTestExpectation

    init(cancellation: CancellationBehavior, label: String = UUID().uuidString) {
        cancellationBehavior = cancellation
        started = XCTestExpectation(description: "analysis call started: \(label)")
        cancellationObserved = XCTestExpectation(
            description: "analysis call observed cancellation: \(label)"
        )
        resolved = XCTestExpectation(description: "analysis call resolved: \(label)")
    }

    func run() async throws -> AnalysisResult {
        markStarted()
        defer { markResolved() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(continuation)
            }
        } onCancel: {
            self.observeCancellation()
        }
    }

    func succeed(_ result: AnalysisResult) {
        finish(with: .success(result))
    }

    func fail(_ error: any Error) {
        finish(with: .failure(error))
    }

    private func markStarted() {
        lock.lock()
        guard !didStart else {
            lock.unlock()
            return
        }
        didStart = true
        lock.unlock()
        started.fulfill()
    }

    private func observeCancellation() {
        lock.lock()
        let shouldFulfill = !didObserveCancellation
        didObserveCancellation = true
        let shouldResolve = cancellationBehavior == .cooperative && !didResolve
        lock.unlock()

        if shouldFulfill {
            cancellationObserved.fulfill()
        }
        if shouldResolve {
            finish(with: .failure(CancellationError()))
        }
    }

    private func install(_ continuation: CheckedContinuation<AnalysisResult, any Error>) {
        lock.lock()
        if let bufferedResult {
            self.bufferedResult = nil
            didResolve = true
            lock.unlock()
            continuation.resume(with: bufferedResult)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func finish(with result: Result<AnalysisResult, any Error>) {
        lock.lock()
        guard !didResolve, bufferedResult == nil else {
            lock.unlock()
            return
        }
        if let continuation {
            self.continuation = nil
            didResolve = true
            lock.unlock()
            continuation.resume(with: result)
        } else {
            bufferedResult = result
            lock.unlock()
        }
    }

    private func markResolved() {
        resolved.fulfill()
    }
}

private enum TestDoubleError: Error {
    case unknown
    case unexpectedCall
}
