import Foundation
import XCTest
@testable import GraphLinkGenerated

private let faultPort = Int(ProcessInfo.processInfo.environment["WS_FAULT_PORT"] ?? "") ?? 9945
private let faultURL = "http://127.0.0.1:\(faultPort)"

final class HugeResponseTest: XCTestCase {
    private func post(_ path: String) async throws {
        var request = URLRequest(url: URL(string: faultURL + path)!)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }

    private func userCount() throws -> Int {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("fault_server/huge_case.json")
        let spec = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
        return spec["users"] as? Int ?? 0
    }

    func test_aTenMegabyteResponseIsDecodedWithoutLoss() async throws {
        let users = try userCount()
        try await post("/_reset")
        try await post("/_arm?fault=huge-users")
        let ws = DefaultGraphLinkWebSocketAdapter(url: URL(string: "ws://127.0.0.1:\(faultPort)/graphql")!)
        defer { ws.close() }
        let http = DefaultGraphLinkURLSessionAdapter(url: URL(string: "\(faultURL)/graphql")!)
        let client = GraphLinkClient(adapter: http.execute, wsAdapter: ws, multipartAdapter: MockMultipartAdapter().executeMultipart)

        let started = Date()
        let response = try await client.queries.fetchBigUsers(count: users)
        let elapsed = Date().timeIntervalSince(started)

        let list = response.bigUsers
        XCTAssertEqual(list.count, users)
        XCTAssertEqual(list.first?.id, "user-0")
        XCTAssertEqual(list.last?.name, "User \(users - 1) Ünï 日本")
        XCTAssertEqual(list.last?.email, "user-\(users - 1)@example.com")
        XCTAssertEqual(list[1].status, .inactive)
        XCTAssertEqual(list[users / 2].tags, ["alpha", "beta"])
        XCTAssertNil(list[0].address.zip)
        XCTAssertLessThan(elapsed, 30)

        try await post("/_arm?fault=huge-users")
        let again = try await client.queries.fetchBigUsers(count: users)
        XCTAssertEqual(again.bigUsers.count, users)
    }
}
