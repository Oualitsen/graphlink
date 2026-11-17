import XCTest
@testable import GraphLinkGenerated

final class CacheConcurrencyTests: XCTestCase {
    private var client: GraphLinkClient!
    private var counter = ""
    private static var sequence = 0

    override func setUp() async throws {
        try await resetServer()
        client = newClient(store: InMemoryGraphLinkCacheStore())
        Self.sequence += 1
        counter = "swift-\(DispatchTime.now().uptimeNanoseconds)-\(Self.sequence)"
    }

    func test_concurrentRequestsForTwoDifferentKeysMakeTwoCalls() async throws {
        let client = self.client!
        let counter = self.counter
        async let a = client.queries.counterSlow(name: "\(counter)-a", delayMs: 300)
        async let b = client.queries.counterSlow(name: "\(counter)-b", delayMs: 300)
        _ = try await (a, b)
        let callsA = try await client.queries.counterCalls(name: "\(counter)-a").n
        let callsB = try await client.queries.counterCalls(name: "\(counter)-b").n
        XCTAssertEqual([callsA, callsB], [1, 1])
    }

    func test_concurrentRequestsForTheSameKeyShareOneCall() async throws {
        let client = self.client!
        let counter = self.counter
        async let a = client.queries.counterSlow(name: counter, delayMs: 300)
        async let b = client.queries.counterSlow(name: counter, delayMs: 300)
        async let c = client.queries.counterSlow(name: counter, delayMs: 300)
        let results = try await [a.n, b.n, c.n]
        XCTAssertEqual(results, [1, 1, 1])
        let calls = try await client.queries.counterCalls(name: counter).n
        XCTAssertEqual(calls, 1)
    }

    func test_aResponseInFlightDuringAnInvalidationIsNotStored() async throws {
        let client = self.client!
        let counter = self.counter
        let slow = Task { try await client.queries.counterSlow(name: counter, delayMs: 600).n }
        try await Task.sleep(nanoseconds: 150_000_000)
        _ = try await client.mutations.touchSlow(name: counter)
        let first = try await slow.value
        XCTAssertEqual(first, 1)
        let second = try await client.queries.counterSlow(name: counter, delayMs: 600).n
        XCTAssertEqual(second, 2)
    }
}
