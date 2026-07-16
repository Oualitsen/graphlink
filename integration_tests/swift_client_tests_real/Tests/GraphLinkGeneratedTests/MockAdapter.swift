import Foundation
@testable import GraphLinkGenerated

/// Implements `GraphLinkClientAdapter` (`(Data) async throws -> Data`) via
/// its bound `execute` method — pass `mockAdapter.execute` wherever the
/// generated client expects the closure typealias.
final class MockAdapter: @unchecked Sendable {
    var simulateFailure = false

    private var responses: [String: String] = [:]
    private var _calls: [GraphLinkCall] = []

    var calls: [GraphLinkCall] { _calls }
    func getLastCall() -> GraphLinkCall? { _calls.last }
    func getCallCount() -> Int { _calls.count }

    func register(_ operationName: String, _ jsonResponse: String) {
        responses[operationName] = jsonResponse
    }

    func registerData(_ operationName: String, _ data: [String: Any?]) {
        register(operationName, jsonString(["data": data]))
    }

    func registerDataAndErrors(_ operationName: String, _ data: [String: Any?], _ errors: [[String: Any?]]) {
        register(operationName, jsonString(["data": data, "errors": errors]))
    }

    func registerErrors(_ operationName: String, _ errors: [[String: Any?]]) {
        register(operationName, jsonString(["data": nil, "errors": errors]))
    }

    func reset() {
        _calls.removeAll()
        responses.removeAll()
        simulateFailure = false
    }

    func execute(_ payload: Data) async throws -> Data {
        if simulateFailure {
            struct SimulatedFailure: Error {}
            throw SimulatedFailure()
        }

        let decoded = try GraphLinkJson.decode(payload)
        let op = decoded["operationName"] as? String
        let variables = (decoded["variables"] as? [String: Any?]) ?? [:]
        _calls.append(GraphLinkCall(operationName: op, variables: variables, rawPayload: String(data: payload, encoding: .utf8) ?? ""))

        guard let op, let response = responses[op] else {
            fatalError("MockAdapter: no response registered for \"\(op ?? "nil")\".\nRegistered operations: \(responses.keys)")
        }
        return response.data(using: .utf8)!
    }
}

func jsonString(_ map: [String: Any?]) -> String {
    let data = try! GraphLinkJson.encode(map)
    return String(data: data, encoding: .utf8)!
}

func n(_ pairs: (String, Any?)...) -> [String: Any?] {
    var result: [String: Any?] = [:]
    for (k, v) in pairs { result[k] = v }
    return result
}
