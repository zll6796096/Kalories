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

    func testAnalyzeWithoutImageShowsInvalidImageWithoutCallingDependencies() async {
        let processor = RecordingImageProcessor(results: [.success("unused")])
        let service = ControlledAnalysisService(calls: [])
        let model = makeModel(service: service, processor: processor)

        let flowCompletion = startAnalysis(
            on: model,
            description: "no-image analysis completed"
        )
        await fulfillment(of: [flowCompletion.expectation], timeout: 1)

        assertFailure(.invalidImage, on: model.screen)
        XCTAssertEqual(processor.images.count, 0)
        XCTAssertEqual(service.callCount, 0)
    }

    func testAnalyzeShowsAnalyzingWhileServiceIsSuspended() async {
        let call = makeControlledCall(cancellation: .cooperative)
        let service = ControlledAnalysisService(calls: [call])
        let model = makeModel(service: service)
        model.select(makeImage(color: .orange))

        let flowCompletion = startAnalysis(
            on: model,
            description: "suspended analysis cancelled"
        )
        await fulfillment(of: [call.started], timeout: 1)

        assertAnalyzing(model.screen)

        model.cancelAnalysis()
        await fulfillment(
            of: [call.cancellationObserved, call.resolved, flowCompletion.expectation],
            timeout: 1
        )
    }

    func testAnalyzeShowsAnalyzingBeforeImageProcessingBegins() async {
        let call = makeControlledCall(cancellation: .cooperative)
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

        let flowCompletion = startAnalysis(
            on: model,
            description: "ordering analysis cancelled"
        )
        await fulfillment(of: [call.started], timeout: 1)

        if let observedScreen {
            assertAnalyzing(observedScreen)
        } else {
            XCTFail("Expected the processor invocation to observe screen state")
        }

        model.cancelAnalysis()
        await fulfillment(
            of: [call.cancellationObserved, call.resolved, flowCompletion.expectation],
            timeout: 1
        )
    }

    func testFlowTaskCompletionWaitsForSuspendedServiceAndFulfillsAfterResolution() async {
        let call = makeControlledCall(cancellation: .nonCooperative)
        let model = makeModel(service: ControlledAnalysisService(calls: [call]))
        model.select(makeImage(color: .systemTeal))

        let flowCompletion = startAnalysis(
            on: model,
            description: "suspended flow task completed"
        )
        await fulfillment(of: [call.started], timeout: 1)

        assertAnalyzing(model.screen)
        XCTAssertFalse(
            flowCompletion.isFulfilled,
            "The inherited TaskLocal sentinel must remain alive while the service is suspended"
        )

        let terminal = screenChangeExpectation(for: model, description: "micro-test result")
        call.succeed(makeFoodResult(name: "完了", score: 80))
        await fulfillment(
            of: [call.resolved, terminal, flowCompletion.expectation],
            timeout: 1
        )
        XCTAssertTrue(flowCompletion.isFulfilled)
    }

    func testCancelBeforeTaskStartsSkipsImageProcessing() async {
        let processor = RecordingImageProcessor(results: [.success("unused")])
        let service = ControlledAnalysisService(calls: [])
        let image = makeImage(color: .red)
        let model = makeModel(service: service, processor: processor)
        model.select(image)

        let flowCompletion = startAnalysis(
            on: model,
            description: "pre-start cancelled flow completed"
        )
        model.cancelAnalysis()

        await fulfillment(of: [flowCompletion.expectation], timeout: 1)
        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === image)
        XCTAssertTrue(processor.images.isEmpty)
        XCTAssertEqual(service.callCount, 0)
    }

    func testRetakeBeforeTaskStartsSkipsProcessingAndReleasesImage() async throws {
        let processor = RecordingImageProcessor(results: [.success("unused")])
        let service = ControlledAnalysisService(calls: [])
        var image: UIImage? = makeImage(color: .brown)
        weak let weakImage = image
        let model = makeModel(service: service, processor: processor)
        model.select(try XCTUnwrap(image))

        let flowCompletion = startAnalysis(
            on: model,
            description: "pre-start retaken flow completed"
        )
        model.retake()
        image = nil

        await fulfillment(of: [flowCompletion.expectation], timeout: 1)
        assertCapture(model.screen)
        XCTAssertNil(model.selectedImage)
        XCTAssertNil(weakImage)
        XCTAssertTrue(processor.images.isEmpty)
        XCTAssertEqual(service.callCount, 0)
    }

    func testSelectingNewImageBeforeTaskStartsSkipsOldImageProcessingAndReleasesIt() async throws {
        let processor = RecordingImageProcessor(results: [.success("unused")])
        let service = ControlledAnalysisService(calls: [])
        var oldImage: UIImage? = makeImage(color: .red)
        weak let weakOldImage = oldImage
        let newImage = makeImage(color: .blue)
        let model = makeModel(service: service, processor: processor)
        model.select(try XCTUnwrap(oldImage))

        let flowCompletion = startAnalysis(
            on: model,
            description: "old-image pre-start flow completed"
        )
        model.select(newImage)
        oldImage = nil

        await fulfillment(of: [flowCompletion.expectation], timeout: 1)
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
        let call = makeControlledCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [call])
        let image = makeImage(color: .systemPink)
        let model = makeModel(service: service, processor: processor)
        model.select(image)

        let firstCompletion = startAnalysis(
            on: model,
            description: "superseded pre-start flow completed"
        )
        let latestCompletion = startAnalysis(
            on: model,
            description: "latest pre-start flow completed"
        )

        await fulfillment(
            of: [firstCompletion.expectation, processed, call.started],
            timeout: 1
        )
        XCTAssertEqual(processor.images.count, 1)
        XCTAssertTrue(processor.images[0] === image)
        XCTAssertEqual(service.dataURIs, ["data:latest"])

        let terminal = screenChangeExpectation(for: model, description: "latest result")
        let expected = makeFoodResult(name: "最新", score: 95)
        call.succeed(expected)
        await fulfillment(
            of: [call.resolved, terminal, latestCompletion.expectation],
            timeout: 1
        )
        XCTAssertEqual(result(from: model.screen), expected)
    }

    func testSuccessfulAnalysisShowsCompleteResultAndRetainsImage() async {
        let result = makeFoodResult(name: "焼き鮭定食", score: 64)
        let call = makeControlledCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [call])
        let image = makeImage(color: .green)
        let model = makeModel(service: service)
        model.select(image)

        let flowCompletion = startAnalysis(on: model, description: "success flow completed")
        await fulfillment(of: [call.started], timeout: 1)
        let terminal = screenChangeExpectation(for: model, description: "success result")
        call.succeed(result)
        await fulfillment(
            of: [call.resolved, terminal, flowCompletion.expectation],
            timeout: 1
        )

        XCTAssertEqual(self.result(from: model.screen), result)
        XCTAssertTrue(model.selectedImage === image)
    }

    func testNormalizedNoFoodResultShowsNoFoodAndRetainsImage() async {
        let call = makeControlledCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [call])
        let image = makeImage(color: .yellow)
        let model = makeModel(service: service)
        model.select(image)

        let flowCompletion = startAnalysis(on: model, description: "no-food flow completed")
        await fulfillment(of: [call.started], timeout: 1)
        let terminal = screenChangeExpectation(for: model, description: "no-food failure")
        call.succeed(makeNoFoodResult())
        await fulfillment(
            of: [call.resolved, terminal, flowCompletion.expectation],
            timeout: 1
        )

        assertFailure(.noFood, on: model.screen)
        XCTAssertTrue(model.selectedImage === image)
    }

    func testRetryReusesExactImageAndRunsProcessorAndServiceAgain() async {
        let firstCall = makeControlledCall(cancellation: .nonCooperative)
        let secondCall = makeControlledCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [firstCall, secondCall])
        let processor = RecordingImageProcessor(results: [
            .success("data:first"),
            .success("data:second"),
        ])
        let image = makeImage(color: .blue)
        let model = makeModel(service: service, processor: processor)
        model.select(image)

        let firstCompletion = startAnalysis(
            on: model,
            description: "first retry flow completed"
        )
        await fulfillment(of: [firstCall.started], timeout: 1)
        let firstTerminal = screenChangeExpectation(for: model, description: "first failure")
        firstCall.fail(AppFailure.network)
        await fulfillment(
            of: [firstCall.resolved, firstTerminal, firstCompletion.expectation],
            timeout: 1
        )

        let secondCompletion = startFlowTask(description: "retry flow completed") {
            model.retry()
        }
        await fulfillment(of: [secondCall.started], timeout: 1)
        let expected = makeFoodResult(name: "再試行", score: 72)
        let secondTerminal = screenChangeExpectation(for: model, description: "retry result")
        secondCall.succeed(expected)
        await fulfillment(
            of: [secondCall.resolved, secondTerminal, secondCompletion.expectation],
            timeout: 1
        )

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
            let call = makeControlledCall(cancellation: .nonCooperative)
            let service = ControlledAnalysisService(calls: [call])
            let model = makeModel(service: service)
            model.select(makeImage(color: .purple))

            let flowCompletion = startAnalysis(
                on: model,
                description: "service failure flow completed: \(expected)"
            )
            await fulfillment(of: [call.started], timeout: 1)
            let terminal = screenChangeExpectation(
                for: model,
                description: "service failure \(expected)"
            )
            call.fail(expected)
            await fulfillment(
                of: [call.resolved, terminal, flowCompletion.expectation],
                timeout: 1
            )

            assertFailure(expected, on: model.screen)
        }
    }

    func testProcessingAppFailurePropagatesWithoutCallingService() async {
        let service = ControlledAnalysisService(calls: [])
        let processor = RecordingImageProcessor(results: [.failure(AppFailure.invalidImage)])
        let model = makeModel(service: service, processor: processor)
        model.select(makeImage(color: .brown))

        let flowCompletion = startAnalysis(
            on: model,
            description: "processing failure flow completed"
        )
        let terminal = screenChangeExpectation(for: model, description: "processing failure")
        await fulfillment(of: [terminal, flowCompletion.expectation], timeout: 1)

        assertFailure(.invalidImage, on: model.screen)
        XCTAssertEqual(service.callCount, 0)
    }

    func testUnknownProcessingAndServiceErrorsMapToAnalysisFailed() async {
        do {
            let service = ControlledAnalysisService(calls: [])
            let processor = RecordingImageProcessor(results: [.failure(TestDoubleError.unknown)])
            let model = makeModel(service: service, processor: processor)
            model.select(makeImage(color: .cyan))

            let flowCompletion = startAnalysis(
                on: model,
                description: "unknown processing failure flow completed"
            )
            let terminal = screenChangeExpectation(
                for: model,
                description: "unknown processing failure"
            )
            await fulfillment(of: [terminal, flowCompletion.expectation], timeout: 1)

            assertFailure(.analysisFailed, on: model.screen)
            XCTAssertEqual(service.callCount, 0)
        }

        do {
            let call = makeControlledCall(cancellation: .nonCooperative)
            let service = ControlledAnalysisService(calls: [call])
            let model = makeModel(service: service)
            model.select(makeImage(color: .magenta))

            let flowCompletion = startAnalysis(
                on: model,
                description: "unknown service failure flow completed"
            )
            await fulfillment(of: [call.started], timeout: 1)
            let terminal = screenChangeExpectation(
                for: model,
                description: "unknown service failure"
            )
            call.fail(TestDoubleError.unknown)
            await fulfillment(
                of: [call.resolved, terminal, flowCompletion.expectation],
                timeout: 1
            )

            assertFailure(.analysisFailed, on: model.screen)
        }
    }

    func testCancelAnalysisReturnsToPreviewAndCooperativelyCancelsService() async {
        let call = makeControlledCall(cancellation: .cooperative)
        let service = ControlledAnalysisService(calls: [call])
        let image = makeImage(color: .gray)
        let model = makeModel(service: service)
        model.select(image)
        let flowCompletion = startAnalysis(
            on: model,
            description: "cooperatively cancelled flow completed"
        )
        await fulfillment(of: [call.started], timeout: 1)

        model.cancelAnalysis()
        await fulfillment(
            of: [call.cancellationObserved, call.resolved, flowCompletion.expectation],
            timeout: 1
        )

        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === image)
    }

    func testRetakeClearsImageAndStaleSuccessCannotRestoreResult() async {
        let call = makeControlledCall(cancellation: .nonCooperative)
        let model = makeModel(service: ControlledAnalysisService(calls: [call]))
        model.select(makeImage(color: .darkGray))
        let flowCompletion = startAnalysis(
            on: model,
            description: "retaken stale flow completed"
        )
        await fulfillment(of: [call.started], timeout: 1)

        model.retake()

        assertCapture(model.screen)
        XCTAssertNil(model.selectedImage)
        await fulfillment(of: [call.cancellationObserved], timeout: 1)

        call.succeed(makeFoodResult(name: "古い結果", score: 1))
        await fulfillment(
            of: [call.resolved, flowCompletion.expectation],
            timeout: 1
        )

        assertCapture(model.screen)
        XCTAssertNil(model.selectedImage)
    }

    func testCancelledNonCooperativeErrorsCannotOverwritePreview() async {
        let errors: [any Error] = [AppFailure.timeout, TestDoubleError.unknown]

        for error in errors {
            let call = makeControlledCall(cancellation: .nonCooperative)
            let image = makeImage(color: .lightGray)
            let model = makeModel(service: ControlledAnalysisService(calls: [call]))
            model.select(image)
            let flowCompletion = startAnalysis(
                on: model,
                description: "cancelled stale-error flow completed"
            )
            await fulfillment(of: [call.started], timeout: 1)

            model.cancelAnalysis()
            await fulfillment(of: [call.cancellationObserved], timeout: 1)
            call.fail(error)
            await fulfillment(
                of: [call.resolved, flowCompletion.expectation],
                timeout: 1
            )

            assertPreview(model.screen)
            XCTAssertTrue(model.selectedImage === image)
        }
    }

    func testSelectingNewImageCancelsOldOperationAndStaleSuccessCannotOverwritePreview() async {
        let call = makeControlledCall(cancellation: .nonCooperative)
        let model = makeModel(service: ControlledAnalysisService(calls: [call]))
        let oldImage = makeImage(color: .red)
        let newImage = makeImage(color: .blue)
        model.select(oldImage)
        let flowCompletion = startAnalysis(
            on: model,
            description: "old-image stale flow completed"
        )
        await fulfillment(of: [call.started], timeout: 1)

        model.select(newImage)
        await fulfillment(of: [call.cancellationObserved], timeout: 1)

        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === newImage)

        call.succeed(makeFoodResult(name: "古い画像", score: 3))
        await fulfillment(
            of: [call.resolved, flowCompletion.expectation],
            timeout: 1
        )

        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === newImage)
    }

    func testRepeatedAnalyzeIsLatestOperationWins() async {
        let firstCall = makeControlledCall(cancellation: .nonCooperative)
        let secondCall = makeControlledCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [firstCall, secondCall])
        let model = makeModel(
            service: service,
            processor: RecordingImageProcessor(results: [
                .success("data:first"),
                .success("data:second"),
            ])
        )
        model.select(makeImage(color: .systemPink))
        let firstCompletion = startAnalysis(
            on: model,
            description: "older repeated flow completed"
        )
        await fulfillment(of: [firstCall.started], timeout: 1)

        let latestCompletion = startAnalysis(
            on: model,
            description: "latest repeated flow completed"
        )
        await fulfillment(of: [firstCall.cancellationObserved, secondCall.started], timeout: 1)

        let latest = makeFoodResult(name: "最新", score: 95)
        let latestTerminal = screenChangeExpectation(for: model, description: "latest result")
        secondCall.succeed(latest)
        await fulfillment(
            of: [secondCall.resolved, latestTerminal, latestCompletion.expectation],
            timeout: 1
        )

        firstCall.succeed(makeFoodResult(name: "旧", score: 4))
        await fulfillment(
            of: [firstCall.resolved, firstCompletion.expectation],
            timeout: 1
        )

        XCTAssertEqual(result(from: model.screen), latest)
        XCTAssertEqual(service.dataURIs, ["data:first", "data:second"])
    }

    func testCurrentProcessorCancellationErrorMapsToAnalysisFailed() async {
        let service = ControlledAnalysisService(calls: [])
        let processor = RecordingImageProcessor(results: [.failure(CancellationError())])
        let model = makeModel(service: service, processor: processor)
        model.select(makeImage(color: .cyan))

        let flowCompletion = startAnalysis(
            on: model,
            description: "processor cancellation-error flow completed"
        )
        let terminal = screenChangeExpectation(
            for: model,
            description: "processor cancellation failure"
        )
        await fulfillment(of: [terminal, flowCompletion.expectation], timeout: 1)

        assertFailure(.analysisFailed, on: model.screen)
        XCTAssertEqual(service.callCount, 0)
    }

    func testCurrentServiceCancellationErrorMapsToAnalysisFailed() async {
        let call = makeControlledCall(cancellation: .nonCooperative)
        let model = makeModel(service: ControlledAnalysisService(calls: [call]))
        model.select(makeImage(color: .magenta))
        let flowCompletion = startAnalysis(
            on: model,
            description: "service cancellation-error flow completed"
        )
        await fulfillment(of: [call.started], timeout: 1)

        let terminal = screenChangeExpectation(
            for: model,
            description: "service cancellation failure"
        )
        call.fail(CancellationError())
        await fulfillment(
            of: [call.resolved, terminal, flowCompletion.expectation],
            timeout: 1
        )

        assertFailure(.analysisFailed, on: model.screen)
    }

    func testDeinitCancelsServiceAndReleasesSelectedImage() async throws {
        let call = makeControlledCall(cancellation: .cooperative)
        let service = ControlledAnalysisService(calls: [call])
        let processor = NonRetainingImageProcessor()
        var image: UIImage? = UIImage()
        weak let weakImage = image
        var model: AppFlowModel? = makeModel(service: service, processor: processor)
        weak let weakModel = model
        model?.select(try XCTUnwrap(image))
        let flowCompletion = startFlowTask(description: "deinitialized flow completed") {
            model?.analyze()
        }
        await fulfillment(of: [processor.processed, call.started], timeout: 1)

        image = nil
        XCTAssertNotNil(weakImage, "The model should retain the selected image before deinit")
        model = nil

        XCTAssertNil(weakModel)
        XCTAssertNil(weakImage, "The flow task must release its processed image before service await")
        await fulfillment(of: [call.cancellationObserved], timeout: 1)
        await fulfillment(
            of: [call.resolved, flowCompletion.expectation],
            timeout: 1
        )
    }

    private func makeModel(
        service: any AnalysisServing = ControlledAnalysisService(calls: []),
        processor: any ImageProcessing = RecordingImageProcessor(results: [.success("data:image")])
    ) -> AppFlowModel {
        AppFlowModel(service: service, processor: processor)
    }

    private func makeControlledCall(
        cancellation: ControlledAnalysisCall.CancellationBehavior,
        label: String = UUID().uuidString
    ) -> ControlledAnalysisCall {
        let call = ControlledAnalysisCall(cancellation: cancellation, label: label)
        addTeardownBlock {
            call.finishForCleanup()
        }
        return call
    }

    private func startAnalysis(
        on model: AppFlowModel,
        description: String
    ) -> FlowTaskCompletion {
        startFlowTask(description: description) {
            model.analyze()
        }
    }

    private func startFlowTask(
        description: String,
        _ start: @MainActor () -> Void
    ) -> FlowTaskCompletion {
        let completion = FlowTaskCompletion(
            expectation: expectation(description: description)
        )
        var sentinel: FlowTaskCompletionSentinel? = FlowTaskCompletionSentinel(
            completion: completion
        )
        FlowTaskLifetime.$sentinel.withValue(sentinel) {
            start()
        }
        sentinel = nil
        return completion
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

private enum FlowTaskLifetime {
    @TaskLocal static var sentinel: FlowTaskCompletionSentinel?
}

private final class FlowTaskCompletion: @unchecked Sendable {
    let expectation: XCTestExpectation

    private let lock = NSLock()
    private var didFulfill = false

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    var isFulfilled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didFulfill
    }

    func fulfill() {
        lock.lock()
        guard !didFulfill else {
            lock.unlock()
            return
        }
        didFulfill = true
        lock.unlock()
        expectation.fulfill()
    }
}

private final class FlowTaskCompletionSentinel: @unchecked Sendable {
    private let completion: FlowTaskCompletion

    init(completion: FlowTaskCompletion) {
        self.completion = completion
    }

    deinit {
        completion.fulfill()
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
    private var didFinishRun = false

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

    func finishForCleanup() {
        finish(with: .failure(CancellationError()))
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
        lock.lock()
        guard !didFinishRun else {
            lock.unlock()
            return
        }
        didFinishRun = true
        lock.unlock()
        resolved.fulfill()
    }
}

private enum TestDoubleError: Error {
    case unknown
    case unexpectedCall
}
