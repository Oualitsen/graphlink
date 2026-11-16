import Foundation
import XCTest
@testable import GraphLinkGenerated

final class CacheConcurrencyTest: XCTestCase {

    private func freshId() -> String { "swift-\(DispatchTime.now().uptimeNanoseconds)" }

    func testConcurrentRequestsForTwoDifferentKeysMakeTwoCalls() async throws {
        let client = Fixtures.newRealClient()
        let id = freshId()
        async let a = client.queries.cachedSlow(id: "\(id)-a", delayMs: 300)
        async let b = client.queries.cachedSlow(id: "\(id)-b", delayMs: 300)
        _ = try await (a, b)
        let callsA = try await client.queries.cachedSlowCalls(id: "\(id)-a").cachedSlowCalls
        let callsB = try await client.queries.cachedSlowCalls(id: "\(id)-b").cachedSlowCalls
        XCTAssertEqual(callsA, 1)
        XCTAssertEqual(callsB, 1)
    }

    func testAResponseInFlightDuringAnInvalidationIsNotStored() async throws {
        let client = Fixtures.newRealClient()
        let id = freshId()
        async let slow = client.queries.cachedSlow(id: id, delayMs: 600)
        try await Task.sleep(nanoseconds: 150_000_000)
        _ = try await client.mutations.bumpSlow(id: id)
        let inFlight = try await slow.cachedSlow
        XCTAssertEqual(inFlight, 0)
        let after = try await client.queries.cachedSlow(id: id, delayMs: 600).cachedSlow
        XCTAssertEqual(after, 1)
    }
}
