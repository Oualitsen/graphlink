import XCTest
@testable import GraphLinkGenerated

// The server fails the first cachedFlaky / cachedFlakyNullable call per id and counts every call.
final class CacheErrorsTest: XCTestCase {
    var client: GraphLinkClient!
    var id: String!
    static var next = 0

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
        Self.next += 1
        id = "swift-\(DispatchTime.now().uptimeNanoseconds)-\(Self.next)"
    }

    private func serverCalls() async throws -> Int {
        try await client.queries.cachedFlakyCalls(id: id).cachedFlakyCalls
    }

    func test_aFailedResponseIsNotCached() async throws {
        do {
            _ = try await client.queries.cachedFlaky(id: id)
            XCTFail("expected the first call to fail")
        } catch {}
        let afterFailure = try await serverCalls()
        XCTAssertEqual(afterFailure, 1)

        let retried = try await client.queries.cachedFlaky(id: id)
        XCTAssertEqual(retried.cachedFlaky.id, "user-1")
        let afterRetry = try await serverCalls()
        XCTAssertEqual(afterRetry, 2)

        let cached = try await client.queries.cachedFlaky(id: id)
        XCTAssertEqual(cached.cachedFlaky.id, "user-1")
        let afterCachedRead = try await serverCalls()
        XCTAssertEqual(afterCachedRead, 2)
    }

    func test_aPartialFailureIsNotCached() async throws {
        do {
            _ = try await client.queries.cachedFlakyNullable(id: id)
            XCTFail("expected the first call to fail")
        } catch {}
        let afterFailure = try await serverCalls()
        XCTAssertEqual(afterFailure, 1)

        let retried = try await client.queries.cachedFlakyNullable(id: id)
        XCTAssertEqual(retried.cachedFlakyNullable?.id, "user-1")
        let afterRetry = try await serverCalls()
        XCTAssertEqual(afterRetry, 2)

        let cached = try await client.queries.cachedFlakyNullable(id: id)
        XCTAssertEqual(cached.cachedFlakyNullable?.id, "user-1")
        let afterCachedRead = try await serverCalls()
        XCTAssertEqual(afterCachedRead, 2)
    }
}
