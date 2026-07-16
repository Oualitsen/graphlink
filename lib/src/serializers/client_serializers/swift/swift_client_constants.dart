const swiftClientException = 'GraphLinkException';
const swiftClientName = 'GraphLinkClient';

// ── Adapter ──────────────────────────────────────────────────────────────────

const swiftGraphLinkClientAdapter = '''
public typealias GraphLinkClientAdapter = (Data) async throws -> Data
''';

const swiftGraphLinkClientAdapterWithOperationName = '''
public typealias GraphLinkClientAdapter = (Data, String) async throws -> Data
''';

// ── JSON codec ──────────────────────────────────────────────────────────────
//
// Unlike Kotlin/Java/TS, there is no pluggable encoder/decoder interface —
// `JSONSerialization` is a concrete Foundation API, not a third-party codec
// choice, so `GraphLinkJson` is the one and only codec every generated
// `toJson`/`fromJson` and client file relies on.

const swiftGraphLinkJson = '''
public enum GraphLinkJson {
    public static func decode(_ data: Data) throws -> [String: Any?] {
        let obj = try JSONSerialization.jsonObject(with: data)
        return (obj as? [String: Any?]) ?? [:]
    }

    public static func encode(_ map: [String: Any?]) throws -> Data {
        try JSONSerialization.data(withJSONObject: normalize(map))
    }

    /// `JSONSerialization` rejects Swift `nil` boxed inside `Any` — this
    /// substitutes `NSNull` recursively so nullable fields serialize as
    /// JSON `null` instead of crashing.
    static func normalize(_ value: Any?) -> Any {
        switch value {
        case nil: return NSNull()
        case let dict as [String: Any?]: return dict.mapValues(normalize)
        case let arr as [Any?]: return arr.map(normalize)
        case let v?: return v
        }
    }
}
''';

// ── Cache store ──────────────────────────────────────────────────────────────
//
// Every method is `async` — not because the protocol requires concurrency,
// but so a single protocol covers both a synchronous conformer and the
// `actor`-based default (actor methods are implicitly async when called
// from outside the actor). Mirrors Kotlin's `GraphLinkCacheStore` shape.

const swiftGraphLinkCacheStore = '''
public protocol GraphLinkCacheStore: Sendable {
    func set(_ key: String, value: String) async
    func get(_ key: String) async -> String?
    func invalidate(_ key: String) async
    func invalidateAll() async
}
''';

const swiftInMemoryGraphLinkCacheStore = '''
public actor InMemoryGraphLinkCacheStore: GraphLinkCacheStore {
    private var store: [String: String] = [:]

    public init() {}

    public func set(_ key: String, value: String) {
        store[key] = value
    }

    public func get(_ key: String) -> String? {
        store[key]
    }

    public func invalidate(_ key: String) {
        store.removeValue(forKey: key)
    }

    public func invalidateAll() {
        store.removeAll()
    }
}
''';

// ── Cache metadata ────────────────────────────────────────────────────────────
//
// `GraphLinkPayload` and `GraphLinkError` are deliberately NOT defined here:
// both are synthetic types already registered in the grammar (so schema
// tooling and the generated `toJson`/`fromJson` for e.g. `GraphLinkError.path`/
// `.extensions`/`.locations` come from the real GraphQL type shape, not a
// hand-maintained guess), and SwiftClientGenerator's `allProjectedTypes` loop
// already emits them into `Types/` via the standard SwiftSerializer path —
// see swift_client_generator.dart. Hand-authoring them again here produced a
// duplicate `struct GraphLinkPayload`/`GraphLinkError` declaration (caught by
// `swift build`'s "multiple producers" error). Kotlin already avoids this:
// `KotlinClientSerializer.generatePayloadFile()` exists but is never called
// by kotlin_client_generator.dart (dead code — the synthetic-type pipeline
// alone produces GraphLinkPayload.kt), and Kotlin never even has a
// hand-written GraphLinkError constant to begin with.

const swiftGraphLinkCacheEntry = '''
public struct GraphLinkCacheEntry: Sendable {
    public let data: String
    public let expiry: Int
    public let stale: Bool

    public init(data: String, expiry: Int, stale: Bool = false) {
        self.data = data
        self.expiry = expiry
        self.stale = stale
    }

    public func isExpired() -> Bool {
        Int(Date().timeIntervalSince1970 * 1000) > expiry
    }

    public func asStale() -> GraphLinkCacheEntry {
        GraphLinkCacheEntry(data: data, expiry: expiry, stale: true)
    }

    public func toJson() -> [String: Any?] {
        ["data": data, "expiry": expiry]
    }

    public static func fromJson(_ map: [String: Any?]) -> GraphLinkCacheEntry {
        GraphLinkCacheEntry(
            data: map["data"] as! String,
            expiry: map["expiry"] as! Int
        )
    }
}
''';

const swiftGraphLinkTagEntry = '''
public struct GraphLinkTagEntry: Sendable {
    public var keys: Set<String>

    public init(keys: Set<String> = []) {
        self.keys = keys
    }

    public mutating func add(_ key: String) {
        keys.insert(key)
    }

    public mutating func remove(_ key: String) {
        keys.remove(key)
    }

    public func toJson() -> [String: Any?] {
        ["keys": Array(keys)]
    }

    public static func fromJson(_ map: [String: Any?]) -> GraphLinkTagEntry {
        let list = (map["keys"] as? [Any?])?.compactMap { \$0 as? String } ?? []
        return GraphLinkTagEntry(keys: Set(list))
    }
}
''';

/// `cacheKey` is a plain throwing method, not a Kotlin-style `by lazy`
/// stored property — a lazily-mutated stored property on a `Sendable`
/// value type has no safe way to synchronize the first write under
/// concurrent access, whereas recomputing an FNV-1a hash over already-small
/// variable maps on demand is cheap enough not to need caching at all.
// See swiftGraphLinkPayload above for why @unchecked Sendable is used here.
const swiftGraphLinkPartialQuery = '''
public struct GraphLinkPartialQuery: @unchecked Sendable {
    public let query: String
    public let variables: [String: Any?]
    public let ttl: Int
    public let tags: [String]
    public let operationName: String
    public let elementKey: String
    public let fragmentNames: Set<String>
    public let argumentDeclarations: [String]
    public let staleIfOffline: Bool

    public init(
        query: String,
        variables: [String: Any?],
        ttl: Int,
        tags: [String],
        operationName: String,
        elementKey: String,
        fragmentNames: Set<String>,
        argumentDeclarations: [String],
        staleIfOffline: Bool
    ) {
        self.query = query
        self.variables = variables
        self.ttl = ttl
        self.tags = tags
        self.operationName = operationName
        self.elementKey = elementKey
        self.fragmentNames = fragmentNames
        self.argumentDeclarations = argumentDeclarations
        self.staleIfOffline = staleIfOffline
    }

    public func cacheKey() throws -> String {
        var sorted: [String: Any?] = [:]
        for key in variables.keys.sorted() {
            sorted[key] = variables[key]
        }
        let encoded = try GraphLinkJson.encode(sorted)
        let raw = operationName + ":" + (String(data: encoded, encoding: .utf8) ?? "")
        return GraphLinkPartialQuery.fnv1a(raw)
    }

    private static func fnv1a(_ input: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash)
    }
}
''';

// ── Exception ─────────────────────────────────────────────────────────────────
//
// GraphLinkError itself is not defined here — see the comment above
// swiftGraphLinkCacheEntry; it's a synthetic grammar type generated into
// Types/GraphLinkError.swift. GraphLinkException just wraps a list of it.

const swiftGraphLinkException = '''
public struct GraphLinkException: Error, Sendable {
    public let errors: [GraphLinkError]

    public init(errors: [GraphLinkError]) {
        self.errors = errors
    }
}
''';

// ── Resolver base ─────────────────────────────────────────────────────────────
//
// Mirrors Kotlin's `GraphLinkResolverBase` open class (see
// kotlin_client_serializer.dart's generateGraphLinkResolverBaseFile): the
// shared engine every generated `GraphLinkQueries`/`Mutations`/`Subscriptions`
// class subclasses. `GraphLinkQueries`/etc. use real Swift subclassing
// (`class GraphLinkQueries: GraphLinkResolverBase`) rather than composition —
// the most direct translation of Kotlin's `open class` inheritance.
//
// Per-tag locking: Kotlin uses one `ReentrantLock` per cache tag, pre-seeded
// from `grammar.getAllCacheTags()`. Swift has no lock primitive that's safe to
// hold across an `await` suspension point, so `GraphLinkTagLocks` (an actor)
// instead chains a `Task` per tag — each new tag-scoped operation awaits the
// previous one for that same tag before running, giving the same "only one
// mutation in flight per tag" guarantee without ever blocking a thread. No
// upfront tag list is needed: entries are created lazily on first use.
//
// `parseToObjectAndCache`/`executeFull`/`executeData`/`executeCached` mirror
// Kotlin's generic `<T : GraphLinkFullResponse>` methods using Swift's
// `<T: GraphLinkFullResponse>` protocol-constrained generics — `data`/`errors`
// FullResponse types and the `GraphLinkFullResponse` protocol already exist
// via the synthetic-type pipeline (Types/<Op>FullResponse.swift,
// Interfaces/GraphLinkFullResponse.swift), so no hand-written duplicate is
// needed here (same reasoning as swiftGraphLinkCacheEntry above).

String swiftGraphLinkResolverBase(bool withOpName) => '''
actor GraphLinkTagLocks {
    private var chains: [String: Task<Void, Never>] = [:]

    func run<T: Sendable>(_ tag: String, _ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        let previous = chains[tag]
        let box = Task<T, Error> {
            _ = await previous?.value
            return try await operation()
        }
        chains[tag] = Task { _ = try? await box.value }
        return try await box.value
    }
}

open class GraphLinkResolverBase: @unchecked Sendable {
    private let adapter: GraphLinkClientAdapter
    let fragmentMap: [String: String]
    let store: any GraphLinkCacheStore
    private let tagLocks = GraphLinkTagLocks()

    public init(adapter: @escaping GraphLinkClientAdapter, fragmentMap: [String: String], store: any GraphLinkCacheStore) {
        self.adapter = adapter
        self.fragmentMap = fragmentMap
        self.store = store
    }

    func glCallAdapter(_ payload: GraphLinkPayload) async throws -> Data {
        let body = try GraphLinkJson.encode(payload.toJson())
        return try await adapter(body${withOpName ? ', payload.operationName' : ''})
    }

    func parseToObjectAndCache<T: GraphLinkFullResponse>(
        data: Data,
        cachedResponse: [String: Any?],
        parser: ([String: Any?]) -> T,
        remainingQueries: [GraphLinkPartialQuery],
        captureErrors: Bool
    ) async throws -> T {
        let result = try GraphLinkJson.decode(data)
        let rawData = result["data"] as? [String: Any?]
        var dataMap = rawData ?? [:]
        for q in remainingQueries {
            if q.ttl > 0, let inner = dataMap[q.elementKey], let value = inner {
                let cacheWrap: [String: Any?] = ["__gl_v__": value]
                let expiry = Int(Date().timeIntervalSince1970 * 1000) + q.ttl * 1000
                let cacheData = try GraphLinkJson.encode(cacheWrap)
                let entry = GraphLinkCacheEntry(data: String(data: cacheData, encoding: .utf8) ?? "", expiry: expiry)
                let entryData = try GraphLinkJson.encode(entry.toJson())
                await store.set(try q.cacheKey(), value: String(data: entryData, encoding: .utf8) ?? "")
                if !q.tags.isEmpty { try await addKeyToTags(q.cacheKey(), tags: q.tags) }
            }
        }
        for (k, v) in cachedResponse { dataMap[k] = v }
        var fullResponse: [String: Any?] = ["data": rawData != nil ? dataMap : nil]
        if result.keys.contains("errors") { fullResponse["errors"] = result["errors"] }
        let parsed = parser(fullResponse)
        if captureErrors { return parsed }
        let errors = result["errors"] as? [Any?]
        if let errors, !errors.isEmpty {
            throw GraphLinkException(errors: parsed.errors ?? [])
        }
        return parsed
    }

    func executeFull<T: GraphLinkFullResponse>(
        query: String,
        fragmentNames: Set<String>,
        operationName: String,
        variables: [String: Any?],
        fromJson: ([String: Any?]) -> T
    ) async throws -> T {
        let fullQuery = assembleQuery(query, fragmentNames: fragmentNames)
        let payload = GraphLinkPayload(query: fullQuery, operationName: operationName, variables: variables)
        let responseData = try await glCallAdapter(payload)
        return fromJson(try GraphLinkJson.decode(responseData))
    }

    func executeData<T: GraphLinkFullResponse>(
        query: String,
        fragmentNames: Set<String>,
        operationName: String,
        variables: [String: Any?],
        fromJson: ([String: Any?]) -> T
    ) async throws -> T {
        let decoded = try await executeFull(query: query, fragmentNames: fragmentNames, operationName: operationName, variables: variables, fromJson: fromJson)
        if let errors = decoded.errors, !errors.isEmpty {
            throw GraphLinkException(errors: errors)
        }
        return decoded
    }

    func executeCached<T: GraphLinkFullResponse>(
        partialQueries: [GraphLinkPartialQuery],
        operationName: String,
        directives: String,
        fromJson: ([String: Any?]) -> T,
        captureErrors: Bool
    ) async throws -> T {
        var responseMap: [String: Any?] = [:]
        var staleData: [String: Any?] = [:]
        for partQuery in partialQueries {
            if partQuery.ttl > 0 {
                if let entry = try? await getFromCache(partQuery.cacheKey(), tags: partQuery.tags, staleIfOffline: partQuery.staleIfOffline) {
                    let decoded = (try? GraphLinkJson.decode(entry.data.data(using: .utf8) ?? Data()))?["__gl_v__"]
                    if entry.stale {
                        staleData[partQuery.elementKey] = decoded ?? nil
                    } else {
                        responseMap[partQuery.elementKey] = decoded ?? nil
                    }
                }
            }
        }
        let remaining = partialQueries.filter { !responseMap.keys.contains(\$0.elementKey) }
        if remaining.isEmpty {
            let wrappedResponse: [String: Any?] = ["data": responseMap]
            return fromJson(wrappedResponse)
        }
        let payload = buildPayload(remaining, operationName: operationName, directives: directives)
        do {
            let responseData = try await glCallAdapter(payload)
            return try await parseToObjectAndCache(data: responseData, cachedResponse: responseMap, parser: fromJson, remainingQueries: remaining, captureErrors: captureErrors)
        } catch {
            for (k, v) in staleData { responseMap[k] = v }
            let remainingCount = partialQueries.filter { !responseMap.keys.contains(\$0.elementKey) }.count
            if remainingCount > 0 { throw error }
            let wrappedResponse: [String: Any?] = ["data": responseMap]
            return fromJson(wrappedResponse)
        }
    }

    func getFromCache(_ key: String, tags: [String], staleIfOffline: Bool) async throws -> GraphLinkCacheEntry? {
        guard let result = await store.get(key) else { return nil }
        let entry = GraphLinkCacheEntry.fromJson(try GraphLinkJson.decode(result.data(using: .utf8) ?? Data()))
        if entry.isExpired() {
            if staleIfOffline { return entry.asStale() }
            await store.invalidate(key)
            if !tags.isEmpty { try await removeKeyFromTags(key, tags: tags) }
            return nil
        }
        return entry
    }

    func invalidateByTags(_ tags: [String]) async throws {
        for tag in tags {
            try await tagLocks.run(tag) {
                let tKey = self.tagKey(tag)
                if let data = await self.store.get(tKey) {
                    let entry = GraphLinkTagEntry.fromJson(try GraphLinkJson.decode(data.data(using: .utf8) ?? Data()))
                    for k in entry.keys { await self.store.invalidate(k) }
                    await self.store.invalidate(tKey)
                }
            }
        }
    }

    func addKeyToTags(_ key: String, tags: [String]) async throws {
        for tag in tags {
            try await tagLocks.run(tag) {
                let tKey = self.tagKey(tag)
                var entry: GraphLinkTagEntry
                if let data = await self.store.get(tKey) {
                    entry = GraphLinkTagEntry.fromJson(try GraphLinkJson.decode(data.data(using: .utf8) ?? Data()))
                } else {
                    entry = GraphLinkTagEntry()
                }
                entry.add(key)
                let entryData = try GraphLinkJson.encode(entry.toJson())
                await self.store.set(tKey, value: String(data: entryData, encoding: .utf8) ?? "")
            }
        }
    }

    func removeKeyFromTags(_ key: String, tags: [String]) async throws {
        for tag in tags {
            try await tagLocks.run(tag) {
                let tKey = self.tagKey(tag)
                guard let data = await self.store.get(tKey) else { return }
                var entry = GraphLinkTagEntry.fromJson(try GraphLinkJson.decode(data.data(using: .utf8) ?? Data()))
                entry.remove(key)
                if entry.keys.isEmpty {
                    await self.store.invalidate(tKey)
                } else {
                    let entryData = try GraphLinkJson.encode(entry.toJson())
                    await self.store.set(tKey, value: String(data: entryData, encoding: .utf8) ?? "")
                }
            }
        }
    }

    private func tagKey(_ tag: String) -> String { "__tag__\\(tag)" }

    func buildPayload(_ partQueries: [GraphLinkPartialQuery], operationName: String, directives: String) -> GraphLinkPayload {
        var variables: [String: Any?] = [:]
        for q in partQueries { for (k, v) in q.variables { variables[k] = v } }
        var args: Set<String> = []
        for q in partQueries { args.formUnion(q.argumentDeclarations) }
        var queryBuilder = "query \\(operationName)"
        if !args.isEmpty {
            queryBuilder += "(" + args.joined(separator: ", ") + ")"
        }
        if !directives.isEmpty { queryBuilder += directives }
        queryBuilder += "{"
        for q in partQueries { queryBuilder += q.query + " " }
        queryBuilder += "}"
        var fragmentNames: Set<String> = []
        for q in partQueries { fragmentNames.formUnion(q.fragmentNames) }
        for fragName in fragmentNames {
            if let frag = fragmentMap[fragName] { queryBuilder += frag }
        }
        return GraphLinkPayload(query: queryBuilder, operationName: operationName, variables: variables)
    }

    func assembleQuery(_ query: String, fragmentNames: Set<String>) -> String {
        var buffer = query
        for name in fragmentNames {
            if let frag = fragmentMap[name] {
                buffer += "\\n" + frag
            }
        }
        return buffer
    }
}
''';

// ── Default HTTP adapter (URLSession) ────────────────────────────────────────
//
// No OkHttp-vs-JDK11-style choice the way Java/Kotlin have — `URLSession`
// is part of Foundation on every Apple platform plus Linux
// (swift-corelibs-foundation), so it's the only adapter, analogous to
// Java's `java11` default with no alternative ever generated.

// ── Upload ────────────────────────────────────────────────────────────────────
//
// Kotlin's `GLUpload` wraps a raw `InputStream` for true streaming uploads.
// Swift has no directly equivalent portable byte-stream type outside
// Combine/AsyncSequence machinery, so `GLUpload` holds the file as `Data`
// instead — simpler and correct for the typical mobile/desktop upload sizes
// this client targets, at the cost of not streaming arbitrarily large files
// from disk without buffering them in memory first.
const swiftGLUpload = '''
public struct GLUpload: Sendable {
    public let data: Data
    public let mimeType: String
    public let filename: String?

    public init(data: Data, mimeType: String = "application/octet-stream", filename: String? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.filename = filename
    }
}
''';

const swiftUploadProgressCallback = '''
public typealias UploadProgressCallback = @Sendable (Int, Int) -> Void
''';

const swiftGraphLinkMultipartAdapter = '''
public typealias GraphLinkMultipartAdapter = (Data, Data, [String: GLUpload], UploadProgressCallback?) async throws -> Data
''';

// `onProgress` is only invoked once, after the full multipart body has been
// built and handed to `URLSession.upload(for:from:)` — true incremental
// progress needs a `URLSessionTaskDelegate` hooked to the session, which is
// beyond what this default adapter does; it exists to satisfy the
// `UploadProgressCallback?` parameter shape, not to provide real streaming
// progress. Swap in a custom `GraphLinkMultipartAdapter` closure for that.
const swiftDefaultGraphLinkURLSessionMultipartAdapter = '''
public struct DefaultGraphLinkURLSessionMultipartAdapter: Sendable {
    private let url: URL
    private let headersProvider: (@Sendable () -> [String: String])?
    private let session: URLSession

    public init(url: URL, headersProvider: (@Sendable () -> [String: String])? = nil, session: URLSession = .shared) {
        self.url = url
        self.headersProvider = headersProvider
        self.session = session
    }

    public func executeMultipart(_ operations: Data, _ mapJson: Data, _ files: [String: GLUpload], _ onProgress: UploadProgressCallback?) async throws -> Data {
        let boundary = "GraphLinkBoundary-" + UUID().uuidString
        var body = Data()

        func appendField(_ name: String, _ value: Data) {
            body.append("--\\(boundary)\\r\\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\\"\\(name)\\"\\r\\n\\r\\n".data(using: .utf8)!)
            body.append(value)
            body.append("\\r\\n".data(using: .utf8)!)
        }

        appendField("operations", operations)
        appendField("map", mapJson)
        for (key, upload) in files {
            let filename = upload.filename ?? key
            body.append("--\\(boundary)\\r\\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\\"\\(key)\\"; filename=\\"\\(filename)\\"\\r\\n".data(using: .utf8)!)
            body.append("Content-Type: \\(upload.mimeType)\\r\\n\\r\\n".data(using: .utf8)!)
            body.append(upload.data)
            body.append("\\r\\n".data(using: .utf8)!)
        }
        body.append("--\\(boundary)--\\r\\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\\(boundary)", forHTTPHeaderField: "Content-Type")
        headersProvider?().forEach { request.setValue(\$1, forHTTPHeaderField: \$0) }

        onProgress?(body.count, body.count)
        let (data, _) = try await session.upload(for: request, from: body)
        return data
    }
}
''';

// ── WebSocket adapter (subscriptions) ───────────────────────────────────────────

const swiftGraphLinkWebSocketAdapter = '''
public protocol GraphLinkWebSocketAdapter: AnyObject, Sendable {
    func connect(onConnect: @escaping @Sendable () -> Void, onFailure: @escaping @Sendable (Error) -> Void)
    func sendMessage(_ message: String)
    func close()
    func setMessageListener(_ listener: @escaping @Sendable (String) -> Void)
    func setReconnectListener(_ onReconnect: @escaping @Sendable () -> Void)
    func connectionInitPayload() -> [String: Any?]?
}

public extension GraphLinkWebSocketAdapter {
    func connectionInitPayload() -> [String: Any?]? { nil }
}
''';

const swiftGraphlinkWsMessageTypes = '''
public enum GraphlinkWsMessageTypes {
    public static let connectionInit = "connection_init"
    public static let connectionAck = "connection_ack"
    public static let subscribe = "subscribe"
    public static let ping = "ping"
    public static let pong = "pong"
    public static let next = "next"
    public static let error = "error"
    public static let complete = "complete"
}
''';

// `GraphLinkAckStatus` is NOT defined here — it's a synthetic grammar enum
// (`enum GraphLinkAckStatus {none progress acknoledged}` in constants.dart's
// clientObjects) shared by every language, so it's already emitted into
// Enums/GraphLinkAckStatus.swift by the standard enum-generation pipeline.

// ── Default WebSocket adapter (URLSessionWebSocketTask) ─────────────────────────

const swiftDefaultGraphLinkWebSocketAdapter = '''
public final class DefaultGraphLinkWebSocketAdapter: GraphLinkWebSocketAdapter, @unchecked Sendable {
    private let url: URL
    private let headersProvider: (@Sendable () -> [String: String])?
    private let session: URLSession
    private let maxReconnectAttempts: Int?
    private let maxReconnectDelay: TimeInterval
    private let wsProtocols: [String]

    private let lock = NSLock()
    private var webSocketTask: URLSessionWebSocketTask?
    private var messageListener: (@Sendable (String) -> Void)?
    private var reconnectListener: (@Sendable () -> Void)?
    private var disposed = false
    private var reconnectAttempts = 0

    public init(
        url: URL,
        headersProvider: (@Sendable () -> [String: String])? = nil,
        session: URLSession = .shared,
        maxReconnectAttempts: Int? = 10,
        maxReconnectDelay: TimeInterval = 30,
        wsProtocols: [String] = ["graphql-transport-ws"]
    ) {
        self.url = url
        self.headersProvider = headersProvider
        self.session = session
        self.maxReconnectAttempts = maxReconnectAttempts
        self.maxReconnectDelay = maxReconnectDelay
        self.wsProtocols = wsProtocols
    }

    public func connect(onConnect: @escaping @Sendable () -> Void, onFailure: @escaping @Sendable (Error) -> Void) {
        lock.lock()
        disposed = false
        reconnectAttempts = 0
        lock.unlock()
        connectInternal(onConnect: onConnect, onFailure: onFailure)
    }

    private func connectInternal(onConnect: @escaping @Sendable () -> Void, onFailure: @escaping @Sendable (Error) -> Void) {
        var request = URLRequest(url: url)
        if !wsProtocols.isEmpty {
            request.setValue(wsProtocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        headersProvider?().forEach { request.setValue(\$1, forHTTPHeaderField: \$0) }
        let task = session.webSocketTask(with: request)
        lock.lock()
        webSocketTask = task
        lock.unlock()
        task.resume()
        onConnect()
        listen(task: task, onFailure: onFailure)
    }

    private func listen(task: URLSessionWebSocketTask, onFailure: @escaping @Sendable (Error) -> Void) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.messageListener?(text)
                case .data(let data): self.messageListener?(String(data: data, encoding: .utf8) ?? "")
                @unknown default: break
                }
                self.listen(task: task, onFailure: onFailure)
            case .failure:
                self.lock.lock()
                let wasDisposed = self.disposed
                self.lock.unlock()
                if !wasDisposed { self.scheduleReconnect(onFailure: onFailure) }
            }
        }
    }

    private func scheduleReconnect(onFailure: @escaping @Sendable (Error) -> Void) {
        lock.lock()
        if disposed { lock.unlock(); return }
        reconnectAttempts += 1
        let attempts = reconnectAttempts
        lock.unlock()
        if let max = maxReconnectAttempts, attempts > max {
            onFailure(NSError(domain: "GraphLinkWebSocketAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max reconnect attempts reached"]))
            return
        }
        let baseDelay = min(1.0 * pow(2.0, Double(min(attempts - 1, 30))), maxReconnectDelay)
        let jitter = Double.random(in: 0...1)
        DispatchQueue.global().asyncAfter(deadline: .now() + baseDelay + jitter) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let wasDisposed = self.disposed
            self.lock.unlock()
            if wasDisposed { return }
            self.connectInternal(
                onConnect: {
                    self.lock.lock()
                    self.reconnectAttempts = 0
                    self.lock.unlock()
                    self.reconnectListener?()
                },
                onFailure: onFailure
            )
        }
    }

    public func sendMessage(_ message: String) {
        lock.lock()
        let task = webSocketTask
        lock.unlock()
        task?.send(.string(message), completionHandler: { _ in })
    }

    public func close() {
        lock.lock()
        disposed = true
        let task = webSocketTask
        lock.unlock()
        task?.cancel(with: .normalClosure, reason: nil as Data?)
    }

    public func setMessageListener(_ listener: @escaping @Sendable (String) -> Void) {
        lock.lock(); messageListener = listener; lock.unlock()
    }

    public func setReconnectListener(_ onReconnect: @escaping @Sendable () -> Void) {
        lock.lock(); reconnectListener = onReconnect; lock.unlock()
    }

    public func connectionInitPayload() -> [String: Any?]? {
        guard let headers = headersProvider?(), !headers.isEmpty else { return nil }
        return headers
    }
}
''';

// ── Subscription handler (AsyncThrowingStream-based) ────────────────────────────
//
// Mirrors Kotlin's `GraphLinkSubscriptionHandler` (`callbackFlow`-based), but
// stores the `AsyncThrowingStream.Continuation` per subscription id directly
// instead of a plain yield closure — that lets server "error"/"complete"
// messages call `continuation.finish(throwing:)` / `.finish()` precisely,
// rather than Kotlin's synthetic `"__gl_error__"` sentinel map key.

const swiftGraphLinkSubscriptionHandler = '''
public final class GraphLinkSubscriptionHandler: @unchecked Sendable {
    private let adapter: any GraphLinkWebSocketAdapter
    private let lock = NSLock()
    private var listeners: [String: AsyncThrowingStream<[String: Any?], Error>.Continuation] = [:]
    private var payloadsToHandle: [String: GraphLinkPayload] = [:]
    private var activePayloads: [String: GraphLinkPayload] = [:]
    private var ackStatus: GraphLinkAckStatus = .none

    public init(adapter: any GraphLinkWebSocketAdapter) {
        self.adapter = adapter
        self.adapter.setMessageListener { [weak self] msg in self?.onMessage(msg) }
        self.adapter.setReconnectListener { [weak self] in self?.handleReconnect() }
    }

    public func handle(_ payload: GraphLinkPayload) -> AsyncThrowingStream<[String: Any?], Error> {
        AsyncThrowingStream { continuation in
            let uuid = UUID().uuidString
            lock.lock()
            listeners[uuid] = continuation
            activePayloads[uuid] = payload
            lock.unlock()
            initConnection(id: uuid, payload: payload)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.listeners.removeValue(forKey: uuid)
                self.activePayloads.removeValue(forKey: uuid)
                self.lock.unlock()
            }
        }
    }

    private func initConnection(id: String, payload: GraphLinkPayload) {
        var shouldConnect = false
        var shouldSend = false
        lock.lock()
        switch ackStatus {
        case .none:
            payloadsToHandle[id] = payload
            ackStatus = .progress
            shouldConnect = true
        case .progress:
            payloadsToHandle[id] = payload
        case .acknoledged:
            shouldSend = true
        }
        lock.unlock()
        if shouldConnect {
            adapter.connect(
                onConnect: { [weak self] in
                    guard let self else { return }
                    self.adapter.sendMessage(self.getConnectionInit(id))
                },
                onFailure: { [weak self] error in self?.notifyAllListenersOfError(error) }
            )
        } else if shouldSend {
            adapter.sendMessage(getSubscriptionMessage(id: id, payload: payload))
        }
    }

    private func encodeMessage(_ map: [String: Any?]) -> String {
        (try? GraphLinkJson.encode(map)).flatMap { String(data: \$0, encoding: .utf8) } ?? "{}"
    }

    private func getConnectionInit(_ id: String) -> String {
        var msg: [String: Any?] = ["type": GraphlinkWsMessageTypes.connectionInit, "id": id]
        if let initPayload = adapter.connectionInitPayload() { msg["payload"] = initPayload }
        return encodeMessage(msg)
    }

    private func getSubscriptionMessage(id: String, payload: GraphLinkPayload) -> String {
        encodeMessage([
            "type": GraphlinkWsMessageTypes.subscribe,
            "id": id,
            "payload": [
                "query": payload.query,
                "operationName": payload.operationName,
                "variables": payload.variables,
            ] as [String: Any?],
        ])
    }

    private func getPongMessage(_ id: String?) -> String {
        encodeMessage(["type": GraphlinkWsMessageTypes.pong, "id": id])
    }

    private func onMessage(_ message: String) {
        guard let data = message.data(using: .utf8), let map = try? GraphLinkJson.decode(data) else { return }
        switch map["type"] as? String {
        case GraphlinkWsMessageTypes.connectionAck: handleConnectionAck()
        case GraphlinkWsMessageTypes.ping: adapter.sendMessage(getPongMessage(map["id"] as? String))
        case GraphlinkWsMessageTypes.next: handleNextMessage(map)
        case GraphlinkWsMessageTypes.error: handleError(map)
        case GraphlinkWsMessageTypes.complete: handleComplete(map["id"] as? String)
        default: break
        }
    }

    private func handleConnectionAck() {
        lock.lock()
        ackStatus = .acknoledged
        let entries = payloadsToHandle
        payloadsToHandle.removeAll()
        lock.unlock()
        for (id, payload) in entries { adapter.sendMessage(getSubscriptionMessage(id: id, payload: payload)) }
    }

    private func handleNextMessage(_ map: [String: Any?]) {
        guard let id = map["id"] as? String else { return }
        guard let payloadMap = map["payload"] as? [String: Any?], let data = payloadMap["data"] as? [String: Any?] else { return }
        lock.lock()
        let listener = listeners[id]
        lock.unlock()
        listener?.yield(data)
    }

    private func handleError(_ map: [String: Any?]) {
        guard let id = map["id"] as? String else { return }
        lock.lock()
        let listener = listeners.removeValue(forKey: id)
        activePayloads.removeValue(forKey: id)
        lock.unlock()
        listener?.finish(throwing: NSError(domain: "GraphLinkSubscriptionHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Subscription error"]))
    }

    private func handleComplete(_ id: String?) {
        guard let id else { return }
        lock.lock()
        let listener = listeners.removeValue(forKey: id)
        activePayloads.removeValue(forKey: id)
        lock.unlock()
        listener?.finish()
    }

    private func notifyAllListenersOfError(_ error: Error) {
        lock.lock()
        let snapshot = Array(listeners.values)
        listeners.removeAll()
        activePayloads.removeAll()
        payloadsToHandle.removeAll()
        ackStatus = .none
        lock.unlock()
        snapshot.forEach { \$0.finish(throwing: error) }
    }

    private func handleReconnect() {
        lock.lock()
        let snapshot = activePayloads
        ackStatus = snapshot.isEmpty ? .none : .progress
        for (k, v) in snapshot { payloadsToHandle[k] = v }
        let firstId = snapshot.keys.first
        lock.unlock()
        if let firstId {
            adapter.sendMessage(getConnectionInit(firstId))
        }
    }
}
''';

String swiftDefaultGraphLinkURLSessionAdapter(bool withOperationName) => '''
public struct DefaultGraphLinkURLSessionAdapter: Sendable {
    private let url: URL
    private let headersProvider: (@Sendable () -> [String: String])?
    private let session: URLSession

    public init(
        url: URL,
        headersProvider: (@Sendable () -> [String: String])? = nil,
        session: URLSession = .shared
    ) {
        self.url = url
        self.headersProvider = headersProvider
        self.session = session
    }

    public func execute(_ payload: Data${withOperationName ? ', _ operationName: String' : ''}) async throws -> Data {
        var request = URLRequest(url: ${withOperationName ? 'url.appending(queryItems: [URLQueryItem(name: "operationName", value: operationName)])' : 'url'})
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headersProvider?().forEach { request.setValue(\$1, forHTTPHeaderField: \$0) }
        request.httpBody = payload
        let (data, _) = try await session.data(for: request)
        return data
    }
}
''';
