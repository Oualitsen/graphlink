# Swift Client Generation

## Context

GraphLink already generates fully-typed clients for Dart, Java, TypeScript, and Kotlin.
This plan adds Swift as a fifth client target, aimed at iOS/macOS (SwiftUI) apps.

Swift differs from the existing targets in ways that actually *simplify* generation:
- `struct` + `Codable` give us free JSON encode/decode — no hand-written `toJson`/`fromJson`
  needed for plain types and inputs (unlike Dart/Java/Kotlin's `Map<String, Any?>` approach).
- Native `async`/`await` and `AsyncThrowingStream` cover queries/mutations and
  subscriptions — no coroutine/Flow/RxJS equivalent to bolt on.
- `URLSession` (Foundation) provides HTTP and WebSocket (`URLSessionWebSocketTask`) with
  zero external dependencies — matches the "zero runtime dependency" rule directly.
- `actor` gives a safe, idiomatic cache store without manual locking.

The main new wrinkles vs. existing targets:
- Swift doesn't auto-synthesize a `public` memberwise initializer — generated `struct`s
  need an explicit `public init(...)`.
- GraphQL interfaces/unions need an enum-with-associated-values + custom `init(from:)`
  for polymorphic decoding (Swift `Codable` has no built-in polymorphism).
- Swift reserved words (`self`, `Self`, `Type`, `class`, `default`, `in`, …) colliding
  with GraphQL field/enum-value names need `CodingKeys` / backtick escaping.

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
public enum Gender: String, Codable, Sendable {
    case male
    case female
}
```

`Codable` is synthesized automatically for `String`-backed enums whose case names match
the raw GraphQL values. If a GraphQL enum value collides with a Swift keyword (`default`,
`in`, …) or isn't a valid identifier (starts with a digit, etc.), emit an explicit
`rawValue` per case:

```swift
public enum SortOrder: String, Codable, Sendable {
    case `default` = "default"
    case ascending = "ASC"
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
public struct CreateUserInput: Codable, Sendable {
    public let name: String
    public let email: String
    public let role: UserRole?

    public init(name: String, email: String, role: UserRole? = nil) {
        self.name = name
        self.email = email
        self.role = role
    }
}
```

- `Codable` conformance is free — `Encodable` handles serialization for the request
  payload directly via `JSONEncoder`.
- `immutableTypeFields = false` → `var` instead of `let` (still requires the explicit
  `init`, since memberwise inits are never `public`).
- `nullableFieldsRequired = true` → drop the `= nil` default on nullable params.
- Fields whose GraphQL name is a Swift reserved word (`self`, `Type`, `default`, …) are
  declared with backticks (`` `default` ``) — no `CodingKeys` needed since the backtick
  identifier *is* the property name and matches the JSON key.

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
public struct User: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let email: String?

    public init(id: String, name: String, email: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
    }
}
```

Types with an `id: ID!` field automatically conform to `Identifiable` — a small but
high-value SwiftUI ergonomics win (`List(users) { ... }` works with no boilerplate).

---

### GraphQL `interface` / `union` → `protocol` + enum wrapper

Swift `Codable` has no native polymorphic decoding, so interfaces/unions generate two
things: a `protocol` for shared-field access, and an `enum` with associated values for
decoding/dispatch (mirrors the `when`/`switch` pattern in Kotlin/TS but as a value type
rather than a sealed hierarchy).

```graphql
interface Node { id: ID! }
type User implements Node { id: ID! name: String! }
type Admin implements Node { id: ID! level: Int! }
```

```swift
public protocol Node: Sendable {
    var id: String { get }
}

public enum NodeValue: Codable, Sendable {
    case user(User)
    case admin(Admin)

    public var node: any Node {
        switch self {
        case .user(let v): return v
        case .admin(let v): return v
        }
    }

    private enum TypenameKey: String, CodingKey { case __typename }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypenameKey.self)
        switch try container.decode(String.self, forKey: .__typename) {
        case "User": self = .user(try User(from: decoder))
        case "Admin": self = .admin(try Admin(from: decoder))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .__typename, in: container,
                debugDescription: "Unknown Node type: \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .user(let v): try v.encode(to: encoder)
        case .admin(let v): try v.encode(to: encoder)
        }
    }
}
```

`User` and `Admin` both declare `extension User: Node {}` / `extension Admin: Node {}`.
Response types reference `NodeValue` directly; callers that just want the shared fields
use `.node.id`.

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
    let variables: [String: any Sendable] = ["id": id]
    // partial query / cache logic mirrors the Kotlin implementation
    let payload = buildPayload(query: remaining, operationName: operationName, variables: variables)
    let responseData = try await adapter(payload)
    return try await parseAndCache(responseData, GetUserFullResponse.self, remaining).data.getUser
}
```

### Mutation

```swift
public func createUser(input: CreateUserInput) async throws -> User {
    let operationName = "CreateUser"
    let payload = GraphLinkPayload(
        query: Self.createUserQuery,
        operationName: operationName,
        variables: ["input": input]
    )
    let data = try await adapter(try encoder.encode(payload))
    let result = try decoder.decode(CreateUserFullResponse.self, from: data)
    if let errors = result.errors { throw GraphLinkException(errors: errors) }
    return result.data!.createUser
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
    return wsAdapter.subscribe(payload: payload, decode: UserEvent.init(from:))
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

Unlike Dart/Java/Kotlin/TS, there is **no generated codec class** — `JSONEncoder` /
`JSONDecoder` from Foundation are used directly:

```swift
public struct GetUserFullResponse: Decodable, Sendable {
    public let data: GetUserData?
    public let errors: [GraphLinkError]?

    public struct GetUserData: Decodable, Sendable {
        public let getUser: User
    }
}
```

```swift
let decoder = JSONDecoder()
let result = try decoder.decode(GetUserFullResponse.self, from: responseData)
```

This is the biggest structural simplification vs. other targets: types/inputs need **no**
`toJson`/`fromJson` methods at all (Codable handles it), so `SwiftSerializer` is
significantly smaller than `KotlinSerializer`/`JavaSerializer`. The per-operation
`*FullResponse` structs (mirroring `GetVehicleResponse` etc.) are still generated, but
as plain `Decodable` structs with no custom logic.

Custom scalars that don't map to a built-in Swift type (e.g. `DateTime` → `Date`) get a
`CodingKeys`-free custom `init(from:)`/`encode(to:)` only on the *field*, via
`@CustomCodable`-style wrapper structs — deferred to a follow-up if a project needs it;
default `typeMappings` should cover the common cases (`Date` via ISO8601 strategy set on
the shared `JSONDecoder`/`JSONEncoder` instances in `GraphLinkClient`).

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

- **Polymorphic interfaces/unions** (`NodeValue` enum pattern above) is the riskiest new
  piece — no precedent in existing targets, since Dart/Java/Kotlin/TS all decode into a
  base class/interface with `__typename`-based factory functions rather than an
  enum-of-associated-values. Worth a small spike before committing to the pattern.
- **Linux/server-side Swift**: `URLSessionWebSocketTask` and `Codable` work on Linux via
  swift-corelibs-foundation, but should be smoke-tested — if it doesn't, `wsAdapter: "none"`
  becomes the only option for non-Apple platforms.
- **Swift 6 strict concurrency**: generated code should compile cleanly under
  `-strict-concurrency=complete`. `Sendable` conformance on all generated types is
  assumed throughout this plan — needs validation once real generation starts, especially
  for the cache actor and WebSocket adapter.

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
