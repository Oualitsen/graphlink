import Foundation
import XCTest
@testable import GraphLinkGenerated

private struct StreamTimeout: Error {}

private struct Outcome<T> {
    var events: [T] = []
    var error: Error?
}

private func drain<T>(_ stream: AsyncThrowingStream<T, Error>, timeout: TimeInterval = 10) async throws -> Outcome<T> {
    try await withThrowingTaskGroup(of: Outcome<T>.self) { group in
        group.addTask {
            var outcome = Outcome<T>()
            do {
                for try await value in stream { outcome.events.append(value) }
            } catch {
                outcome.error = error
            }
            return outcome
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

final class SubscriptionStreamsTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testEveryArgumentShapeRoundTrips() async throws {
        let o = try await drain(client.subscriptions.subEchoArgs(
            a: [1, 2], b: [1, nil], c: [[1], [], [2, 3]], e: [.xY, .http2Ok], f: [nil, .v1]
        ))
        XCTAssertNil(o.error)
        XCTAssertEqual(o.events.count, 1)
        let r = o.events[0].subEchoArgs
        XCTAssertEqual(r.a, [1, 2])
        XCTAssertEqual(r.b, [1, nil])
        XCTAssertEqual(r.c, [[1], [], [2, 3]])
        XCTAssertEqual(r.e, [.xY, .http2Ok])
        XCTAssertEqual(r.f, [nil, .v1])
    }

    func testOmittedArgumentsAreNullAndDefaultsApply() async throws {
        let o = try await drain(client.subscriptions.subEchoArgs(a: [], e: []))
        let r = o.events[0].subEchoArgs
        XCTAssertNil(r.b)
        XCTAssertNil(r.c)
        XCTAssertNil(r.f)
        XCTAssertEqual(r.g, [.a, .b2])
        XCTAssertEqual(r.one, .only)
    }

    func testInputObjectRoundTrips() async throws {
        let input = ListsInput(a: [3, 4], b: [nil, 5], c: [[1, 2], []], e: [.snakeCase2], f: [.a, nil], g: [.v1])
        let o = try await drain(client.subscriptions.subEchoInput(input: input))
        let r = o.events[0].subEchoInput
        XCTAssertEqual(r.a, [3, 4])
        XCTAssertEqual(r.b, [nil, 5])
        XCTAssertEqual(r.c, [[1, 2], []])
        XCTAssertEqual(r.e, [.snakeCase2])
        XCTAssertEqual(r.f, [.a, nil])
        XCTAssertEqual(r.g, [.v1])
    }

    func testServerCompletionEndsTheStream() async throws {
        let o = try await drain(client.subscriptions.finiteTicks(count: 5))
        XCTAssertNil(o.error)
        XCTAssertEqual(o.events.map { $0.finiteTicks }, [1, 2, 3, 4, 5])
    }

    func testCompletionWithoutEventsIsAnEmptyStream() async throws {
        let o = try await drain(client.subscriptions.finiteTicks(count: 0))
        XCTAssertTrue(o.events.isEmpty)
        XCTAssertNil(o.error)
    }

    func testEventsBeforeTheFailureArriveThenTheError() async throws {
        let o = try await drain(client.subscriptions.flakyTicks(failAfter: 3))
        XCTAssertEqual(o.events.map { $0.flakyTicks }, [1, 2, 3])
        XCTAssertNotNil(o.error)
    }

    func testFailureBeforeTheFirstEvent() async throws {
        let o = try await drain(client.subscriptions.flakyTicks(failAfter: 0))
        XCTAssertTrue(o.events.isEmpty)
        XCTAssertNotNil(o.error)
    }

    func testFailedStreamDoesNotBreakTheNextSubscription() async throws {
        _ = try await drain(client.subscriptions.flakyTicks(failAfter: 1))
        let o = try await drain(client.subscriptions.finiteTicks(count: 2))
        XCTAssertNil(o.error)
        XCTAssertEqual(o.events.count, 2)
    }
}
