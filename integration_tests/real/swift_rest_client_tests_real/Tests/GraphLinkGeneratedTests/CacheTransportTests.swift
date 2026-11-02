import XCTest
@testable import GraphLinkGenerated

actor CountingStore: GraphLinkCacheStore {
    private var store: [String: String] = [:]
    private(set) var sets = 0

    func set(_ key: String, value: String) { sets += 1; store[key] = value }
    func get(_ key: String) -> String? { store[key] }
    func invalidate(_ key: String) { store.removeValue(forKey: key) }
    func invalidateAll() { store.removeAll() }
}

private let dead = "http://127.0.0.1:1"

class CacheCase: XCTestCase {
    var store: InMemoryGraphLinkCacheStore!
    var client: GraphLinkClient!

    override func setUp() async throws {
        try await resetServer()
        store = InMemoryGraphLinkCacheStore()
        client = newClient(store: store)
    }
}

final class CacheQueriesTests: CacheCase {
    func test_secondCallServedFromCache() async throws {
        let first = try await client.queries.counter(name: "a")
        let second = try await client.queries.counter(name: "a")
        XCTAssertEqual([first.n, second.n], [1, 1])
        let v1 = try await client.queries.counterUncached(name: "a").n
        XCTAssertEqual(v1, 2)
    }

    func test_differentArgumentsAreDifferentEntries() async throws {
        let v2 = try await client.queries.counter(name: "a").n
        XCTAssertEqual(v2, 1)
        let v3 = try await client.queries.counter(name: "b").n
        XCTAssertEqual(v3, 1)
        let v4 = try await client.queries.counter(name: "a").n
        XCTAssertEqual(v4, 1)
    }

    func test_uncachedAndNoCacheAreNeverCached() async throws {
        let v5 = try await client.queries.counterUncached(name: "u").n
        XCTAssertEqual(v5, 1)
        let v6 = try await client.queries.counterUncached(name: "u").n
        XCTAssertEqual(v6, 2)
        let v7 = try await client.queries.counterNoCache(name: "u").n
        XCTAssertEqual(v7, 3)
        let v8 = try await client.queries.counterNoCache(name: "u").n
        XCTAssertEqual(v8, 4)
    }

    func test_entryExpiresAfterItsTtl() async throws {
        let v9 = try await client.queries.counterShort(name: "s").n
        XCTAssertEqual(v9, 1)
        let v10 = try await client.queries.counterShort(name: "s").n
        XCTAssertEqual(v10, 1)
        try await Task.sleep(nanoseconds: 1_300_000_000)
        let v11 = try await client.queries.counterShort(name: "s").n
        XCTAssertEqual(v11, 2)
    }

    func test_cacheSharedByClientsUsingTheSameStore() async throws {
        _ = try await client.queries.counter(name: "shared")
        let v12 = try await newClient(store: store).queries.counter(name: "shared").n
        XCTAssertEqual(v12, 1)
        let v13 = try await newClient().queries.counter(name: "shared").n
        XCTAssertEqual(v13, 2)
    }
}

final class CacheInvalidationTests: CacheCase {
    func test_invalidatesEntriesHoldingTheTag() async throws {
        let v14 = try await client.queries.counter(name: "c").n
        XCTAssertEqual(v14, 1)
        _ = try await client.mutations.bump(name: "c")
        let v15 = try await client.queries.counter(name: "c").n
        XCTAssertEqual(v15, 102)
    }

    func test_leavesEntriesWithOtherTagsAlone() async throws {
        let v16 = try await client.queries.counterOther(name: "o").n
        XCTAssertEqual(v16, 1)
        let v17 = try await client.queries.counter(name: "o").n
        XCTAssertEqual(v17, 2)
        _ = try await client.mutations.bump(name: "o")
        let v18 = try await client.queries.counterOther(name: "o").n
        XCTAssertEqual(v18, 1)
        let v19 = try await client.queries.counter(name: "o").n
        XCTAssertGreaterThan(v19, 100)
    }

    func test_allClearsEverything() async throws {
        _ = try await client.queries.counter(name: "x")
        _ = try await client.queries.counterOther(name: "x")
        _ = try await client.mutations.resetAll(name: "x")
        let v20 = try await client.queries.counter(name: "x").n
        XCTAssertEqual(v20, 1)
        let v21 = try await client.queries.counterOther(name: "x").n
        XCTAssertEqual(v21, 2)
    }

    func test_failedMutationDoesNotInvalidateBut204Does() async throws {
        _ = try await client.queries.counter(name: "f")
        let failure = await capture { try await self.client.mutations.bumpFails(code: 500) }
        XCTAssertNotNil(failure as? RestError)
        let v22 = try await client.queries.counter(name: "f").n
        XCTAssertEqual(v22, 1)
        _ = try await client.mutations.bumpFails(code: 204)
        let v23 = try await client.queries.counter(name: "f").n
        XCTAssertEqual(v23, 2)
    }
}

final class CacheFailuresTests: CacheCase {
    func test_errorResponseIsNotCached() async throws {
        let writes = CountingStore()
        let c = newClient(store: writes)
        let failure = await capture { try await c.queries.cachedStatus(code: 500) }
        XCTAssertNotNil(failure as? RestError)
        let none = await writes.sets
        XCTAssertEqual(none, 0)
        let v24 = try await c.queries.cachedStatus(code: 200)?.id
        XCTAssertEqual(v24, "p1")
        let one = await writes.sets
        XCTAssertEqual(one, 1)
    }


    func test_staleIfOfflineServesExpiredEntryOnTransportFailure() async throws {
        _ = try await client.queries.counterOffline(name: "off")
        try await Task.sleep(nanoseconds: 1_300_000_000)
        let offline = newClient(baseUrl: dead, store: store)
        let v25 = try await offline.queries.counterOffline(name: "off").n
        XCTAssertEqual(v25, 1)
    }

    func test_withoutStaleIfOfflineATransportFailureSurfaces() async throws {
        _ = try await client.queries.counterShort(name: "off2")
        try await Task.sleep(nanoseconds: 1_300_000_000)
        let failure = await capture { try await newClient(baseUrl: dead, store: self.store).queries.counterShort(name: "off2") }
        XCTAssertNotNil(failure)
        XCTAssertNil(failure as? RestError)
    }

    func test_freshEntryServedEvenWhenUnreachable() async throws {
        _ = try await client.queries.counter(name: "fresh")
        let v26 = try await newClient(baseUrl: dead, store: store).queries.counter(name: "fresh").n
        XCTAssertEqual(v26, 1)
    }

    func test_nothingCachedAndUnreachableIsATransportError() async throws {
        let failure = await capture { try await newClient(baseUrl: dead, store: self.store).queries.counter(name: "never") }
        XCTAssertNotNil(failure)
        XCTAssertNil(failure as? RestError)
    }
}

final class TransportTests: RestCase {
    func test_pathPrefixTrailingSlashAndBareBaseUrl() async throws {
        let v27 = try await newClient(baseUrl: serverUrl + "/api").queries.eScalars(id: "p").path
        XCTAssertEqual(v27, "/api/echo/scalars/p")
        let v28 = try await newClient(baseUrl: serverUrl + "/api/").queries.eScalars(id: "p").path
        XCTAssertEqual(v28, "/api/echo/scalars/p")
        let v29 = try await newClient(baseUrl: serverUrl + "/").queries.eScalars(id: "p").path
        XCTAssertEqual(v29, "/echo/scalars/p")
    }

    func test_unreachableServerIsNotARestErrorAndTheClientKeepsWorking() async throws {
        let failure = await capture { try await newClient(baseUrl: dead).queries.eAccept() }
        XCTAssertNotNil(failure)
        XCTAssertNil(failure as? RestError)
        let v30 = try await client.queries.eAccept().method
        XCTAssertEqual(v30, "GET")
    }

    func test_concurrentRequestsDoNotMixTheirData() async throws {
        let c = client!
        let results = try await withThrowingTaskGroup(of: (Int, Echo).self) { group in
            for i in 0..<60 { group.addTask { (i, try await c.queries.eScalars(id: "id\(i)", i: i)) } }
            var out: [(Int, Echo)] = []
            for try await r in group { out.append(r) }
            return out
        }
        for (i, e) in results {
            XCTAssertEqual(e.path, "/echo/scalars/id\(i)")
            XCTAssertEqual(queryValue(e, "i"), "\(i)")
        }
    }
}
