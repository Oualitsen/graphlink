![GraphLink](assets/graphlink.png)

# GraphLink

> Write your GraphQL schema once. Get fully typed Dart/Flutter code — queries, mutations, subscriptions, UI input widgets — generated in milliseconds. No boilerplate. No drift.

[![pub.dev](https://img.shields.io/pub/v/graphlink?label=pub.dev)](https://pub.dev/packages/graphlink)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub Releases](https://img.shields.io/github/v/release/Oualitsen/graphlink)](https://github.com/Oualitsen/graphlink/releases/latest)

---

## What you get

Define a GraphQL schema and GraphLink generates:

- Fully typed query, mutation, and subscription methods — no casting, no generics
- JSON serialization — ready to use, nothing to wire up
- Schema-driven cache control — declare TTL and invalidation in the schema, the generated client handles the rest
- Flutter UI input widgets — generated directly from your `input` types
- Zero runtime dependency — delete GraphLink tomorrow, everything still compiles

---

## Installation

### Recommended — `glink` CLI (fastest)

The CLI compiles to a native binary. No Dart VM overhead — regenerates in milliseconds even on large schemas.

```bash
# macOS (ARM)
curl -fsSL https://github.com/Oualitsen/graphlink/releases/latest/download/glink-macos-arm64 -o glink
chmod +x glink && sudo mv glink /usr/local/bin/glink

# macOS (x64)
curl -fsSL https://github.com/Oualitsen/graphlink/releases/latest/download/glink-macos-x64 -o glink
chmod +x glink && sudo mv glink /usr/local/bin/glink

# Linux (x64)
curl -fsSL https://github.com/Oualitsen/graphlink/releases/latest/download/glink-linux-x64 -o glink
chmod +x glink && sudo mv glink /usr/local/bin/glink
```

→ [All releases](https://github.com/Oualitsen/graphlink/releases/latest) — also `glink-linux-arm64`, `glink-windows-x64.exe`

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
  getVehicle(id: ID!): Vehicle!
  listVehicles: [Vehicle!]!
}

type Mutation {
  addVehicle(input: AddVehicleInput!): Vehicle!
}
```

### 2. Configure

`glink.json` in your project root:

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
glink              # auto-discovers glink.json / glink.yaml / glink.yml
glink -w           # watch mode — regenerate on every save
```

### 4. Use it

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
await client.mutations.addVehicle(
  input: AddVehicleInput(brand: 'Toyota', model: 'Camry', year: 2023, fuelType: FuelType.GASOLINE),
);

// Subscription
client.subscriptions.vehicleAdded().listen((e) => print(e.vehicleAdded.brand));
```

---

## Schema-driven caching

Cache control lives in your schema — not scattered through your application code. Declare it once, the generated client handles TTL, tag-based invalidation, and offline fallback automatically.

```graphql
type Query {
  # Cache for 2 minutes, tagged "vehicles"
  getVehicle(id: ID!): Vehicle!      @glCache(ttl: "2m", tags: ["vehicles"])

  # Serve stale data when offline instead of throwing
  getUserProfile(id: ID!): UserProfile  @glCache(ttl: "1m", staleIfOffline: true)
}

type Mutation {
  # Automatically evicts all "vehicles" cache entries on success
  addVehicle(input: AddVehicleInput!): Vehicle!  @glCacheInvalidate(tags: ["vehicles"])

  # Wipe everything
  resetData: Boolean!  @glCacheInvalidate(all: true)
}
```

No cache code to write. Cache entries are keyed by operation name + variables — each unique argument combination is cached independently. Bring your own persistent store by implementing `GraphLinkCacheStore`.

---

## Flutter UI widgets

GraphLink generates ready-to-use `InputFormWidget` classes directly from your `input` types. Drop them into any Flutter form — validation, state management, and serialization included.

```dart
AddVehicleInputFormWidget(
  onChanged: (value) => setState(() => _input = value),
)
```

---

## Subscriptions

```dart
client.subscriptions.vehicleAdded().listen((event) {
  print(event.vehicleAdded.brand);
});
```

Reconnection, error handling, and typed payloads are all generated.

---

## Multi-language support

GraphLink also generates Java, Kotlin, TypeScript, and Spring Boot server code from the same schema. See the [full documentation on GitHub](https://github.com/Oualitsen/graphlink) for setup and examples.

---

## Documentation

Full documentation at **[graphlink.dev](https://graphlink.dev/docs/index.html)**

- [Getting Started](https://graphlink.dev/docs/getting-started.html)
- [Dart / Flutter Client](https://graphlink.dev/docs/dart-client.html)
- [Caching](https://graphlink.dev/docs/caching.html)
- [Directives Reference](https://graphlink.dev/docs/directives.html)
- [Configuration Reference](https://graphlink.dev/docs/configuration.html)

---

## License

MIT — see [LICENSE](LICENSE).

Issues and contributions welcome at [github.com/Oualitsen/graphlink](https://github.com/Oualitsen/graphlink).
