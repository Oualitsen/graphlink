const swiftRestFile = r'''
public typealias DownloadProgressCallback = @Sendable (Int, Int) -> Void
public typealias GLRestAdapter = @Sendable (RestRequest) async throws -> RestResponse

public struct RestEntry: Sendable, Equatable {
    public let name: String
    public let value: String

    public init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

public struct RestPart: Sendable {
    public let name: String
    public let value: String?
    public let file: GLUpload?
    public let mimeType: String?

    public init(name: String, value: String? = nil, file: GLUpload? = nil, mimeType: String? = nil) {
        self.name = name
        self.value = value
        self.file = file
        self.mimeType = mimeType
    }
}

public enum RestBody: Sendable {
    case json(Data)
    case form([RestEntry])
    case multipart([RestPart])
    case raw(GLUpload)
}

public struct RestRequest: Sendable {
    public let method: String
    public let path: String
    public let query: [RestEntry]
    public let headers: [String: String]
    public let body: RestBody?
    public let onSendProgress: UploadProgressCallback?

    public init(
        method: String,
        path: String,
        query: [RestEntry] = [],
        headers: [String: String] = [:],
        body: RestBody? = nil,
        onSendProgress: UploadProgressCallback? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.onSendProgress = onSendProgress
    }
}

public struct RestResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let stream: AsyncThrowingStream<Data, Error>

    public init(status: Int, headers: [String: String] = [:], stream: AsyncThrowingStream<Data, Error>) {
        self.status = status
        self.headers = headers
        self.stream = stream
    }

    public static func fromData(status: Int, data: Data, headers: [String: String] = [:]) -> RestResponse {
        RestResponse(
            status: status,
            headers: headers,
            stream: AsyncThrowingStream { continuation in
                if !data.isEmpty { continuation.yield(data) }
                continuation.finish()
            }
        )
    }

    public static func fromText(status: Int, text: String, headers: [String: String] = [:]) -> RestResponse {
        fromData(status: status, data: Data(text.utf8), headers: headers)
    }

    public var isSuccess: Bool { status >= 200 && status < 300 }

    public func data() async throws -> Data {
        var out = Data()
        for try await chunk in stream { out.append(chunk) }
        return out
    }

    public func text() async throws -> String {
        String(decoding: try await data(), as: UTF8.self)
    }

    public func json() async throws -> Any? {
        try restParseJson(try await data())
    }

    public func drain() async throws {
        for try await _ in stream {}
    }
}

public struct RestError: Error, Sendable, CustomStringConvertible {
    public let status: Int
    public let headers: [String: String]
    public let body: String

    public init(status: Int, headers: [String: String], body: String) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public var description: String { "RestError(\(status)): \(body)" }

    public static func from(_ response: RestResponse) async throws -> RestError {
        RestError(status: response.status, headers: response.headers, body: try await response.text())
    }
}

public struct RestDecodeError: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

public struct GLDownload: Sendable {
    public let stream: AsyncThrowingStream<Data, Error>
    public let filename: String?
    public let contentType: String?
    public let length: Int?

    public init(stream: AsyncThrowingStream<Data, Error>, filename: String? = nil, contentType: String? = nil, length: Int? = nil) {
        self.stream = stream
        self.filename = filename
        self.contentType = contentType
        self.length = length
    }

    public func data() async throws -> Data {
        var out = Data()
        for try await chunk in stream { out.append(chunk) }
        return out
    }

    static func fromResponse(_ response: RestResponse, onProgress: DownloadProgressCallback?) -> GLDownload {
        let length = restResponseHeader(response.headers, "content-length").flatMap { Int($0) }
        var stream = response.stream
        if let onProgress {
            let source = response.stream
            let total = length ?? -1
            stream = AsyncThrowingStream { continuation in
                let task = Task {
                    var received = 0
                    do {
                        for try await chunk in source {
                            received += chunk.count
                            onProgress(received, total)
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        return GLDownload(
            stream: stream,
            filename: restFilename(restResponseHeader(response.headers, "content-disposition")),
            contentType: restResponseHeader(response.headers, "content-type"),
            length: length
        )
    }
}

public func restResponseHeader(_ headers: [String: String], _ name: String) -> String? {
    for (key, value) in headers where key.lowercased() == name { return value }
    return nil
}

func restFilename(_ disposition: String?) -> String? {
    guard let disposition,
          let regex = try? NSRegularExpression(pattern: "filename\\*?=(?:UTF-8'')?\"?([^\";]+)\"?", options: [.caseInsensitive]),
          let match = regex.firstMatch(in: disposition, range: NSRange(disposition.startIndex..., in: disposition)),
          let range = Range(match.range(at: 1), in: disposition) else { return nil }
    let raw = String(disposition[range])
    return raw.removingPercentEncoding ?? raw
}

private let restUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

public func restEncode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: restUnreserved) ?? value
}

public func restEncodeQuery(_ value: String) -> String {
    restEncode(value).replacingOccurrences(of: "%20", with: "+")
}

public func restText(_ value: Any?) -> String {
    switch value {
    case nil: return ""
    case let flag as Bool: return flag ? "true" : "false"
    case let text as String: return text
    case let some?: return String(describing: some)
    }
}

public func restPath(_ value: Any?) -> String {
    restEncode(restText(value))
}

public func restParseJson(_ data: Data) throws -> Any? {
    if data.isEmpty { return nil }
    let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    return value is NSNull ? nil : value
}

public func restEncodeJson(_ value: Any?) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: GraphLinkJson.normalize(value),
        options: [.fragmentsAllowed, .withoutEscapingSlashes]
    )
}

public func restEncodeJsonString(_ value: Any?) throws -> String {
    String(decoding: try restEncodeJson(value), as: UTF8.self)
}

public func restUrl(_ baseUrl: String, _ request: RestRequest) -> URL? {
    var base = baseUrl
    if base.hasSuffix("/") { base.removeLast() }
    let query = request.query.map { "\(restEncodeQuery($0.name))=\(restEncodeQuery($0.value))" }.joined(separator: "&")
    return URL(string: base + request.path + (query.isEmpty ? "" : "?" + query))
}

public func restFormBody(_ entries: [RestEntry]) -> Data {
    Data(entries.map { "\(restEncodeQuery($0.name))=\(restEncodeQuery($0.value))" }.joined(separator: "&").utf8)
}

private func restIsContainer(_ value: Any) -> Bool {
    value is [Any?] || value is [String: Any?]
}

private func restCollect(_ out: inout [RestEntry], _ key: String, _ value: Any?, _ bracket: Bool, _ comma: Bool, _ inList: Bool) {
    guard let value, !(value is NSNull) else { return }
    if let list = value as? [Any?] {
        let items = list.compactMap { $0 }.filter { !($0 is NSNull) }
        if items.isEmpty { return }
        if !inList && !items.contains(where: restIsContainer) {
            if comma {
                out.append(RestEntry(key, items.map { restText($0) }.joined(separator: ",")))
            } else {
                for item in items { out.append(RestEntry(key, restText(item))) }
            }
        } else {
            for (index, element) in list.enumerated() {
                restCollect(&out, bracket ? "\(key)[\(index)]" : "\(key).\(index)", element, bracket, comma, true)
            }
        }
    } else if let map = value as? [String: Any?] {
        for name in map.keys.sorted() {
            restCollect(&out, bracket ? "\(key)[\(name)]" : "\(key).\(name)", map[name] ?? nil, bracket, comma, false)
        }
    } else {
        out.append(RestEntry(key, restText(value)))
    }
}

public func restEntries(_ key: String, _ value: Any?, bracket: Bool = false, comma: Bool = false) -> [RestEntry] {
    var out: [RestEntry] = []
    restCollect(&out, key, value, bracket, comma, false)
    return out
}

public func restSpreadEntries(_ json: Any?, _ names: [(String, String)], bracket: Bool = false, comma: Bool = false) -> [RestEntry] {
    var out: [RestEntry] = []
    if let map = json as? [String: Any?] {
        for (field, wire) in names {
            restCollect(&out, wire, map[field] ?? nil, bracket, comma, false)
        }
    }
    return out
}

public func restHeaderValue(_ value: Any) -> String {
    if let list = value as? [Any?] {
        return list.compactMap { $0 }.map { restText($0) }.joined(separator: ",")
    }
    return restText(value)
}

public func restHeader(_ name: String, _ value: Any?) -> [String: String] {
    guard let value, !(value is NSNull) else { return [:] }
    return [name: restHeaderValue(value)]
}

public func restHeaders(_ json: Any?, _ names: [(String, String)]) -> [String: String] {
    var out: [String: String] = [:]
    if let map = json as? [String: Any?] {
        for (field, header) in names {
            if let value = map[field] ?? nil, !(value is NSNull) { out[header] = restHeaderValue(value) }
        }
    }
    return out
}

public func restHeaderSet(_ parts: [String: String]...) -> [String: String] {
    var out: [String: String] = [:]
    for part in parts { out.merge(part) { _, new in new } }
    return out
}

public func restParts(_ entries: [RestEntry]) -> [RestPart] {
    entries.map { RestPart(name: $0.name, value: $0.value) }
}

public func restNavigate(_ json: Any?, _ path: [String]) -> Any? {
    var current = json
    for segment in path {
        if let map = current as? [String: Any?] {
            current = map[segment] ?? nil
        } else {
            current = nil
        }
    }
    return current
}
''';

String swiftRestNoGraphQL(bool withOperationName) => '''
public let glNoGraphQL__: GraphLinkClientAdapter = { ${withOperationName ? '_, _' : '_'} in
    throw RestDecodeError("This schema has no GraphQL operation: pass no GraphQL adapter")
}
''';

const swiftRestResolver = r'''
open class GraphLinkRestResolver: GraphLinkResolverBase, @unchecked Sendable {
    public var restAdapter: GLRestAdapter?

    func restCall(_ request: RestRequest) async throws -> RestResponse {
        guard let adapter = restAdapter else { throw RestDecodeError("No REST adapter configured") }
        let response = try await adapter(request)
        if !response.isSuccess { throw try await RestError.from(response) }
        return response
    }

    func restVoid(_ request: RestRequest) async throws {
        try await restCall(request).drain()
    }

    func restDownload(_ request: RestRequest, onProgress: DownloadProgressCallback?) async throws -> GLDownload? {
        let response = try await restCall(request)
        if response.status == 204 {
            try await response.drain()
            return nil
        }
        return GLDownload.fromResponse(response, onProgress: onProgress)
    }

    func restDownloadRequired(_ request: RestRequest, onProgress: DownloadProgressCallback?) async throws -> GLDownload {
        guard let download = try await restDownload(request, onProgress: onProgress) else {
            throw RestDecodeError("Empty REST response for a non-null download of \(request.method) \(request.path)")
        }
        return download
    }

    func restText(_ request: RestRequest) async throws -> String {
        try await restCall(request).text()
    }

    func restTextOrNull(_ request: RestRequest) async throws -> String? {
        let text = try await restCall(request).text()
        return text.isEmpty ? nil : text
    }

    func restJson(_ request: RestRequest, path: [String], allowEmpty: Bool) async throws -> Any? {
        let value = restNavigate(try await restCall(request).json(), path)
        if value == nil && !allowEmpty {
            throw RestDecodeError("Empty REST response for a non-null result of \(request.method) \(request.path)")
        }
        return value
    }

    func restCached<T>(
        _ name: String,
        _ variables: [String: Any?],
        ttl: Int,
        tags: [String],
        staleIfOffline: Bool,
        fetch: () async throws -> Any?,
        decode: (Any?) throws -> T
    ) async throws -> T {
        let key = try GraphLinkPartialQuery.computeCacheKey(name, variables)
        let cached = try await getFromCache(key, tags: tags, staleIfOffline: staleIfOffline)
        if let cached, !cached.stale { return try decode(try restCachedValue(cached)) }
        let json: Any?
        do {
            json = try await fetch()
        } catch let error as RestError {
            throw error
        } catch {
            if let cached { return try decode(try restCachedValue(cached)) }
            throw error
        }
        let value = try decode(json)
        if let json {
            let wrapped: [String: Any?] = ["__gl_v__": json]
            let entry = GraphLinkCacheEntry(
                data: String(decoding: try GraphLinkJson.encode(wrapped), as: UTF8.self),
                expiry: Int(Date().timeIntervalSince1970 * 1000) + ttl * 1000
            )
            await store.set(key, value: String(decoding: try GraphLinkJson.encode(entry.toJson()), as: UTF8.self))
            if !tags.isEmpty { try await addKeyToTags(key, tags: tags) }
        }
        return value
    }

    private func restCachedValue(_ entry: GraphLinkCacheEntry) throws -> Any? {
        (try GraphLinkJson.decode(Data(entry.data.utf8)))["__gl_v__"] ?? nil
    }
}
''';

const swiftRestUrlSessionAdapter = r'''
public struct DefaultGraphLinkRestAdapter: Sendable {
    private let baseUrl: String
    private let headersProvider: (@Sendable () -> [String: String])?
    private let session: URLSession

    public init(baseUrl: String, headersProvider: (@Sendable () -> [String: String])? = nil, session: URLSession? = nil) {
        self.baseUrl = baseUrl
        self.headersProvider = headersProvider
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    public func execute(_ request: RestRequest) async throws -> RestResponse {
        guard let url = restUrl(baseUrl, request) else {
            throw RestDecodeError("Invalid REST URL: \(baseUrl)\(request.path)")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        var headers = headersProvider?() ?? [:]
        for (name, value) in request.headers { headers[name] = value }
        var streamed: (chunks: GLChunks, length: Int?)?
        switch request.body {
        case .json(let data):
            urlRequest.httpBody = data
        case .form(let entries):
            urlRequest.httpBody = restFormBody(entries)
        case .multipart(let parts):
            let multipart = GLMultipartBody(parts: parts.map {
                GLMultipartPart(name: $0.name, value: $0.value, file: $0.file, mimeType: $0.mimeType)
            })
            headers["Content-Type"] = multipart.contentType
            streamed = (multipart.chunks(), multipart.length)
        case .raw(let upload):
            streamed = (upload.chunks(), upload.length)
        case nil:
            break
        }
        for (name, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: name) }

        if let streamed {
            let (data, response) = try await GLStreamedUpload.send(
                urlRequest,
                chunks: streamed.chunks,
                length: streamed.length,
                session: session,
                onProgress: request.onSendProgress
            )
            return try Self.response(response, RestResponse.fromData(status: 0, data: data).stream)
        }
        let (bytes, response) = try await session.bytes(for: urlRequest)
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    buffer.reserveCapacity(16384)
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 16384 {
                            continuation.yield(buffer)
                            buffer = Data()
                            buffer.reserveCapacity(16384)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return try Self.response(response, stream)
    }

    private static func response(_ response: URLResponse, _ stream: AsyncThrowingStream<Data, Error>) throws -> RestResponse {
        guard let http = response as? HTTPURLResponse else { throw RestDecodeError("Not an HTTP response") }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String { headers[name.lowercased()] = String(describing: value) }
        }
        return RestResponse(status: http.statusCode, headers: headers, stream: stream)
    }
}
''';
