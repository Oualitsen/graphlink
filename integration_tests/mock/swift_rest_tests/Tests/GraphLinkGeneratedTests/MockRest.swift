import Foundation
import XCTest
@testable import GraphLinkGenerated

final class MockRest: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [RestRequest] = []
    private var _bodies: [String] = []
    private var specs: [String: (Int, String, [String: String])] = [:]
    var failTransport = false

    var calls: [RestRequest] { lock.lock(); defer { lock.unlock() }; return _calls }
    var bodies: [String] { lock.lock(); defer { lock.unlock() }; return _bodies }
    var last: RestRequest { calls[calls.count - 1] }

    func on(_ method: String, _ path: String, status: Int = 200, json: Any? = nil, text: String? = nil, headers: [String: String] = [:]) {
        let body = text ?? (json == nil ? "" : String(decoding: try! JSONSerialization.data(withJSONObject: json!, options: [.fragmentsAllowed]), as: UTF8.self))
        lock.lock(); specs["\(method) \(path)"] = (status, body, headers); lock.unlock()
    }

    func call(_ request: RestRequest) async throws -> RestResponse {
        if failTransport { throw URLError(.notConnectedToInternet) }
        var rawBody = ""
        if case .raw(let upload) = request.body { rawBody = String(decoding: try await upload.readAll(), as: UTF8.self) }
        lock.lock()
        _calls.append(request)
        switch request.body {
        case .json(let data): _bodies.append(String(decoding: data, as: UTF8.self))
        case .raw: _bodies.append(rawBody)
        default: break
        }
        let spec = specs["\(request.method) \(request.path)"]
        lock.unlock()
        guard let spec else { return RestResponse.fromText(status: 404, text: "no mock") }
        return RestResponse.fromText(status: spec.0, text: spec.1, headers: spec.2)
    }
}

func clientFor(_ rest: MockRest) -> GraphLinkClient {
    GraphLinkClient(
        adapter: { _ in Data(#"{"data":{"ping":"pong"}}"#.utf8) },
        restAdapter: { try await rest.call($0) }
    )
}

func queryString(_ r: RestRequest) -> String { r.query.map { "\($0.name)=\($0.value)" }.joined(separator: "&") }
func textUpload(_ text: String, filename: String? = nil, mimeType: String = "application/octet-stream") -> GLUpload {
    GLUpload(data: Data(text.utf8), mimeType: mimeType, filename: filename)
}

func capture<T>(_ call: () async throws -> T) async -> Error? {
    do { _ = try await call(); return nil } catch { return error }
}
