import CryptoKit
import Foundation
import XCTest
@testable import GraphLinkGenerated

enum Variant {
    static let comma = ProcessInfo.processInfo.environment["REST_VARIANT"] == "comma"
    static let port = comma ? 9984 : 9983

    static func key(_ base: String, _ path: [String] = []) -> String {
        path.reduce(base) { comma ? "\($0)[\($1)]" : "\($0).\($1)" }
    }

    static func list(_ key: String, _ values: [String]) -> [String] {
        comma ? ["\(key)=\(values.joined(separator: ","))"] : values.map { "\(key)=\($0)" }
    }
}

let serverUrl = "http://127.0.0.1:\(Variant.port)"

func newClient(
    baseUrl: String? = nil,
    headers: (@Sendable () -> [String: String])? = nil,
    store: any GraphLinkCacheStore = InMemoryGraphLinkCacheStore()
) -> GraphLinkClient {
    let base = baseUrl ?? serverUrl
    let graphql = DefaultGraphLinkURLSessionAdapter(url: URL(string: base + "/graphql")!)
    let rest = DefaultGraphLinkRestAdapter(baseUrl: base, headersProvider: headers)
    return GraphLinkClient(adapter: graphql.execute, restAdapter: rest.execute, store: store)
}

func resetServer() async throws {
    var request = URLRequest(url: URL(string: serverUrl + "/_reset")!)
    request.httpMethod = "POST"
    _ = try await URLSession.shared.data(for: request)
}

class RestCase: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() async throws {
        try await resetServer()
        client = newClient()
    }
}

func capture<T>(_ call: () async throws -> T) async -> Error? {
    do {
        _ = try await call()
        return nil
    } catch {
        return error
    }
}

func pair(_ p: Pair) -> String { "\(p.name)=\(p.value)" }
func queryPairs(_ e: Echo) -> [String] { e.query.map(pair) }
func formPairs(_ e: Echo) -> [String] { e.form.map(pair) }
func queryValue(_ e: Echo, _ name: String) -> String? { e.query.first { $0.name == name }?.value }
func formValue(_ e: Echo, _ name: String) -> String? { e.form.first { $0.name == name }?.value }
func header(_ e: Echo, _ name: String) -> String? { e.headers.first { $0.name == name.lowercased() }?.value }
func partsNamed(_ e: Echo, _ name: String) -> [Part] { e.parts.filter { $0.name == name } }

func part(_ e: Echo, _ name: String, file: StaticString = #filePath, line: UInt = #line) -> Part {
    guard let found = e.parts.first(where: { $0.name == name }) else {
        XCTFail("no part named \(name)", file: file, line: line)
        return Part(name: name, filename: nil, contentType: nil, size: 0, sha256: "", text: nil)
    }
    return found
}

func bodyJson(_ e: Echo) throws -> Any {
    try JSONSerialization.jsonObject(with: Data((e.bodyText ?? "").utf8), options: [.fragmentsAllowed])
}

func pattern(_ size: Int) -> Data {
    Data((0..<size).map { UInt8($0 % 251) })
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func upload(_ data: Data, filename: String? = nil, mimeType: String = "application/octet-stream") -> GLUpload {
    GLUpload(data: data, mimeType: mimeType, filename: filename)
}

func streamedUpload(
    _ data: Data,
    filename: String? = nil,
    knownLength: Bool = true,
    chunkSize: Int = 65_536,
    onPull: (@Sendable (Int) -> Void)? = nil,
    pauseEvery: Int = 0
) -> GLUpload {
    GLUpload(length: knownLength ? data.count : nil, filename: filename) {
        GLChunks {
            let cursor = Collector<Int>()
            return {
                let offset = cursor.all.last ?? 0
                guard offset < data.count else { return nil }
                if pauseEvery > 0, offset % pauseEvery == 0 { try await Task.sleep(nanoseconds: 2_000_000) }
                let end = min(offset + chunkSize, data.count)
                cursor.add(end)
                onPull?(end)
                return data.subdata(in: offset..<end)
            }
        }
    }
}

final class Collector<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []

    func add(_ item: T) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    var all: [T] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}
