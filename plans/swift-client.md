# Swift Client Generation

## Context

GraphLink already generates fully-typed clients for Dart, Java, TypeScript, and Kotlin.
This plan adds Swift as a fifth client target, aimed at iOS/macOS (SwiftUI) apps.

**Decision: `toJson`/`fromJson` over `[String: Any?]`, not `Codable`.** Every existing
target (Dart/Java/Kotlin/TS) self-serializes through a hand-written `toJson()`/`fromJson()`
pair over an untyped map — that contract is *why* those serializers exist in the first
place, specifically to make interface/union polymorphism a solved, mechanical
`__typename`-dispatch problem rather than a per-target special case. `Codable` was
initially considered for Swift because it's free, but `Codable` has no native open
polymorphism — decoding into a `protocol` requires either a sealed enum-of-associated-
values wrapper (extra type most callers don't want) or a lot of manual `init(from:)`
work per interface. Since GraphQL interfaces/unions are exactly the problem
`toJson`/`fromJson` was already built to solve everywhere else, Swift uses the same
pattern: `[String: Any?]` in, `[String: Any?]` out, decoded/encoded via Foundation's
`JSONSerialization` (not `JSONDecoder`/`JSONEncoder`, which only operate on `Decodable`/
`Encodable` typed targets and can't produce a raw dictionary). This makes `SwiftSerializer`
structurally the same shape as `KotlinSerializer`/`JavaSerializer` — recursive
`toJson`/`fromJson` expression builders — rather than a fundamentally different codec
design, and it means the cache layer, `@glMapsTo`, and anything else built on the
"every generated type is Map-serializable" contract work unchanged for Swift.

Swift still differs from the existing targets in ways that simplify or change generation:
- Native `async`/`await` and `AsyncThrowingStream` cover queries/mutations and
  subscriptions — no coroutine/Flow/RxJS equivalent to bolt on.
- `URLSession` (Foundation) provides HTTP and WebSocket (`URLSessionWebSocketTask`) with
  zero external dependencies — matches the "zero runtime dependency" rule directly.
- `actor` gives a safe, idiomatic cache store without manual locking.
- Interfaces/unions decode into the **protocol type directly** via a static `__typename`-
  dispatch factory (mirrors Kotlin's `when`-based `fromJson` almost exactly) — no wrapper
  enum needed, unlike what an earlier draft of this plan proposed for `Codable`.

The remaining new wrinkles vs. existing targets:
- Swift doesn't auto-synthesize a `public` memberwise initializer — generated `struct`s
  need an explicit `public init(...)`.
- `JSONSerialization` doesn't accept Swift `nil` boxed inside `Any` — `toJson()` must
  substitute `NSNull()` for nullable fields that are absent, and `fromJson` must treat
  `NSNull` and Swift `nil` as equivalent on read. One shared helper in the generated
  runtime handles this once; per-type `toJson`/`fromJson` don't need to think about it.
- Swift reserved words (`self`, `Self`, `Type`, `class`, `default`, `in`, …) colliding
  with GraphQL field/enum-value names need backtick escaping in generated Swift
  identifiers (property names, `case` labels) — this is independent of the
  serialization approach and applies either way.

---

## Configuration

Config key: `clientConfig.swift` (same level as `clientConfig.kotlin`).

```json
{
  "mode": "client",
  "outputDir": "Sources/Generated",
  "clientConfig": {
    "swift": {
      "moduleName": "GraphLinkGenerated",
      "autoGenerateQueries": true,
      "wsAdapter": "urlsession"
    }
  }
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `moduleName` | string | required | Used only in doc comments / generated `Package.swift` (if emitted); generated files have no module declaration |
| `generateAllFieldsFragments` | bool | `true` | Generate `_all_fields` fragments |
| `autoGenerateQueries` | bool | `true` | Auto-generate queries from schema |
| `operationNameAsParameter` | bool | `false` | Pass operation name as adapter parameter |
| `nullableFieldsRequired` | bool | `false` | Nullable fields required in `init` (no default `= nil`) |
| `captureErrors` | bool | `false` | Return full response including errors |
| `immutableTypeFields` | bool | `true` | `let` vs `var` for struct properties (mirrors `KotlinClientConfig.immutableTypeFields`) |
| `wsAdapter` | string | `urlsession` | `"urlsession"` or `"none"` |

No `httpAdapter` option — `URLSession` is part of Foundation and available on all Apple
platforms plus Linux (swift-corelibs-foundation), so there's only one HTTP adapter,
analogous to Java's `java11` default.

---

## Type Mappings

### Scalars

| GraphQL | Swift |
|---|---|
| `String` | `String` |
| `Int` | `Int` |
| `Float` | `Double` |
| `Boolean` | `Bool` |
| `ID` | `String` |
| custom scalar | configurable via `typeMappings` |

### Nullability

`String!` → `String`
`String` → `String?`
`[String!]!` → `[String]`
`[String!]` → `[String]?`

---

## Generated constructs

### Enum

```graphql
enum Gender { male female }
```

```swift
public enum Gender: String, Sendable {
    case male
    case female

    public func toJson() -> String { rawValue }

    public static func fromJson(_ value: String) -> Gender {
        Gender(rawValue: value)!
    }
}
```

`String`-backed `RawRepresentable` gives `rawValue`/`init(rawValue:)` for free; `toJson`/
`fromJson` are one-line wrappers around it, matching the shape of `toJson`/`fromJson` on
every other generated type (uniform call convention for callers and for recursive
field-level (de)serialization, even though an enum's "map" is just a `String`). If a
GraphQL enum value collides with a Swift keyword (`default`, `in`, …) or isn't a valid
identifier (starts with a digit, etc.), emit an explicit `rawValue` per case:

```swift
public enum SortOrder: String, Sendable {
    case `default` = "default"
    case ascending = "ASC"

    public func toJson() -> String { rawValue }
    public static func fromJson(_ value: String) -> SortOrder { SortOrder(rawValue: value)! }
}
```

---

### Input type (`struct`)

```graphql
input CreateUserInput {
  name: String!
  email: String!
  role: UserRole
}
```

```swift
public struct CreateUserInput: Sendable {
    public let name: String
    public let email: String
    public let role: UserRole?

    public init(name: String, email: String, role: UserRole? = nil) {
        self.name = name
        self.email = email
        self.role = role
    }

    public func toJson() -> [String: Any?] {
        ["name": name, "email": email, "role": role?.toJson()]
    }

    public static func fromJson(_ map: [String: Any?]) -> CreateUserInput {
        CreateUserInput(
            name: map["name"] as! String,
            email: map["email"] as! String,
            role: (map["role"] as? String).map { UserRole.fromJson($0) }
        )
    }
}
```

- `toJson`/`fromJson` mirror `KotlinSerializer`'s field-expression builders directly —
  scalar fields pass through, enum/projectable fields recurse via `.toJson()`/`.fromJson()`,
  optional fields use `?.`/`as?` the same way Kotlin uses `?.let{}`.
- `immutableTypeFields = false` → `var` instead of `let` (still requires the explicit
  `init`, since memberwise inits are never `public`).
- `nullableFieldsRequired = true` → drop the `= nil` default on nullable params.
- Fields whose GraphQL name is a Swift reserved word (`self`, `Type`, `default`, …) are
  declared with backticks (`` `default` ``) — the backtick identifier *is* the property
  name, and the generated `toJson`/`fromJson` map key is the original GraphQL field name
  (a string literal), so there is no key/identifier mismatch to reconcile the way
  `CodingKeys` would have needed.
- `fromJson` is a reasonable place to also apply the `NSNull`-vs-`nil` normalization noted
  above, likely via a small shared helper (`GraphLinkJson.unwrap(map["role"])`) rather than
  repeating the check per field.

---

### GraphQL `type` → Swift `struct`

```graphql
type User {
  id: ID!
  name: String!
  email: String
}
```

```swift
public struct User: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let email: String?

    public init(id: String, name: String, email: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
    }

    public func toJson() -> [String: Any?] {
        ["id": id, "name": name, "email": email]
    }

    public static func fromJson(_ map: [String: Any?]) -> User {
        User(
            id: map["id"] as! String,
            name: map["name"] as! String,
            email: map["email"] as? String
        )
    }
}
```

Types with an `id: ID!` field automatically conform to `Identifiable` — a small but
high-value SwiftUI ergonomics win (`List(users) { ... }` works with no boilerplate).
`Identifiable` needs no extra code beyond the `id` property already being generated.

If the type implements a GraphQL `interface`, add `__typename` to the emitted map (see
Interfaces/unions below) and conform to the protocol — same as Kotlin implementing the
interface and overriding `toJson`.

---

### GraphQL `interface` / `union` → `protocol` + static dispatch factory

This is the payoff of choosing `toJson`/`fromJson` over `Codable`: interfaces/unions
decode into the **protocol type directly**, via a static factory that switches on
`__typename` — the same mechanical pattern `KotlinSerializer` already generates as a
`when` expression (`lib/src/serializers/kotlin_serializer.dart` lines ~376-397), just
Swift syntax. No wrapper enum, no custom `Decoder`/`Encoder` conformance.

```graphql
interface Node { id: ID! }
type User implements Node { id: ID! name: String! }
type Admin implements Node { id: ID! level: Int! }
```

```swift
public protocol Node: Sendable {
    var id: String { get }
    func toJson() -> [String: Any?]
}

public enum NodeJson {
    public static func fromJson(_ map: [String: Any?]) -> any Node {
        switch map["__typename"] as? String {
        case "User": return User.fromJson(map)
        case "Admin": return Admin.fromJson(map)
        case let other:
            fatalError("Unknown Node type: \(other ?? "nil")")
        }
    }
}

public struct User: Node {
    public let id: String
    public let name: String

    public func toJson() -> [String: Any?] {
        ["__typename": "User", "id": id, "name": name]
    }

    public static func fromJson(_ map: [String: Any?]) -> User {
        User(id: map["id"] as! String, name: map["name"] as! String)
    }
}

public struct Admin: Node {
    public let id: String
    public let level: Int

    public func toJson() -> [String: Any?] {
        ["__typename": "Admin", "id": id, "level": level]
    }

    public static func fromJson(_ map: [String: Any?]) -> Admin {
        Admin(id: map["id"] as! String, level: map["level"] as! Int)
    }
}
```

`User`/`Admin` conform to `Node` directly — no wrapper type. A field typed `Node` in the
schema generates as `any Node` in Swift, decoded via `NodeJson.fromJson(map)`. Callers
access shared fields straight off the protocol value (`node.id`), and can pattern-match
to a concrete type with `as?` (`node as? User`) when they need type-specific fields —
equivalent to Kotlin's `is User` smart-cast on the interface-typed value, and no worse
ergonomics than the previously-proposed `case .user(let v)` unwrap.

`enum` namespacing (`NodeJson`, not an extension on the protocol) is used for the static
factory because Swift protocols cannot dispatch a "which concrete type is this JSON"
decision — that information only exists in the untyped map, before any concrete type is
known, so it can't live as a protocol requirement. Naming convention:
`<InterfaceName>Json.fromJson(_:)`, generated once per interface/union.

This removes the plan's previously flagged highest-risk item (no existing-target
precedent for polymorphic decoding) — it's now the same `__typename`-switch pattern
already proven in `KotlinSerializer`, `JavaSerializer`, `DartSerializer`, and the
TypeScript serializer, just re-emitted in Swift syntax.

---

### `@glMapsTo` mapping methods (Swift)

Same `toXxx()` / `fromXxx()` pattern as Java/Kotlin/Dart, generated as an `extension`:

```swift
extension CreateUserInput {
    public func toUser() -> User {
        User(id: UUID().uuidString, name: name, email: nil)
    }

    public static func fromUser(_ user: User) -> CreateUserInput {
        CreateUserInput(name: user.name, email: user.email ?? "")
    }
}
```

List fields use `.map { }`; optional chaining (`?.`) covers nullable sub-mappings. Logic
mirrors `KotlinSerializer._toMappingExpr` / `_fromMappingExpr`.

---

## Client operation methods

### Query (cache-aware)

```swift
public func getUser(id: String) async throws -> User {
    let operationName = "GetUser"
    let variables: [String: Any?] = ["id": id]
    // partial query / cache logic mirrors the Kotlin implementation
    let payload = buildPayload(query: remaining, operationName: operationName, variables: variables)
    let responseData = try await adapter(payload)
    let fullResponse = try parseAndCache(responseData, GetUserFullResponse.fromJson, remaining)
    return User.fromJson(fullResponse.data!["getUser"] as! [String: Any?])
}
```

### Mutation

```swift
public func createUser(input: CreateUserInput) async throws -> User {
    let operationName = "CreateUser"
    let payload = GraphLinkPayload(
        query: Self.createUserQuery,
        operationName: operationName,
        variables: ["input": input.toJson()]
    )
    let responseData = try await adapter(try GraphLinkJson.encode(payload.toJson()))
    let result = CreateUserFullResponse.fromJson(try GraphLinkJson.decode(responseData))
    if let errors = result.errors { throw GraphLinkException(errors: errors) }
    return User.fromJson(result.data!["createUser"] as! [String: Any?])
}
```

### Subscription

```swift
public func watchUser(id: String) -> AsyncThrowingStream<UserEvent, Error> {
    let payload = GraphLinkPayload(
        query: Self.watchUserQuery,
        operationName: "WatchUser",
        variables: ["id": id]
    )
    return wsAdapter.subscribe(payload: payload, decode: UserEvent.fromJson)
}
```

`AsyncThrowingStream` is the natural Swift-Concurrency analogue of Kotlin's `Flow<T>` /
Dart's `Stream<T>` / RxJS `Observable<T>` — `for try await event in client.subscriptions.watchUser(id: "1") { ... }`.

---

## Generated file structure

```
outputDir/
  Enums/          *.swift  (one file per enum)
  Inputs/         *.swift  (one file per input)
  Types/          *.swift  (one file per type / projected type)
  Interfaces/      *.swift  (protocol + *Value enum per interface/union)
  Client/
    GraphLinkClient.swift
    GraphLinkQueries.swift           (if hasQueries)
    GraphLinkMutations.swift         (if hasMutations)
    GraphLinkSubscriptions.swift     (if hasSubscriptions)
    GraphLinkClientAdapter.swift     (typealias: (Data) async throws -> Data)
    GraphLinkPayload.swift
    GraphLinkFullResponse.swift
    GraphLinkError.swift
    GraphLinkException.swift
    GraphLinkPartialQuery.swift
    GraphLinkCacheStore.swift         (protocol)
    InMemoryGraphLinkCacheStore.swift (actor)
    GraphLinkCacheEntry.swift
    GraphLinkTagEntry.swift
    DefaultGraphLinkURLSessionAdapter.swift   (URLSession-based HTTP, if wsAdapter != none or always)
    [if hasUploadMutations:]
      GLUpload.swift
      GraphLinkMultipartAdapter.swift   (URLSession multipart/form-data)
    [if hasSubscriptions:]
      GraphLinkWebSocketAdapter.swift           (protocol)
      DefaultGraphLinkWebSocketAdapter.swift    (URLSessionWebSocketTask, auto-reconnect)
      GraphLinkSubscriptionHandler.swift
      GraphLinkWsMessageTypes.swift
```

Each file gets a `// GENERATED` header (no `package`/`import module` line, since Swift
files don't declare their containing module — the consumer adds these files to a target
or SPM package). Files are named `PascalCase.swift` matching the type name, following
Swift convention (same as Java/Kotlin).

No `Package.swift` is generated by default — these are source files meant to be dropped
into an existing Xcode project or SPM target, same as how Dart/Kotlin output drops into
an existing `lib/`/`src/`. (Could revisit if there's demand for a standalone SPM package.)

---

## Codec design

Like Dart/Java/Kotlin/TS, there **is** a generated codec — it's just built on
`JSONSerialization` instead of `JSONDecoder`/`JSONEncoder`, since `Codable`'s decoder
only knows how to populate `Decodable` typed targets and can't hand back a raw
`[String: Any?]` the way `dart:convert.jsonDecode` or Jackson's `readValue(..., Map.class)`
do. A small `GraphLinkJson` enum wraps the two Foundation calls generated code needs:

```swift
public enum GraphLinkJson {
    public static func decode(_ data: Data) throws -> [String: Any?] {
        let obj = try JSONSerialization.jsonObject(with: data)
        return (obj as? [String: Any?]) ?? [:]
    }

    public static func encode(_ map: [String: Any?]) throws -> Data {
        try JSONSerialization.data(withJSONObject: normalize(map))
    }

    // JSONSerialization rejects Swift `nil` boxed in `Any` — substitute NSNull
    // recursively so nullable fields serialize as JSON null instead of crashing.
    static func normalize(_ value: Any?) -> Any {
        switch value {
        case nil: return NSNull()
        case let dict as [String: Any?]: return dict.mapValues(normalize)
        case let arr as [Any?]: return arr.map(normalize)
        case let v?: return v
        }
    }
}
```

The per-operation `*FullResponse` types (mirroring `GetVehicleResponse` etc.) are plain
structs with hand-written `toJson`/`fromJson`, same as every other target — no `Decodable`
conformance:

```swift
public struct GetUserFullResponse {
    public let data: [String: Any?]?
    public let errors: [GraphLinkError]?

    public static func fromJson(_ map: [String: Any?]) -> GetUserFullResponse {
        GetUserFullResponse(
            data: map["data"] as? [String: Any?],
            errors: (map["errors"] as? [[String: Any?]])?.map(GraphLinkError.fromJson)
        )
    }
}
```

This makes `SwiftSerializer` structurally the same size/shape as `KotlinSerializer`/
`JavaSerializer` — it is **not** the "smallest serializer, `Codable` does the work" design
from the earlier draft of this plan. The trade is deliberate: consistency with the
polymorphism-solving `toJson`/`fromJson` contract across all five targets beats the
per-target size win `Codable` would have given Swift alone.

Custom scalars that don't map to a built-in Swift type (e.g. `DateTime` → `Date`) get a
conversion pair on the field, same as Kotlin/Java handle custom scalar `typeMappings` —
`toJson` emits an ISO8601 string via `ISO8601DateFormatter`, `fromJson` parses it back.
No `Codable` strategy hook needed since there's no `Codable` in this design.

---

## New source files

| File | Role |
|---|---|
| `lib/src/swift_code_gen_utils.dart` | Swift code generation primitives (keyword escaping, `init` generation, `Sendable`/`Identifiable` conformance rules) |
| `lib/src/serializers/swift_serializer.dart` | Types / inputs / enums / interfaces serializer, extends `GLSerializer` |
| `lib/src/serializers/client_serializers/swift_client_context.dart` | Shared context + safe variable names |
| `lib/src/serializers/client_serializers/swift_client_operation_serializer.dart` | Generates `async`/`async throws` operation methods + `AsyncThrowingStream` subscriptions |
| `lib/src/serializers/client_serializers/swift_client_serializer.dart` | Assembles `GLClassModel` instances for all client files |
| `lib/src/serializers/client_serializers/swift_client_constants.dart` | Static Swift code strings (cache actor, URLSession adapters, payload/response types) |
| `lib/src/generators/swift_client_generator.dart` | Orchestrates file writing, mirrors `kotlin_client_generator.dart` |

## Modified source files

| File | Change |
|---|---|
| `lib/src/config.dart` | Add `SwiftWsAdapter` enum (`urlsession`/`none`), `SwiftClientConfig` class, update `ClientLanguageConfig.fromJson()` |
| `lib/src/main.dart` | Add import, export, dispatch for `SwiftClientConfig`, update help text |

---

## Reused utilities (no changes)

- `lib/src/serializers/gl_serializer.dart` — base class
- `lib/src/serializers/gl_client_serializer.dart` — base client class
- `lib/src/serializers/gl_graphql_serializer.dart` — GQL query string generation
- `lib/src/io_utils.dart` — `writeToFile`, `cleanUpObsoleteFiles`
- `lib/src/model/gl_input_mapping.dart` — `ToMappingPlan`, `FromMappingPlan`
- `lib/src/capture_errors_utils.dart` — `isCaptureErrors`, `clientExceptionName`
- `lib/src/gl_grammar_cache_extension.dart` — cache tag/TTL logic
- `lib/src/gl_grammar_upload_extension.dart` — upload detection
- `lib/src/code_gen_utils.dart` — `CodeGenUtilsBase` interface

---

## Open questions / risks

- ~~Polymorphic interfaces/unions~~ **Resolved:** protocol + static `__typename`-dispatch
  factory (`NodeJson.fromJson`), mirroring `KotlinSerializer`'s existing `when`-based
  dispatch. No wrapper enum, no custom `Decoder`/`Encoder` conformance, no precedent gap —
  this is now the same pattern already proven in four other targets.
- **`[String: Any?]` casting safety.** `as!`/`as?` force- and optional-casts on dictionary
  values are inherently less type-safe than `Codable`'s compiler-checked decoding — a
  server response with an unexpected type for a field crashes (`as!`) or silently produces
  a wrong value (`as?` misuse) rather than failing to compile. This is not a new risk
  relative to Dart/Java/Kotlin/TS (they all have the identical exposure via their own
  `Map`-based `fromJson`), but it's worth being explicit that Swift is not gaining
  `Codable`'s safety net here — it was deliberately traded away for the interface-dispatch
  win, matching every other target's existing trade-off.
- **`NSNull`/nil normalization** must be applied consistently by every generated
  `toJson`/`fromJson`, not just remembered ad hoc — likely enforced by having field-level
  (de)serialization always route through the shared `GraphLinkJson.normalize`/an unwrap
  helper rather than each serializer call site handling it independently. Worth nailing
  down the exact helper API before generation starts, since it's used by every single
  generated `toJson`/`fromJson` pair.
- **Linux/server-side Swift**: `URLSessionWebSocketTask` works on Linux via
  swift-corelibs-foundation; `JSONSerialization` is also part of swift-corelibs-foundation
  and should be fine, but both should be smoke-tested — if `URLSessionWebSocketTask`
  doesn't work, `wsAdapter: "none"` becomes the only option for non-Apple platforms.
- **Swift 6 strict concurrency**: generated code should compile cleanly under
  `-strict-concurrency=complete`. `Sendable` conformance on all generated types is
  assumed throughout this plan — needs validation once real generation starts, especially
  for the cache actor, the WebSocket adapter, and `[String: Any?]` itself (`Any` is not
  automatically `Sendable`; may need `@unchecked Sendable` on the JSON map typealias with
  a documented justification, since the maps are only ever built from JSON-safe leaf
  types).

---

## Tests

Add `test/swift/` following the same pattern as `test/kotlin/`:

- `test/swift/basic/swift_basic_test.dart` — enum, input struct, type struct, interface/protocol serialization
- `test/swift/client/swift_client_test.dart` — query/mutation/subscription method generation
- `test/swift/maps_to/swift_maps_to_test.dart` — `@glMapsTo` mapping method generation

Run: `dart test test/swift/`

A `server_integration_tests`-style real-server suite (Swift client + the existing Spring
Boot test server) would be the natural follow-up once the basic generator is stable —
mirrors `integration_tests/dart_client_tests_real/` etc.
