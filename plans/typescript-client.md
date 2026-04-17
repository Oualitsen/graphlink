# TypeScript Client Generation

## Philosophy

Same architecture as Dart: one `.graphql` schema → fully typed client, zero runtime dependency.
The adapter is a plain function — HTTP client agnostic.

TypeScript's structural typing removes the need for `fromJson`/`toJson` on types and inputs.
The server returns JSON whose shape already matches the generated interfaces — a plain cast is sufficient.

---

## Type Mappings

### Scalars

| GraphQL | TypeScript |
|---|---|
| `String` | `string` |
| `Int` | `number` |
| `Float` | `number` |
| `Boolean` | `boolean` |
| `ID` | `string` |
| custom scalar | configurable via `typeMappings` |

### Nullability

`String!` → `string`
`String` → `string | null`

### Lists

`[String!]!` → `string[]`
`[String!]` → `string[] | null`
`[String]!` → `(string | null)[]`

---

## Generated Constructs

### Enum → TypeScript string enum

```graphql
enum FuelType { GASOLINE DIESEL ELECTRIC }
```

```typescript
export enum FuelType {
  GASOLINE = 'GASOLINE',
  DIESEL = 'DIESEL',
  ELECTRIC = 'ELECTRIC',
}
```

No `toJson`/`fromJson` — the enum value IS the wire value. `FuelType.GASOLINE` serializes
to `"GASOLINE"` in JSON automatically. Same usage pattern as Dart and Java.

---

### GraphQL `type` → TypeScript `interface`

```graphql
type Vehicle {
  id: ID!
  brand: String!
  year: Int!
  fuelType: FuelType!
  owner: Person
}
```

```typescript
export interface Vehicle {
  id: string;
  brand: string;
  year: number;
  fuelType: FuelType;
  owner: Person | null;
}
```

No constructor, no `fromJson`, no `toJson`. Structural typing handles the rest.
`readonly` fields controlled by `immutableTypeFields` config flag (default `true`).

---

### GraphQL `interface` → TypeScript discriminated union

```graphql
interface Animal {
  id: ID!
  name: String!
}
type Dog implements Animal { id: ID! name: String! breed: String! }
type Cat implements Animal { id: ID! name: String! indoor: Boolean! }
```

```typescript
export interface Dog { __typename: 'Dog'; id: string; name: string; breed: string; }
export interface Cat { __typename: 'Cat'; id: string; name: string; indoor: boolean; }
export type Animal = Dog | Cat;
```

`__typename` on each implementing type is the discriminant. The server must include it — GraphLink
generates query strings that request `__typename` automatically on union/interface fields.

---

### GraphQL `input` → TypeScript `interface`

```graphql
input AddVehicleInput {
  brand: String!
  model: String!
  year: Int!
  fuelType: FuelType!
  note: String
}
```

```typescript
export interface AddVehicleInput {
  brand: string;
  model: string;
  year: number;
  fuelType: FuelType;
  note?: string | null;
}
```

Nullable fields use optional syntax (`field?: T | null`) when `optionalNullableInputFields: true` (default).

---

## Client

### Adapter — HTTP agnostic

```typescript
// User provides this — works with fetch, axios, ky, got, anything
type GraphLinkAdapter = (payload: string) => Promise<string>;
```

Same philosophy as Dart. No dependency on any HTTP library.

### WebSocket adapter — for subscriptions

```typescript
export interface GraphLinkWsAdapter {
  connect(): Promise<void>;
  send(message: string): Promise<void>;
  onMessage: AsyncIterable<string>;
  close(): Promise<void>;
  connectionInitPayload?(): Promise<Record<string, unknown> | null>;
  onReconnect?: AsyncIterable<void>;
}
```

A default implementation using the browser `WebSocket` API is generated alongside (opt-in via config).

### Subscriptions — AsyncGenerator

```typescript
async *vehicleAdded(): AsyncGenerator<VehicleAddedResponse> { ... }
```

Zero runtime dependencies. Works in browser, Node.js, React Native.

### Generated client shape

```typescript
const client = new GraphLinkClient({
  adapter: (payload) => fetch('/graphql', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: payload,
  }).then(r => r.text()),
});

// Query — fully typed
const res = await client.queries.getVehicle({ id: '42' });
console.log(res.getVehicle.brand);

// Mutation
await client.mutations.addVehicle({
  input: { brand: 'Toyota', model: 'Camry', year: 2023, fuelType: FuelType.GASOLINE }
});

// Subscription
for await (const event of client.subscriptions.vehicleAdded()) {
  console.log(event.vehicleAdded.brand);
}
```

---

## Caching

Full port of the Dart cache system:
- TTL-based expiry
- Tag-based invalidation (`@glCache`, `@glCacheInvalidate`)
- `staleIfOffline` fallback
- Partial query execution (only uncached resolvers hit the network)
- FNV-1a cache key hash (same algorithm as Dart for consistency)

```typescript
export interface GraphLinkCacheStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  invalidate(key: string): Promise<void>;
  invalidateAll(): Promise<void>;
}
```

Default `InMemoryGraphLinkCacheStore` generated. User can supply a custom implementation
(localStorage, IndexedDB, Redis, etc.).

---

## Output structure

```
generated/
  types/          ← GraphQL types (one file per type)
  interfaces/     ← GraphQL interfaces (discriminated unions)
  inputs/         ← GraphQL inputs
  enums/          ← string unions + const objects
  client/
    graph_link_client.ts
    graph_link_ws_adapter.ts    ← default WS adapter (generated when subscriptions exist)
  index.ts        ← barrel re-exports
```

---

## Config

```json
{
  "clientConfig": {
    "typescript": {
      "generateAllFieldsFragments": true,
      "autoGenerateQueries": true,
      "immutableTypeFields": true,
      "optionalNullableInputFields": true,
      "generateDefaultWsAdapter": true
    }
  }
}
```

---

## What is NOT in v1

| Feature | Notes |
|---|---|
| `@glMapsTo` / `@glMapField` | No structural benefit — TS structural typing handles mapping naturally |
| File upload (`@glUpload`) | v2 |
| CommonJS output | ESM only in v1 |
| React hooks (`useQuery`, `useMutation`) | Thin wrapper, separate package, v2 |

---

## New files

| File | Role |
|---|---|
| `lib/src/serializers/typescript_serializer.dart` | Types, inputs, enums, interfaces generation |
| `lib/src/typescript_code_gen_utils.dart` | TS syntax helpers (interface, type alias, const object, async function, AsyncGenerator) |
| `lib/src/serializers/client_serializers/typescript_client_serializer.dart` | Client, queries, mutations, subscriptions generation |
| `lib/src/serializers/client_serializers/typescript_client_constants.dart` | TS template strings (cache infra, WS adapter, error types) |
| `lib/src/config.dart` | Add `TypeScriptClientConfig` + `typescript` field on `ClientConfig`; relax assert |
| `lib/src/main.dart` | Dispatch when `clientConfig.typescript != null` |

---

## Config changes

`ClientConfig` gets a `typescript` field and the assert relaxes to accept any one of dart/java/typescript:

```dart
class ClientConfig {
  final DartClientConfig? dart;
  final JavaClientConfig? java;
  final TypeScriptClientConfig? typescript;
  // assert: at least one is non-null
}

class TypeScriptClientConfig {
  final bool generateAllFieldsFragments;
  final bool autoGenerateQueries;
  final bool immutableTypeFields;         // default true
  final bool optionalNullableInputFields; // default true — nullable input fields use `field?: T | null`
  final bool generateDefaultWsAdapter;   // default true — emit default browser WS adapter
  final bool operationNameAsParameter;   // default false
}
```

---

## Build order

| Step | What |
|---|---|
| 1 | `TypeScriptClientConfig` in `config.dart` + relax `ClientConfig` assert |
| 2 | `TypeScriptCodeGenUtils` — interface, type alias, const object, async function, AsyncGenerator |
| 3 | `TypeScriptSerializer` — enums, inputs, types, GraphQL interfaces |
| 4 | `typescript_client_constants.dart` — cache infra, WS adapter, error class template strings |
| 5 | `TypeScriptClientSerializer` — queries, mutations, subscriptions, GraphLinkClient |
| 6 | Wire up dispatch in `main.dart` |
| 7 | Integration test: sample schema → generate → `tsc --noEmit` passes |
