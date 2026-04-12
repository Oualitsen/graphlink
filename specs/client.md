# GraphLink — Client Generation Spec

Rules for generating client-side code from a GraphQL schema. Reference targets are Dart/Flutter and Java.

---

## Config options

### Common (Dart and Java)

| Key | Type | Default | Effect |
|---|---|---|---|
| `generateAllFieldsFragments` | bool | `false` | Generate an `_all_fields` fragment for every type |
| `nullableFieldsRequired` | bool | `false` | Require nullable fields in constructors |
| `autoGenerateQueries` | bool | `false` | Auto-generate query strings from the schema |
| `operationNameAsParameter` | bool | `false` | Pass operation name as a parameter to the adapter |
| `immutableInputFields` | bool | `true` | Generate input fields as `final` |
| `immutableTypeFields` | bool | `true` | Generate type fields as `final` |

### Dart-specific (`clientConfig.dart`)

| Key | Type | Default | Effect |
|---|---|---|---|
| `packageName` | string | — | Dart package name used in import paths |
| `autoGenerateQueriesDefaultAlias` | string | — | Default alias applied to auto-generated queries |
| `generateUiTypes` | bool | `false` | Generate Flutter widget classes for each type |
| `generateUiInputs` | bool | `false` | Generate Flutter form widgets for each input |
| `generateAdapters` | bool | `true` | Generate HTTP / WebSocket adapter files |
| `httpAdapter` | `http`\|`dio`\|`none` | `http` | Which HTTP adapter to generate |
| `appLocalizationsImport` | string | — | Import path for app localizations (used in UI widgets) |

### Java-specific (`clientConfig.java`)

| Key | Type | Default | Effect |
|---|---|---|---|
| `packageName` | string | required | Java package name |
| `inputAsRecord` | bool | `false` | Emit inputs as Java records |
| `typeAsRecord` | bool | `false` | Emit types as Java records |
| `wsAdapter` | `java11`\|`okhttp`\|`none` | `java11` | Which WebSocket adapter to generate |
| `jsonCodec` | `jackson`\|`gson`\|`none` | `jackson` | Which JSON codec adapter to generate |

---

## Schema constructs

### Types → classes

One class per non-internal type. Fields map directly to class fields.

- Nullable fields → nullable type (`String?` in Dart, `@Nullable String` / unboxed in Java)
- Fields annotated `@glSkipOnClient` are excluded.
- `immutableTypeFields: true` → fields are `final`.
- `typeAsRecord: true` (Java only) → emit as a Java `record`.
- JSON serialization methods (`fromJson` / `toJson`) are always generated.

### Inputs → classes

Same rules as types, with `immutableInputFields` and `inputAsRecord`.

- Inputs always get a builder pattern in Java.
- `@glMapsTo` → generates a `toTargetType()` conversion method.
- `@glMapField(to: "fieldName")` → maps a field to a differently-named field on the target type in the conversion method.

### Enums

Emitted as a Dart `enum` or Java `enum`. Values match the schema exactly.

### Interfaces / Unions

Projected types are generated per query projection, not per schema interface. Each unique projection shape produces its own class.

---

## Query strings

The client sends minimal query strings containing only the fields requested in the projection, not a full schema dump.

- `autoGenerateQueries: true` → query strings are generated automatically from the schema, requesting all non-skipped fields.
- `generateAllFieldsFragments: true` → an `_all_fields` fragment is generated for each type and reused in queries.

---

## Client class

A single `GraphLinkClient` class is generated, exposing three namespaces:

- `client.queries` — one typed method per `Query` field
- `client.mutations` — one typed method per `Mutation` field
- `client.subscriptions` — one typed method per `Subscription` field

Each method returns the fully-resolved response type. No generics or casting at the call site.

### Subscription return types

| Target | Return |
|---|---|
| Dart | `Stream<T>` |
| Java | `void` with a `GraphLinkSubscriptionListener<T>` callback parameter |

---

## Directives

### `@glSkipOnClient`

Applied to a field: the field is excluded from all client-generated classes and query strings.

### `@glSkipOnServer`

Applied to a type or field: included on the client, excluded on the server. Client generation is unaffected.

### `@glTypeName(name: "NewName")`

Applied to a type: the generated class uses `NewName` instead of the schema type name. Useful when the schema name conflicts with a language keyword or existing class.

### `@glCache(ttl: 120, tags: ["tag1"], staleIfOffline: false)`

Applied to a query: the generated client caches the response.

- `ttl` — cache lifetime in seconds
- `tags` — list of tag strings used for invalidation
- `staleIfOffline: true` — serve stale cached data when the network is unavailable instead of throwing

Cache entries are keyed by operation name + serialized variables. Each unique argument combination is cached independently.

### `@glCacheInvalidate(tags: ["tag1"], all: false)`

Applied to a mutation: on successful execution, the client evicts cached entries.

- `tags` — evict all cache entries matching any of these tags
- `all: true` — evict the entire cache

### `@glNoCache`

Applied to a query: explicitly disables caching even if a default cache policy is configured.

### `@glMapsTo(type: "TargetType")`

Applied to an input: generates a `toTargetType()` conversion method.

### `@glMapField(to: "targetFieldName")`

Applied to an input field: in the `toTargetType()` conversion method, this field is written to `targetFieldName` on the target instead of the same-named field.

### `@glUpload`

Applied to a scalar: the scalar is treated as a file upload.

- Dart → parameter type becomes `GLUpload`
- Java → parameter type becomes `GLUpload`

Mutations containing upload fields are sent as multipart requests. The adapter must implement `GraphLinkMultipartAdapter`.

### `@glDecorators(value: ["@JsonProperty(\"name\")"], applyOnClient: true)`

Applied to a type, field, or argument: adds the listed annotations/decorators to the generated client element.

### `@glEqualsHashcode(fields: ["id"])`

Applied to a type: generates `==` / `hashCode` (Dart) or `equals()` / `hashCode()` (Java) based on the listed fields.

### `@glExternal(glClass: "SomeClass", glImport: "com.example.SomeClass")`

Applied to a scalar: the scalar maps to an existing class. No class is generated; the import is injected where needed.
