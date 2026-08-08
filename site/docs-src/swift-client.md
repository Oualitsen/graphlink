---
title: Swift Client — GraphLink Docs
description: Use the generated GraphLink Swift client in iOS, macOS, or server-side Swift projects. async/await queries, mutations, and AsyncThrowingStream subscriptions, with Sendable structs and zero third-party dependencies.
---

# Swift Client

A fully typed GraphQL client generated from your schema — idiomatic Swift with `async`/`await`,
`Sendable` structs, and no third-party dependency. `URLSession` (Foundation) is the only transport
used, so the generated code compiles unchanged on Apple platforms and on Linux
(swift-corelibs-foundation).

## Configuration

Set `"mode": "client"` and add a `"swift"` key under `clientConfig`:

=== "JSON"

    ```json title="glink.json"
    {
      "schemaPaths": ["schema/*.graphql"],
      "mode": "client",
      "typeMappings": {
        "ID":      "String",
        "String":  "String",
        "Float":   "Double",
        "Int":     "Int",
        "Boolean": "Bool"
      },
      "outputDir": "Sources/GraphLinkGenerated",
      "clientConfig": {
        "swift": {
          "moduleName": "GraphLinkGenerated",
          "generateAllFieldsFragments": true,
          "autoGenerateQueries": true,
          "immutableTypeFields": true,
          "wsAdapter": "urlsession"
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml"
    schemaPaths:
      - schema/*.graphql
    mode: client
    typeMappings:
      ID: String
      String: String
      Float: Double
      Int: Int
      Boolean: Bool
    outputDir: Sources/GraphLinkGenerated
    clientConfig:
      swift:
        moduleName: GraphLinkGenerated
        generateAllFieldsFragments: true
        autoGenerateQueries: true
        immutableTypeFields: true
        wsAdapter: urlsession
    ```

## Generated output

For a schema with `User`, `Post`, `CreateUserInput`, and a `UserStatus` enum, GraphLink generates:

```
Sources/GraphLinkGenerated/
  Client/
    GraphLinkClient.swift               ← main client (queries / mutations / subscriptions)
    GraphLinkQueries.swift
    GraphLinkMutations.swift
    GraphLinkSubscriptions.swift
    GraphLinkClientAdapter.swift        ← HTTP adapter typealias
    DefaultGraphLinkURLSessionWebSocketAdapter.swift
    GraphLinkMultipartAdapter.swift     ← file-upload adapter typealias
    GraphLinkCacheStore.swift           ← cache store protocol
    InMemoryGraphLinkCacheStore.swift   ← actor-based in-memory cache
    GraphLinkCacheEntry.swift
    GraphLinkTagEntry.swift
    GraphLinkPartialQuery.swift
    GraphLinkException.swift
    GLUpload.swift                      ← file upload type
    ...
  Types/
    User.swift
    Post.swift
    CreateUserResponse.swift
    ...
  Inputs/
    CreateUserInput.swift
  Enums/
    UserStatus.swift
  Interfaces/
    SearchResult.swift                  ← generated union/interface protocol
```

## Structs

Types and inputs are generated as `Sendable` structs with an explicit memberwise `init` and
`toJson()`/`fromJson()`:

```swift
// generated
public struct User: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let email: String?
    public let status: UserStatus
    public let address: Address

    public init(
        id: String,
        name: String,
        email: String? = nil,
        status: UserStatus,
        address: Address
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.status = status
        self.address = address
    }

    public func toJson() -> [String: Any?] {
        return [
            "id": id,
            "name": name,
            "email": email,
            "status": status.toJson(),
            "address": address.toJson(),
        ]
    }

    public static func fromJson(_ map: [String: Any?]) -> User {
        return User(
            id: map["id"] as! String,
            name: map["name"] as! String,
            email: map["email"] as? String,
            status: UserStatus.fromJson(map["status"] as! String),
            address: Address.fromJson(map["address"] as! [String: Any?])
        )
    }
}
```

A type is additionally `Identifiable` whenever it has a non-null `id` field — ready to drop into
a SwiftUI `List` without extra glue.

## Enums

```swift
// generated
public enum UserStatus: String, Sendable {
    case active = "ACTIVE"
    case inactive = "INACTIVE"
    case suspended = "SUSPENDED"

    public func toJson() -> String {
        return rawValue
    }

    public static func fromJson(_ value: String) -> UserStatus {
        return UserStatus(rawValue: value)!
    }
}
```

An unrecognized wire value force-unwraps to a crash, matching the throwing behavior of the
Kotlin/Java/TypeScript enum `fromJson` — treat an unknown enum value from the server as a
programmer/contract error, not a value to silently swallow.

## Queries

All query, mutation, and subscription methods are `async throws` — call them from an `async`
context:

```swift
import GraphLinkGenerated

let user = try await client.queries.getUser(id: "user-42").getUser
print("\(user.name) — \(user.status)")
```

Compound queries that resolve multiple fields in a single network call return a typed response
with one property per top-level resolver:

```swift
let result = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
let user = result.user   // User
let post = result.post   // Post
```

One HTTP call — two fully typed results.

## Mutations

Input structs are plain memberwise-initialized `Sendable` structs — construct them directly, no
builder boilerplate:

```swift
let input = CreateUserInput(
    name: "Alice Smith",
    email: "alice@example.com",
    status: .active,
    address: AddressInput(street: "123 Main St", city: "Springfield", country: "US", zip: "12345")
)

let response = try await client.mutations.createUser(input: input)
print(response.createUser.id)   // "user-1"
```

Nullable input fields default to `nil` — omit them when you don't need them:

```swift
let patch = UpdateUserInput(status: .inactive)   // only sets status
try await client.mutations.updateUser(id: "user-1", input: patch)
```

## Subscriptions

Subscriptions return an `AsyncThrowingStream` backed by a WebSocket connection. Iterate it with
`for try await`:

```swift
let task = Task {
    for try await event in client.subscriptions.userCreated() {
        print("New user: \(event.userCreated.name)")
    }
}

// cancel when done
task.cancel()
```

Events are deserialized into the same typed response structs used by queries.

## Projected types

When a query selects only a subset of a type's fields, GraphLink generates a dedicated projected
struct instead of reusing the full type, so the Swift compiler catches field misuse at compile
time:

```swift
// schema query that selects only id, name, status
let summary = try await client.queries.fetchUserSummary(id: "user-1").getUser
// summary is User_IdNameStatus — only .id, .name, .status are available
print(summary.status)   // UserStatus.active
```

## Union and interface types

Union members are dispatched via `__typename`. Each member type conforms to the generated
protocol:

```swift
let results: [SearchResult] = try await client.queries.runSearch(query: "alice").search

for result in results {
    switch result {
    case let user as UserResult: print("User: \(user.name)")
    case let post as PostResult: print("Post: \(post.title)")
    default: break
    }
}
```

## Wiring the client

### HTTP adapter

`GraphLinkClientAdapter` is a plain closure typealias — implement it with `URLSession` or any
HTTP client of your choice:

```swift
import GraphLinkGenerated
import Foundation

let adapter: GraphLinkClientAdapter = { payload in
    var request = URLRequest(url: URL(string: "https://api.example.com/graphql")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = payload

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
        throw GraphLinkException.http
    }
    return data
}
```

### WebSocket adapter (URLSession)

When `wsAdapter: "urlsession"` is set (the default), GraphLink generates a default
`DefaultGraphLinkURLSessionWebSocketAdapter` built on `URLSessionWebSocketTask`. Pass your server
URL and optional headers:

```swift
import GraphLinkGenerated

let wsAdapter = DefaultGraphLinkURLSessionWebSocketAdapter(
    url: URL(string: "wss://api.example.com/graphql")!,
    headers: ["Authorization": "Bearer \(token)"]
)
```

### Assembling the client

```swift
import GraphLinkGenerated

let client = GraphLinkClient(
    adapter: adapter,
    wsAdapter: wsAdapter,
    multipartAdapter: DefaultGraphLinkURLSessionMultipartAdapter()
)

// Use it
let user = try await client.queries.getUser(id: "42").getUser
```

## Caching

Cache behaviour is declared in the schema, not in code:

```graphql
type Query {
  getUser(id: ID!): User! @glCache(ttl: "5m", tags: ["users"])
}
type Mutation {
  updateUser(id: ID!, input: UpdateUserInput!): User! @glCacheInvalidate(tags: ["users"])
}
```

The generated client handles caching transparently through an `actor`-based
`InMemoryGraphLinkCacheStore` — the second call to `getUser` with the same arguments is served
from the cache; `updateUser` evicts it:

```swift
let first  = try await client.queries.getUser(id: "1")   // hits the network
let second = try await client.queries.getUser(id: "1")   // served from cache — no HTTP call

try await client.mutations.updateUser(id: "1", input: UpdateUserInput(status: .inactive))

let third  = try await client.queries.getUser(id: "1")   // cache evicted — hits the network again
```

Bring your own cache store by conforming to `GraphLinkCacheStore` (a `Sendable` protocol) and
passing it to the `GraphLinkClient` initializer.

## Inline error handling (`@glCaptureErrors`)

Enable per-operation inline errors with the directive or globally via config:

```graphql
type Query {
  findUser(id: ID!): User @glCaptureErrors
}
```

```swift
// returns FindUserFullResponse with an optional data + optional errors
let result = try await client.queries.findUser(id: "user-99")
if let errors = result.errors {
    errors.forEach { print($0.message) }
} else {
    print(result.data?.findUser?.name ?? "")
}
```

Enable globally in config with `"captureErrors": true` under `clientConfig.swift`.

## File uploads

Upload mutations accept a `GLUpload` value (raw `Data` plus filename/MIME type) and are sent
through `DefaultGraphLinkURLSessionMultipartAdapter` per the GraphQL multipart request spec:

```swift
let upload = GLUpload(data: fileData, filename: "avatar.png", mimeType: "image/png")
try await client.mutations.uploadAvatar(userId: "1", file: upload)
```

Pass an `UploadProgressCallback` to the generated method to observe upload progress.

## Configuration reference

| Option | Type | Default | Description |
|---|---|---|---|
| `moduleName` | `string` | — | **Required.** Used in doc comments / generated `Package.swift` (if emitted) — generated files have no module declaration of their own. |
| `generateAllFieldsFragments` | `boolean` | `true` | Generate `_all_fields_*` fragments for every type. |
| `autoGenerateQueries` | `boolean` | `true` | Auto-generate query strings for all operations. |
| `nullableFieldsRequired` | `boolean` | `false` | When `true`, nullable initializer parameters have no default. |
| `immutableTypeFields` | `boolean` | `true` | Generate `let` fields (immutable) instead of `var`. |
| `operationNameAsParameter` | `boolean` | `false` | Append the operation name as a `?operationName=` query parameter in the request URL. |
| `captureErrors` | `boolean` | `false` | Return `FullResponse` (data + errors) for all operations instead of throwing. |
| `wsAdapter` | `"urlsession"` \| `"none"` | `"urlsession"` | WebSocket adapter to generate. `"urlsession"` emits `DefaultGraphLinkURLSessionWebSocketAdapter`; `"none"` emits only the adapter typealias. |
| `defaultAlias` | `string?` | `null` | Default alias prefix for auto-generated query fields. |
| `autoGenerateQueriesFor` | `object?` | `null` | Restrict auto-generated operations to an explicit allow-list per operation type. |
| `autoGenerateQueriesArgumentLimit` | `int?` | `200` | Caps propagated field arguments per auto-generated operation before it's skipped with a warning. |
| `maxFragmentBodySize` | `int?` | `8192` | Skips oversized auto-generated `_all_fields` fragments (and dependent auto-queries). Set to `null` to disable. |
