import Foundation
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

        model.analyze()
        await drainTasks()

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
        await call.waitUntilStarted()

        assertAnalyzing(model.screen)

        model.cancelAnalysis()
        await call.waitUntilCancellationObserved()
        await drainTasks()
    }

    func testSuccessfulAnalysisShowsCompleteResultAndRetainsImage() async {
        let result = makeFoodResult(name: "焼き鮭定食", score: 64)
        let call = ControlledAnalysisCall(cancellation: .nonCooperative)
        let service = ControlledAnalysisService(calls: [call])
        let image = makeImage(color: .green)
        let model = makeModel(service: service)
        model.select(image)

        model.analyze()
        await call.waitUntilStarted()
        call.succeed(result)
        await waitUntil { self.result(from: model.screen) == result }

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
        await call.waitUntilStarted()
        call.succeed(makeNoFoodResult())
        await waitUntil { self.failure(from: model.screen) == .noFood }

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
        await firstCall.waitUntilStarted()
        firstCall.fail(AppFailure.network)
        await waitUntil { self.failure(from: model.screen) == .network }

        model.retry()
        await secondCall.waitUntilStarted()
        let expected = makeFoodResult(name: "再試行", score: 72)
        secondCall.succeed(expected)
        await waitUntil { self.result(from: model.screen) == expected }

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
            await call.waitUntilStarted()
            call.fail(expected)
            await waitUntil { self.failure(from: model.screen) == expected }

            assertFailure(expected, on: model.screen)
        }
    }

    func testProcessingAppFailurePropagatesWithoutCallingService() async {
        let service = ControlledAnalysisService(calls: [])
        let processor = RecordingImageProcessor(results: [.failure(AppFailure.invalidImage)])
        let model = makeModel(service: service, processor: processor)
        model.select(makeImage(color: .brown))

        model.analyze()
        await drainTasks()

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

            assertFailure(.analysisFailed, on: model.screen)
            XCTAssertEqual(service.callCount, 0)
        }

        do {
            let call = ControlledAnalysisCall(cancellation: .nonCooperative)
            let service = ControlledAnalysisService(calls: [call])
            let model = makeModel(service: service)
            model.select(makeImage(color: .magenta))

            model.analyze()
            await call.waitUntilStarted()
            call.fail(TestDoubleError.unknown)
            await waitUntil { self.failure(from: model.screen) == .analysisFailed }

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
        await call.waitUntilStarted()

        model.cancelAnalysis()
        await call.waitUntilCancellationObserved()
        await drainTasks()

        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === image)
        XCTAssertTrue(call.isResolved)
    }

    func testRetakeClearsImageAndStaleSuccessCannotRestoreResult() async {
        let call = ControlledAnalysisCall(cancellation: .nonCooperative)
        let model = makeModel(service: ControlledAnalysisService(calls: [call]))
        model.select(makeImage(color: .darkGray))
        model.analyze()
        await call.waitUntilStarted()

        model.retake()

        assertCapture(model.screen)
        XCTAssertNil(model.selectedImage)
        await call.waitUntilCancellationObserved()

        call.succeed(makeFoodResult(name: "古い結果", score: 1))
        await drainTasks()

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
            await call.waitUntilStarted()

            model.cancelAnalysis()
            await call.waitUntilCancellationObserved()
            call.fail(error)
            await drainTasks()

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
        await call.waitUntilStarted()

        model.select(newImage)
        await call.waitUntilCancellationObserved()

        assertPreview(model.screen)
        XCTAssertTrue(model.selectedImage === newImage)

        call.succeed(makeFoodResult(name: "古い画像", score: 3))
        await drainTasks()

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
        await firstCall.waitUntilStarted()

        model.analyze()
        await firstCall.waitUntilCancellationObserved()
        await secondCall.waitUntilStarted()

        let latest = makeFoodResult(name: "最新", score: 95)
        secondCall.succeed(latest)
        await waitUntil { self.result(from: model.screen) == latest }

        firstCall.succeed(makeFoodResult(name: "旧", score: 4))
        await drainTasks()

        XCTAssertEqual(result(from: model.screen), latest)
        XCTAssertEqual(service.dataURIs, ["data:first", "data:second"])
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

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition was not reached", file: file, line: line)
    }

    private func drainTasks() async {
        for _ in 0..<20 {
            await Task.yield()
        }
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
private final class RecordingImageProcessor: ImageProcessing {
    private var results: [Result<String, any Error>]
    private(set) var images: [UIImage] = []

    init(results: [Result<String, any Error>]) {
        self.results = results
    }

    func dataURI(for image: UIImage) throws -> String {
        images.append(image)
        guard !results.isEmpty else {
            throw TestDoubleError.unexpectedCall
        }
        return try results.removeFirst().get()
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
    private var started = false
    private var cancellationObserved = false
    private var resolved = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    init(cancellation: CancellationBehavior) {
        cancellationBehavior = cancellation
    }

    var isResolved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolved
    }

    func run() async throws -> AnalysisResult {
        markStarted()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(continuation)
            }
        } onCancel: {
            self.observeCancellation()
        }
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { waiter in
            lock.lock()
            if started {
                lock.unlock()
                waiter.resume()
            } else {
                startWaiters.append(waiter)
                lock.unlock()
            }
        }
    }

    func waitUntilCancellationObserved() async {
        await withCheckedContinuation { waiter in
            lock.lock()
            if cancellationObserved {
                lock.unlock()
                waiter.resume()
            } else {
                cancellationWaiters.append(waiter)
                lock.unlock()
            }
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
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume() }
    }

    private func observeCancellation() {
        lock.lock()
        cancellationObserved = true
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        let shouldResolve = cancellationBehavior == .cooperative && !resolved
        lock.unlock()

        waiters.forEach { $0.resume() }
        if shouldResolve {
            finish(with: .failure(CancellationError()))
        }
    }

    private func install(_ continuation: CheckedContinuation<AnalysisResult, any Error>) {
        lock.lock()
        if let bufferedResult {
            self.bufferedResult = nil
            resolved = true
            lock.unlock()
            continuation.resume(with: bufferedResult)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func finish(with result: Result<AnalysisResult, any Error>) {
        lock.lock()
        guard !resolved, bufferedResult == nil else {
            lock.unlock()
            return
        }
        if let continuation {
            self.continuation = nil
            resolved = true
            lock.unlock()
            continuation.resume(with: result)
        } else {
            bufferedResult = result
            lock.unlock()
        }
    }
}

private enum TestDoubleError: Error {
    case unknown
    case unexpectedCall
}
