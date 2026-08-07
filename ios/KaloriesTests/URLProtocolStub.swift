import Foundation

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    struct StubbedResponse: @unchecked Sendable {
        let response: HTTPURLResponse
        let data: Data
    }

    typealias Handler = @Sendable (URLRequest) throws -> StubbedResponse?
    typealias StopObserver = @Sendable () -> Void

    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var handlerStorage: Handler?
    nonisolated(unsafe) private static var stopObserverStorage: StopObserver?

    static func setHandler(_ handler: @escaping Handler) {
        stateLock.lock()
        handlerStorage = handler
        stateLock.unlock()
    }

    static func setStopObserver(_ observer: @escaping StopObserver) {
        stateLock.lock()
        stopObserverStorage = observer
        stateLock.unlock()
    }

    static func clear() {
        stateLock.lock()
        handlerStorage = nil
        stopObserverStorage = nil
        stateLock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler = Self.currentHandler()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            guard let stub = try handler(request) else {
                return
            }
            client?.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        Self.currentStopObserver()?()
    }

    private static func currentHandler() -> Handler? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return handlerStorage
    }

    private static func currentStopObserver() -> StopObserver? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopObserverStorage
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}
