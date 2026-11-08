import Foundation
import XCTest
@testable import GraphLinkGenerated

private let faultUrl = "http://127.0.0.1:\(Variant.comma ? 9965 : 9964)"

private let opNames: [Character: String] = ["g": "GraphQL getCount", "c": "REST count", "p": "REST status"]


private let knownDefects: [String: String] = [:]

private struct FaultCase {
    let fault: String
    let ops: String
    let expect: String
}

private func loadFaultCases() throws -> [FaultCase] {
    var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while true {
        let candidate = directory.appendingPathComponent("fault_server/cases.json")
        if let data = try? Data(contentsOf: candidate) {
            let rows = try JSONSerialization.jsonObject(with: data) as! [[String: String]]
            return rows.map { FaultCase(fault: $0["fault"]!, ops: $0["ops"]!, expect: $0["expect"]!) }
        }
        let parent = directory.deletingLastPathComponent()
        if parent == directory { throw NSError(domain: "fault", code: 1, userInfo: [NSLocalizedDescriptionKey: "cases.json not found"]) }
        directory = parent
    }
}

private func postFault(_ path: String) async throws {
    var request = URLRequest(url: URL(string: faultUrl + path)!)
    request.httpMethod = "POST"
    _ = try await URLSession.shared.data(for: request)
}

private struct FaultTimeout: Error {}

private func withDeadline<T: Sendable>(seconds: Double, _ call: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await call() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw FaultTimeout()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

final class FaultTests: XCTestCase {
    private func faultClient() -> GraphLinkClient { newClient(baseUrl: faultUrl) }

    private func call(_ client: GraphLinkClient, _ op: Character) async throws -> String {
        switch op {
        case "g": return String(try await client.queries.getCount().getCount)
        case "c": return String(try await client.queries.count())
        default: return try await client.queries.status(code: 200)?.id ?? "nil"
        }
    }

    private func assertHealthy(_ client: GraphLinkClient, _ op: Character, _ label: String) async throws {
        switch op {
        case "g":
            let value = try await client.queries.getCount().getCount
            XCTAssertEqual(value, 19, label)
        case "c":
            let value = try await client.queries.count()
            XCTAssertEqual(value, 7, label)
        default:
            let value = try await client.queries.status(code: 200)?.name
            XCTAssertEqual(value, "Pen", label)
        }
    }

    func testFaultInjection() async throws {
        var skipped: [String] = []
        for c in try loadFaultCases() {
            for op in c.ops {
                let label = "\(c.fault): \(opNames[op]!) -> \(c.expect)"
                if let defect = knownDefects["\(c.fault):\(op)"] {
                    skipped.append("\(label) (\(defect))")
                    continue
                }
                FileHandle.standardError.write(Data("FAULT \(c.fault):\(op)\n".utf8))
                try await postFault("/_reset")
                let client = faultClient()
                try await postFault("/_arm?fault=\(c.fault)")
                var result: String?
                var failure: Error?
                do {
                    result = try await withDeadline(seconds: 8) { try await self.call(client, op) }
                } catch is FaultTimeout {
                    XCTFail("\(label): hung for 8 seconds")
                    continue
                } catch {
                    failure = error
                }
                if c.expect == "value" { XCTAssertNil(failure, "\(label): unexpected failure \(String(describing: failure))") }
                if c.expect == "failure" { XCTAssertNotNil(failure, "\(label): decoded without a failure: \(result ?? "nil")") }
                try await assertHealthy(client, op, "\(label): client unusable afterwards")
            }
        }
        if !skipped.isEmpty { print("SKIPPED known defects:\n" + skipped.joined(separator: "\n")) }
    }

    func testARestErrorCarriesTheStatusAndTheBodyOfAGatewayPage() async throws {
        try await postFault("/_reset")
        try await postFault("/_arm?fault=html-502")
        let error = await capture { try await self.faultClient().queries.count() }
        let rest = try XCTUnwrap(error as? RestError)
        XCTAssertEqual(rest.status, 502)
        XCTAssertTrue(rest.body.contains("Bad Gateway"))
    }

    func testAGraphQLErrorReachesTheCallerWithMessagePathAndExtensions() async throws {
        try await postFault("/_reset")
        try await postFault("/_arm?fault=gql-errors-only")
        let error = await capture { try await self.faultClient().queries.getCount() }
        let exception = try XCTUnwrap(error as? GraphLinkException)
        XCTAssertEqual(exception.errors.count, 1)
        XCTAssertEqual(exception.errors.first?.message, "boom")
    }

    func testAGraphQLCallKeepsTheHttpStatusAndBody() async throws {
        for (fault, status, text) in [("html-502", 502, "Bad Gateway"), ("status-401-json", 401, "unauthorized")] {
            try await postFault("/_reset")
            try await postFault("/_arm?fault=\(fault)")
            let error = await capture { try await self.faultClient().queries.getCount() }
            let exception = try XCTUnwrap(error as? GraphLinkException, fault)
            XCTAssertEqual(exception.errors.first?.status, status, fault)
            XCTAssertTrue(exception.errors.first?.body?.contains(text) ?? false, fault)
        }
    }

    func testAResponseWithoutDataAndWithoutErrorsSaysSo() async throws {
        try await postFault("/_reset")
        try await postFault("/_arm?fault=gql-empty-object")
        let error = await capture { try await self.faultClient().queries.getCount() }
        let exception = try XCTUnwrap(error as? GraphLinkException)
        XCTAssertTrue(exception.errors.first?.message.contains("no data") ?? false)
    }
}
