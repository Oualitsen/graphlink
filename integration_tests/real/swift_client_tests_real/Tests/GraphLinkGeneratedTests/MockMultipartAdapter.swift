import Foundation
@testable import GraphLinkGenerated

struct MultipartCall {
    let operationName: String?
    let operations: String
    let mapJson: String
    let files: [String: GLUpload]
}

/// Implements `GraphLinkMultipartAdapter` (`(Data, Data, [String: GLUpload],
/// UploadProgressCallback?) async throws -> Data`) via its bound
/// `executeMultipart` method.
final class MockMultipartAdapter: @unchecked Sendable {
    private var responses: [String: String] = [:]
    private var _calls: [MultipartCall] = []

    var calls: [MultipartCall] { _calls }
    func getLastCall() -> MultipartCall? { _calls.last }
    func getCallCount() -> Int { _calls.count }

    func registerData(_ operationName: String, _ data: [String: Any?]) {
        responses[operationName] = jsonString(["data": data])
    }

    func reset() {
        _calls.removeAll()
        responses.removeAll()
    }

    func executeMultipart(_ operations: Data, _ mapJson: Data, _ files: [String: GLUpload], _ onProgress: UploadProgressCallback?) async throws -> Data {
        let operationsStr = String(data: operations, encoding: .utf8) ?? ""
        let mapJsonStr = String(data: mapJson, encoding: .utf8) ?? ""
        let decoded = try GraphLinkJson.decode(operations)
        let op = decoded["operationName"] as? String
        _calls.append(MultipartCall(operationName: op, operations: operationsStr, mapJson: mapJsonStr, files: files))

        guard let op, let response = responses[op] else {
            fatalError("MockMultipartAdapter: no response registered for \"\(op ?? "nil")\".\nRegistered operations: \(responses.keys)")
        }
        return response.data(using: .utf8)!
    }
}
