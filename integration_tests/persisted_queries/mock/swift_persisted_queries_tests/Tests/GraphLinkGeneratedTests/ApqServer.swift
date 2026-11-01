import Foundation
@testable import GraphLinkGenerated

func jsonString(_ map: [String: Any?]) -> String {
    String(data: try! GraphLinkJson.encode(map), encoding: .utf8)!
}

final class ApqServer: @unchecked Sendable {
    private var responses: [String: [String: Any?]] = [:]
    private var registered: Set<String> = []

    private(set) var requests: [[String: Any?]] = []
    private(set) var methods: [String] = []

    var supported = true
    var getSupported = true
    var notFoundMessage = "PersistedQueryNotFound"
    var failWith: Error?
    var getFailWith: Error?

    func respondTo(_ operationName: String, _ data: [String: Any?]) {
        responses[operationName] = ["data": data]
    }

    func respondWithErrors(_ operationName: String, _ errors: [[String: Any?]]) {
        responses[operationName] = ["data": nil, "errors": errors]
    }

    func evict() { registered.removeAll() }

    func clearRequests() {
        requests.removeAll()
        methods.removeAll()
    }

    func isHashOnly(_ body: [String: Any?]) -> Bool {
        body.keys.contains("extensions") && !body.keys.contains("query")
    }

    func post(_ payload: Data) async throws -> Data {
        methods.append("POST")
        return try handle(payload, failWith)
    }

    func get(_ payload: Data) async throws -> Data {
        methods.append("GET")
        if !getSupported { throw GraphLinkGetNotSupported(message: "GET is not allowed") }
        return try handle(payload, getFailWith)
    }

    private func handle(_ payload: Data, _ failure: Error?) throws -> Data {
        let body = try GraphLinkJson.decode(payload)
        requests.append(body)
        if let failure { throw failure }

        let extensions = body["extensions"] as? [String: Any]
        if let persisted = extensions?["persistedQuery"] as? [String: Any] {
            if !supported { return error("PersistedQueryNotSupported", "PERSISTED_QUERY_NOT_SUPPORTED") }
            let hash = persisted["sha256Hash"] as! String
            if let query = body["query"] as? String {
                if GraphLinkSha256.hex(query) != hash { return error("provided sha does not match query", "INTERNAL_SERVER_ERROR") }
                registered.insert(hash)
            } else if !registered.contains(hash) {
                return error(notFoundMessage, "PERSISTED_QUERY_NOT_FOUND")
            }
        }
        let operationName = body["operationName"] as! String
        guard let response = responses[operationName] else {
            fatalError("No response registered for \(operationName)")
        }
        return try GraphLinkJson.encode(response)
    }

    private func error(_ message: String, _ code: String) -> Data {
        try! GraphLinkJson.encode(["errors": [["message": message, "extensions": ["code": code]]]])
    }
}
