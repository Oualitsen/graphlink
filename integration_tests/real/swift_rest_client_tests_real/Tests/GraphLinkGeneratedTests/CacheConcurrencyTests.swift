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

    func test_anInvalidationThatArrivesWhileTheResponseIsBeingStoredRemovesIt() async throws {
        let store = PausingStore()
        let pausing = newClient(store: store)
        let counter = self.counter
        let first = Task { try await pausing.queries.counterSlow(name: counter, delayMs: 50).n }
        while !store.reached { try await Task.sleep(nanoseconds: 10_000_000) }
        let touch = Task { _ = try await pausing.mutations.touchSlow(name: counter) }
        try await Task.sleep(nanoseconds: 300_000_000)
        store.release()
        _ = try await first.value
        try await touch.value
        let second = try await pausing.queries.counterSlow(name: counter, delayMs: 50).n
        XCTAssertEqual(second, 2)
    }
}

private final class PausingStore: GraphLinkCacheStore, @unchecked Sendable {
    private let inner = InMemoryGraphLinkCacheStore()
    private let lock = NSLock()
    private var paused = false
    private var released = false
    private var hasReached = false

    var reached: Bool { lock.lock(); defer { lock.unlock() }; return hasReached }

    func release() { lock.lock(); released = true; lock.unlock() }

    func set(_ key: String, value: String) async {
        lock.lock()
        let shouldPause = !key.hasPrefix("__tag__") && !paused
        if shouldPause { paused = true; hasReached = true }
        lock.unlock()
        if shouldPause {
            while true {
                lock.lock(); let done = released; lock.unlock()
                if done { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        await inner.set(key, value: value)
    }

    func get(_ key: String) async -> String? { await inner.get(key) }
    func invalidate(_ key: String) async { await inner.invalidate(key) }
    func invalidateAll() async { await inner.invalidateAll() }
}
