import Foundation
import XCTest
@testable import GraphLinkGenerated

private let faultPort = Int(ProcessInfo.processInfo.environment["WS_FAULT_PORT"] ?? "") ?? 9945
private let faultURL = "http://127.0.0.1:\(faultPort)"

private let knownDefects: [String: String] = [:]

private final class Outcome: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [Int] = []
    private var _error: Error?
    private var _settled = false

    func add(_ value: Int) { lock.lock(); _events.append(value); lock.unlock() }
    func fail(_ error: Error) { lock.lock(); _error = error; _settled = true; lock.unlock() }
    func finish() { lock.lock(); _settled = true; lock.unlock() }
    var events: [Int] { lock.lock(); defer { lock.unlock() }; return _events }
    var error: Error? { lock.lock(); defer { lock.unlock() }; return _error }
    var settled: Bool { lock.lock(); defer { lock.unlock() }; return _settled }
}

final class WsFaultsTest: XCTestCase {
    private func post(_ path: String) async throws {
        var request = URLRequest(url: URL(string: faultURL + path)!)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }

    private func log() async throws -> [[String: Any]] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: faultURL + "/_ws_log")!)
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    private func cases() throws -> [[String: Any]] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("fault_server/ws_cases.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]] ?? []
    }

    func test_websocketFaults() async throws {
        for c in try cases() {
            let fault = c["fault"] as! String
            if let reason = knownDefects[fault] {
                print("skipped \(fault): \(reason)")
                continue
            }
            try await run(c, fault: fault)
        }
    }

    private func run(_ c: [String: Any], fault: String) async throws {
        try await post("/_reset")
        try await post("/_arm?fault=\(fault)&times=\(c["times"] as? Int ?? 1)")
        let ws = DefaultGraphLinkWebSocketAdapter(url: URL(string: "ws://127.0.0.1:\(faultPort)/graphql")!)
        let http = DefaultGraphLinkURLSessionAdapter(url: URL(string: "\(faultURL)/graphql")!)
        let client = GraphLinkClient(adapter: http.execute, wsAdapter: ws, multipartAdapter: MockMultipartAdapter().executeMultipart)
        let outcome = Outcome()
        let task = Task {
            do {
                for try await event in client.subscriptions.counterTick() { outcome.add(event.counterTick) }
                outcome.finish()
            } catch {
                outcome.fail(error)
            }
        }
        let wait = c["waitSeconds"] as? Int
        let deadline = Date().addingTimeInterval(Double(wait ?? 8))
        while !outcome.settled && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        task.cancel()
        let connections = try await log()
        ws.close()

        let sent = connections.flatMap { ($0["frames"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String } }
        if wait == nil {
            XCTAssertTrue(outcome.settled, "\(fault): the subscription hung")
            switch c["expect"] as? String {
            case "value":
                XCTAssertNil(outcome.error, "\(fault): unexpected failure \(String(describing: outcome.error))")
                XCTAssertEqual(outcome.events, [1], fault)
            case "error":
                XCTAssertNotNil(outcome.error, "\(fault): no failure, events=\(outcome.events)")
                if let message = c["message"] as? String, let error = outcome.error {
                    XCTAssertTrue("\(error)".contains(message), "\(fault): \(error) does not mention \(message)")
                }
            default: break
            }
        }
        if c["noSubscribeBeforeAck"] as? Bool == true { XCTAssertFalse(sent.contains("subscribe"), "\(fault): subscribe before the ack") }
        if c["pong"] as? Bool == true { XCTAssertTrue(sent.contains("pong"), "\(fault): ping not answered") }
        if let most = c["maxConnections"] as? Int { XCTAssertLessThanOrEqual(connections.count, most, "\(fault): too many connections") }
        if let least = c["minConnections"] as? Int { XCTAssertGreaterThanOrEqual(connections.count, least, "\(fault): did not reconnect") }
    }
}
