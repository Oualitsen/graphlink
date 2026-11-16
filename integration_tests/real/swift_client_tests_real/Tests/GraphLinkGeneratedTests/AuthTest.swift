import Foundation
import XCTest
@testable import GraphLinkGenerated

private struct StreamTimeout: Error {}

private func drain<T>(_ stream: AsyncThrowingStream<T, Error>, timeout: TimeInterval = 10) async throws -> (events: [T], error: Error?) {
    try await withThrowingTaskGroup(of: (events: [T], error: Error?).self) { group in
        group.addTask {
            var events: [T] = []
            do {
                for try await value in stream { events.append(value) }
            } catch {
                return (events, error)
            }
            return (events, nil)
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw StreamTimeout()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private final class Token: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String
    init(_ value: String) { current = value }
    var value: String {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); defer { lock.unlock() }; current = newValue }
    }
}

final class AuthTest: XCTestCase {
    static var next = 0
    var wsAdapters: [DefaultGraphLinkWebSocketAdapter] = []

    override func tearDown() {
        wsAdapters.forEach { $0.close() }
        wsAdapters = []
        super.tearDown()
    }

    private func clientWith(_ headers: (@Sendable () -> [String: String])?) -> GraphLinkClient {
        let http = DefaultGraphLinkURLSessionAdapter(url: Fixtures.SERVER_URL, headersProvider: headers)
        let ws = DefaultGraphLinkWebSocketAdapter(url: Fixtures.WS_URL, headersProvider: headers)
        wsAdapters.append(ws)
        return GraphLinkClient(adapter: http.execute, wsAdapter: ws, multipartAdapter: MockMultipartAdapter().executeMultipart)
    }

    func test_headersProviderValuesReachTheServer() async throws {
        let client = clientWith { ["X-Test": "v1"] }
        let echoed = try await client.queries.echoHeader(name: "X-Test")
        XCTAssertEqual(echoed.echoHeader, "v1")
        let absent = try await client.queries.echoHeader(name: "X-Other")
        XCTAssertNil(absent.echoHeader)
    }

    func test_headersProviderIsEvaluatedOnEveryRequest() async throws {
        let token = Token("first")
        let client = clientWith { ["Authorization": "Bearer \(token.value)"] }
        let first = try await client.queries.whoAmI()
        XCTAssertEqual(first.whoAmI, "first")
        token.value = "second"
        let second = try await client.queries.whoAmI()
        XCTAssertEqual(second.whoAmI, "second")
    }

    func test_aMissingTokenIsAGraphLinkException() async throws {
        do {
            _ = try await clientWith(nil).queries.whoAmI()
            XCTFail("expected throw")
        } catch let error as GraphLinkException {
            XCTAssertFalse(error.errors.isEmpty)
        }
    }

    func test_connectionInitCarriesTheToken() async throws {
        Self.next += 1
        let token = "swift-\(DispatchTime.now().uptimeNanoseconds)-\(Self.next)"
        let client = clientWith { ["Authorization": "Bearer \(token)"] }
        let outcome = try await drain(client.subscriptions.secureTicks(count: 3))
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.events.map { $0.secureTicks }, [1, 2, 3])
        let starts = try await clientWith(nil).queries.secureTickStarts(token: token)
        XCTAssertEqual(starts.secureTickStarts, 1)
    }

    func test_aSubscriptionWithoutATokenFails() async throws {
        let client = clientWith(nil)
        let outcome = try await drain(client.subscriptions.secureTicks(count: 3))
        XCTAssertTrue(outcome.events.isEmpty)
        XCTAssertNotNil(outcome.error)
    }
}
