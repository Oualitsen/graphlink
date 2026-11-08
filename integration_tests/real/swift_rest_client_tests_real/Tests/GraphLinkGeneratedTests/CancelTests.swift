import Foundation
import XCTest
@testable import GraphLinkGenerated

private let faultUrl = "http://127.0.0.1:\(Variant.comma ? 9965 : 9964)"

private func post(_ path: String) async throws {
    var request = URLRequest(url: URL(string: faultUrl + path)!)
    request.httpMethod = "POST"
    _ = try await URLSession.shared.data(for: request)
}

private struct DeadlineReached: Error {}

private func race(seconds: Double, _ call: @escaping @Sendable () async throws -> String) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask { try await call() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw DeadlineReached()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

final class CancelTests: XCTestCase {
    private func call(_ client: GraphLinkClient, _ op: Character) async throws -> String {
        switch op {
        case "g": return String(try await client.queries.getCount().getCount)
        case "c": return String(try await client.queries.count())
        case "k": return try await client.queries.cachedStatus(code: 200)?.id ?? "nil"
        default: return try await client.queries.status(code: 200)?.id ?? "nil"
        }
    }

    func testACancelledCallReturnsPromptlyAndLeavesTheClientUsable() async throws {
        for op in "gcpk" {
            for mode in ["cancel", "timeout"] {
                let label = "\(op) \(mode)"
                try await post("/_reset")
                let client = newClient(baseUrl: faultUrl)
                try await post("/_arm?fault=slow")
                let started = Date()
                var failure: Error?
                if mode == "timeout" {
                    do { _ = try await race(seconds: 0.2) { try await self.call(client, op) } } catch { failure = error }
                } else {
                    let task = Task { try await self.call(client, op) }
                    try await Task.sleep(nanoseconds: 200_000_000)
                    task.cancel()
                    do { _ = try await task.value } catch { failure = error }
                }
                XCTAssertNotNil(failure, "\(label): a cancelled call returned a value")
                XCTAssertLessThan(Date().timeIntervalSince(started), 0.7, "\(label): waited for a response nobody wanted")
                _ = try await race(seconds: 5) { try await self.call(client, op) }
            }
        }
    }
}
