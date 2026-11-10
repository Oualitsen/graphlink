![GraphLink](../assets/graphlink.png)

# GraphLink

> Define your GraphQL schema once. Get fully typed GraphQL **and** REST clients — for Dart, Flutter, Java, TypeScript, Kotlin, Swift, Python and Go — plus Spring Boot and Express/Apollo servers, in milliseconds.

[![pub.dev](https://img.shields.io/pub/v/graphlink?label=pub.dev)](https://pub.dev/packages/graphlink)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub Releases](https://img.shields.io/github/v/release/Oualitsen/graphlink)](https://github.com/Oualitsen/graphlink/releases/latest)

---

No runtime. No boilerplate. No schema drift.

GraphLink is a CLI tool (`glink`) that reads a `.graphql` file and writes production-ready, idiomatic code for your target language. The generated files have **zero dependency on GraphLink itself** — delete it tomorrow, everything still compiles.

---

## Why GraphLink?

**No generics at the Java call site.**
Every other Java GraphQL client makes you write `TypeReference<GraphQLResponse<Map<String,Object>>>`. GraphLink generates fully-resolved return types:

```java
// Other clients
GraphQLResponse<Map<String, Object>> res = client.query(QUERY_STRING, vars, new TypeReference<>() {});
Vehicle v = objectMapper.convertValue(res.getData().get("getVehicle"), Vehicle.class);

// GraphLink
GetVehicleResponse res = client.queries.getVehicle("42");
System.out.println(res.getGetVehicle().getBrand());
```

**Cache control belongs in your schema.**
Declare caching once with `@glCache` and `@glCacheInvalidate` — the generated client handles TTL, tag-based invalidation, partial query caching, and offline fallback automatically.

**Only what the server needs.**
GraphLink generates minimal, precise query strings. No full-schema dumps that break Spring Boot's strict GraphQL validation.

**Inline error handling.**
Annotate any query or mutation with `@glCaptureErrors` (or set `captureErrors: true` globally) and the generated method returns a `FullResponse` with `data` and `errors` side by side — no try/catch required. Works in every client.

**Single source of truth.**
One `.graphql` file drives every client (Dart, Java, TypeScript, Kotlin, Swift, Python, Go) and the Spring Boot or Express/Apollo server — controllers/resolvers plus service interfaces. Add a field once, regenerate, and every end stays in sync.

**GraphQL and REST in one client.**
A field of `Query` or `Mutation` annotated with `@glRest` is served over HTTP/JSON by the same generated client, with the same call syntax. Remove the directive to move it to GraphQL.

---

## Supported targets

| Target | Language / framework | Status |
|---|---|---|
| Dart client | Dart | Stable |
| Flutter client (UI widget generation) | Dart / Flutter | Stable |
| Java client | Java (blocking, or Reactor / RxJava 3 / Mutiny) | Stable |
| TypeScript client | TypeScript (Angular, React, Vue, Svelte, Node) | Stable |
| Kotlin client | Kotlin (coroutines) | Stable |
| Swift client | Swift (async/await, Apple platforms and Linux) | Stable |
| Python client | Python (pydantic v2, asyncio) | Stable |
| Go client | Go 1.22+ (context-aware, `(value, error)`) | Stable |
| Spring Boot server | Java or Kotlin, MVC or WebFlux | Stable |
| Express / Apollo server | TypeScript (Node.js) | Stable |

Every client generates both **GraphQL** operations and **REST** operations (`@glRest`), caching, subscriptions with auto-reconnect, file uploads, persisted queries and custom scalar codecs. See the [target matrix](https://graphlink.dev/targets.html).

## What's new in 6.0

- **REST operations in every client.** Annotate a field with `@glRest` and the same generated client calls it over HTTP/JSON. Remove the directive to move the field to GraphQL, and the call site stays the same.
- **Python and Go clients.** pydantic v2 models with an `asyncio` client, and plain structs with a `context`-aware client.
- **Scalar codecs.** A `typeMappings` entry can convert a custom scalar (`DateTime`, `Decimal`, ...) on decode and encode.
- **Validated directives.** Unknown or misspelled directive arguments now fail generation with a line and column. `glink --print-directives` prints the declarations for your IDE.
- **Hardened decoding and streaming uploads** in every client. Some of this is breaking: see the [changelog](https://github.com/Oualitsen/graphlink/blob/main/CHANGELOG.md).

---|---|
| Dart client | Stable |
| Flutter client (UI widget generation) | Stable |
| Java client | Stable |
| Spring Boot server | Stable |
| TypeScript client | Stable |
| Kotlin client | Stable |
| Express / Apollo (Node.js) | Stable |

---

## Installation

### Recommended — `glink` CLI (fastest)

The CLI compiles to a native binary — no Dart VM overhead, regenerates in milliseconds even on large schemas.

```bash
# macOS (ARM)
curl -fsSL https://github.com/Oualitsen/graphlink/releases/latest/download/glink-macos-arm64 -o glink
chmod +x glink && sudo mv glink /usr/local/bin/glink

# Linux (x64)
curl -fsSL https://github.com/Oualitsen/graphlink/releases/latest/download/glink-linux-x64 -o glink
chmod +x glink && sudo mv glink /usr/local/bin/glink
```

Also available: `glink-macos-x64`, `glink-linux-arm64`, `glink-windows-x64.exe`
→ [All releases](https://github.com/Oualitsen/graphlink/releases/latest)

### Alternative — Dart / Flutter package

```bash
flutter pub add --dev graphlink
# or
dart pub add --dev graphlink
```

---

## Quick Start

### 1. Write your schema

```graphql
type Vehicle {
  id: ID!
  brand: String!
  model: String!
  year: Int!
  fuelType: FuelType!
}

enum FuelType { GASOLINE DIESEL ELECTRIC HYBRID }

input AddVehicleInput {
  brand: String!
  model: String!
  year: Int!
  fuelType: FuelType!
}

type Query {
  getVehicle(id: ID!): Vehicle!    @glCache(ttl: "2m", tags: ["vehicles"])
  listVehicles: [Vehicle!]!        @glCache(ttl: "1m", tags: ["vehicles"])
}

type Mutation {
  addVehicle(input: AddVehicleInput!): Vehicle! @glCacheInvalidate(tags: ["vehicles"])
}
```

### 2. Configure

Create a `glink.json` (or `glink.yaml` / `glink.yml`) in your project root:

```json
{
  "schemaPaths": ["schema/*.graphql"],
  "mode": "client",
  "typeMappings": { "ID": "String", "Float": "double", "Int": "int", "Boolean": "bool" },
  "outputDir": "lib/generated",
  "clientConfig": {
    "dart": {
      "packageName": "my_app"
    }
  }
}
```

### 3. Generate

```bash
glink                   # auto-discovers glink.json / glink.yaml / glink.yml
glink -c config.json    # explicit config path
glink -w                # watch mode — regenerate on every save
```

---

## Usage

### Dart / Flutter

```dart
final client = GraphLinkClient.withHttp(
  url: 'http://localhost:8080/graphql',
  wsUrl: 'ws://localhost:8080/graphql',
  tokenProvider: () async => await getAuthToken(),
);

// Query — fully typed, no casting
final res = await client.queries.getVehicle(id: '42');
print(res.getVehicle.brand);    // Toyota
print(res.getVehicle.fuelType); // FuelType.GASOLINE

// Mutation
final added = await client.mutations.addVehicle(
  input: AddVehicleInput(brand: 'Toyota', model: 'Camry', year: 2023, fuelType: FuelType.GASOLINE),
);

// Subscription
client.subscriptions.vehicleAdded().listen((e) => print(e.vehicleAdded.brand));
```

### Java

```java
// One-liner init — Jackson + Java 11 HttpClient auto-configured
GraphLinkClient client = new GraphLinkClient("http://localhost:8080/graphql");

// Query — no generics, no casting
GetVehicleResponse res = client.queries.getVehicle("42");
System.out.println(res.getGetVehicle().getBrand());

// Mutation — builder pattern
client.mutations.addVehicle(
    AddVehicleInput.builder()
        .brand("Toyota").model("Camry").year(2023).fuelType(FuelType.GASOLINE)
        .build()
);

// List
List<Vehicle> vehicles = client.queries.listVehicles().getListVehicles();
```

### TypeScript

```typescript
import { GraphLinkClient } from './generated/client/graph-link-client';
import { GraphLinkFetchAdapter } from './generated/client/graph-link-fetch-adapter';

const adapter = new GraphLinkFetchAdapter('http://localhost:8080/graphql');
const client = new GraphLinkClient(adapter.call.bind(adapter));

// Query — fully typed
const res = await client.queries.getVehicle({ id: '42' });
console.log(res.getVehicle.brand);    // Toyota
console.log(res.getVehicle.fuelType); // FuelType.GASOLINE

// Mutation
await client.mutations.addVehicle({
  input: { brand: 'Toyota', model: 'Camry', year: 2023, fuelType: FuelType.GASOLINE },
});

// Subscription
client.subscriptions.vehicleAdded({
  onData: (e) => console.log(e.vehicleAdded.brand),
});
```

### Kotlin

```kotlin
val client = GraphLinkClient.create("http://localhost:8080/graphql")

val vehicle = runBlocking { client.queries.getVehicle("42").getVehicle }
println("${vehicle.brand} ${vehicle.model}")
```

### Swift

```swift
let client = GraphLinkClient.create(
    url: URL(string: "http://localhost:8080/graphql")!,
    wsUrl: URL(string: "ws://localhost:8080/graphql")!
)

let vehicle = try await client.queries.getVehicle(id: "42").getVehicle
print("\(vehicle.brand) \(vehicle.model)")
```

### Python

```python
client = GraphLinkClient.with_http(
    url="http://localhost:8080/graphql",
    ws_url="ws://localhost:8080/graphql",
)

res = await client.queries.get_vehicle(id="42")
print(res.get_vehicle.brand, res.get_vehicle.model)
```

### Go

```go
client, err := graphql.NewGraphLinkClientWithHttp(graphql.GraphLinkHttpOptions{
    URL:   "http://localhost:8080/graphql",
    WsURL: "ws://localhost:8080/graphql",
})
if err != nil {
    return err
}

res, err := client.Queries.GetVehicle(ctx, "42")
if err != nil {
    return err
}
fmt.Println(res.GetVehicle.Brand, res.GetVehicle.Model)
```

### Spring Boot (server mode)

Set `"mode": "server"` and GraphLink generates controllers, service interfaces, types, inputs, and enums:

```java
// Generated — implement this interface
public interface VehicleService {
    Vehicle getVehicle(String id);
    List<Vehicle> listVehicles();
    Vehicle addVehicle(AddVehicleInput input);
    Flux<Vehicle> vehicleAdded(); // subscriptions use Reactor Flux
}

// Generated — wires directly into Spring GraphQL
@Controller
public class VehicleServiceController {
    @QueryMapping
    public Vehicle getVehicle(@Argument String id) { return vehicleService.getVehicle(id); }
    // ...
}
```

Just implement the service interface — the routing is done.

### Express / Apollo (server mode)

Set `"mode": "server"` with an `"expressApollo"` block under `serverConfig` and GraphLink generates resolvers, typed service interfaces, and a ready-to-run entry point:

```typescript
// Generated — implement this interface
export interface VehicleService {
  getVehicle(id: string): Promise<Vehicle>;
  listVehicles(): Promise<Vehicle[]>;
  addVehicle(input: AddVehicleInput): Promise<Vehicle>;
  vehicleAdded(): AsyncIterable<Vehicle>; // subscriptions use async generators
}

// Generated — wires Express + Apollo Server + graphql-ws together
import { createServer } from './generated/index.js';

const httpServer = await createServer({
  vehicleService: new VehicleServiceImpl(),
});
httpServer.listen(4000);
```

`@glSkipOnServer(batch: true)` fields generate per-request DataLoaders automatically — same N+1-avoidance guarantee as the Spring targets, idiomatic to Node.

---

## Built-in Caching

Cache control lives in the schema, not scattered through your application code.

```graphql
type Query {
  getVehicle(id: ID!): Vehicle!         @glCache(ttl: "2m", tags: ["vehicles"])
  getUserProfile(id: ID!): UserProfile  @glCache(ttl: "1m", staleIfOffline: true)
}

type Mutation {
  addVehicle(input: AddVehicleInput!): Vehicle!  @glCacheInvalidate(tags: ["vehicles"])
  resetData: Boolean!                            @glCacheInvalidate(all: true)
}
```

Cache entries are keyed by operation name + variables — each unique argument combination is cached independently. The generated client handles all of it automatically. Bring your own persistent store by implementing `GraphLinkCacheStore`.

---

## REST operations

Serve some fields over plain HTTP/JSON from the same schema and the same generated client:

```graphql
extend type Query @glRestPrefix(path: "/products") {
  product(id: ID!): Product @glRest(path: "/{id}")
}
```

```dart
final product = await client.queries.product(id: 'p1');
```

The call looks like any GraphQL operation. Arguments get explicit roles (`@glRestPath`, `@glRestParam`, `@glRestHeader`, `@glRestBody`, `@glRestField`, `@glRestPart`), responses can be JSON, text, `Void` or a streamed `Download`, and `@glCache` works on REST operations. Available in Dart, Java, TypeScript, Kotlin, Swift, Python and Go. See [REST operations](https://graphlink.dev/rest-client.html) and [why support REST](https://graphlink.dev/why-rest.html): try GraphLink on the API you have, one client-side cache shared with GraphQL, and migrate to GraphQL one field at a time.

---

## How It Compares

| Feature | GraphLink | ferry (Dart) | Apollo (JS/Kotlin) | Manual |
|---|---|---|---|---|
| Runtime dependency | ✅ None | ❌ Yes | ❌ Yes | ✅ None |
| Languages from one schema | ✅ 7 clients | ➖ Dart only | ➖ One library per platform | ❌ Manual |
| Sends whole schema per request | ✅ No | ❌ Yes | ⚠️ Partial | ✅ No |
| Generics at Java call site | ✅ No | ➖ N/A | ❌ Yes | ❌ Yes |
| Server-side generation | ✅ Yes | ❌ No | ⚠️ Partial | ❌ Manual |
| Java client | ✅ Yes | ❌ No | ⚠️ Kotlin only | ❌ Manual |
| Cache directives in schema | ✅ Yes | ❌ No | ❌ No | ❌ No |
| Spring Boot controller gen (MVC) | ✅ Yes | ❌ No | ❌ No | ❌ Manual |
| Spring Boot controller gen (WebFlux) | ✅ Yes | ❌ No | ❌ No | ❌ Manual |

The competitor columns describe each project's documented approach and may be out of date. For the scope of other generators (Apollo Kotlin, GraphQL Code Generator, genqlient, ariadne-codegen, Netflix DGS) and for cases where another tool fits better, such as when you need a normalized client cache, see [How it compares](https://graphlink.dev/philosophy.html#how-it-compares).

---

## Documentation

Full documentation at **[graphlink.dev](https://graphlink.dev/)**

- [Getting Started](https://graphlink.dev/getting-started.html)
- [Supported Targets](https://graphlink.dev/targets.html)
- Clients: [Dart / Flutter](https://graphlink.dev/dart-client.html), [Java](https://graphlink.dev/java-client.html), [TypeScript](https://graphlink.dev/typescript-client.html), [Kotlin](https://graphlink.dev/kotlin-client.html), [Swift](https://graphlink.dev/swift-client.html), [Python](https://graphlink.dev/python-client.html), [Go](https://graphlink.dev/go-client.html)
- Servers: [Spring Boot](https://graphlink.dev/spring-server.html), [Express / Apollo](https://graphlink.dev/express-apollo.html)
- [Why Support REST](https://graphlink.dev/why-rest.html)
- [REST Operations](https://graphlink.dev/rest-client.html)
- [Custom Queries & Mutations](https://graphlink.dev/custom-queries.html)
- [Caching](https://graphlink.dev/caching.html)
- [Persisted Queries](https://graphlink.dev/persisted-queries.html)
- [Directives Reference](https://graphlink.dev/directives.html)
- [Configuration Reference](https://graphlink.dev/configuration.html)
- [For AI agents](https://graphlink.dev/ai-agents.html) and [llms.txt](https://graphlink.dev/llms.txt)

---

## License

MIT — see [LICENSE](LICENSE).

Issues and contributions welcome at [github.com/Oualitsen/graphlink](https://github.com/Oualitsen/graphlink).
