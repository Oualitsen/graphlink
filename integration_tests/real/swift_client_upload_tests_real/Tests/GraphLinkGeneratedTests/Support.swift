import CryptoKit
import Foundation
import XCTest
@testable import GraphLinkGenerated

let recordingPort = ProcessInfo.processInfo.environment["RECORDING_PORT"] ?? "9970"
let recordingUrl = URL(string: "http://127.0.0.1:\(recordingPort)/graphql")!
let springUrl = ProcessInfo.processInfo.environment["UPLOAD_SERVER_URL"].flatMap(URL.init(string:))

struct ReceivedPart: Decodable {
    let name: String
    let filename: String?
    let contentType: String?
    let size: Int
    let sha256: String
    let text: String?
}

struct Received: Decodable {
    let contentLength: Int?
    let chunked: Bool
    let parts: [ReceivedPart]

    func part(_ name: String) -> ReceivedPart {
        parts.first { $0.name == name }!
    }
}

func lastRequest() async throws -> Received {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(recordingPort)/_last")!)
    return try JSONDecoder().decode(Received.self, from: data)
}

func newClient(_ url: URL) -> GraphLinkClient {
    let multipart = DefaultGraphLinkURLSessionMultipartAdapter(url: url)
    return GraphLinkClient(adapter: { _ in fatalError("no GraphQL adapter") }, multipartAdapter: multipart.executeMultipart)
}

func pattern(_ size: Int) -> Data {
    Data((0..<size).map { UInt8(($0 &* 31 &+ 7) % 251) })
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

func streamedUpload(
    _ data: Data,
    filename: String,
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
