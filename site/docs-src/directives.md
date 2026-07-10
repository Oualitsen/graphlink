---
title: Directives Reference — GraphLink Docs
description: Complete reference for all GraphLink schema directives — @glCache, @glCacheInvalidate, @glCaptureErrors, @glMapsTo, @glMapField, @glSkipOnServer (with forward mappings), @glExternal, @glValidate, @glServerLenient, @glInjectContext, @deprecated, and more.
---

# Directives Reference

All GraphLink directives with arguments, placement, and examples.

## Copy-paste declarations

Add this block to your schema file (or a dedicated `directives.graphql`) so your IDE and schema validators recognise every GraphLink directive:

```graphql title="directives.graphql"
# ── Caching ───────────────────────────────────────────────────────────────────

directive @glCache(
  ttl: String!
  tags: [String!]
  staleIfOffline: Boolean
) on QUERY | MUTATION | FIELD | FIELD_DEFINITION | OBJECT | INTERFACE | UNION | ENUM | INPUT_OBJECT | SCALAR | SCHEMA

directive @glCacheInvalidate(
  tags: [String!]
  all: Boolean
) on QUERY | MUTATION | FIELD | FIELD_DEFINITION | OBJECT | INTERFACE | UNION | ENUM | INPUT_OBJECT | SCALAR | SCHEMA

# ── Code generation control ───────────────────────────────────────────────────

directive @glSkipOnServer(mapTo: String, batch: Boolean) on OBJECT | SCALAR | FIELD_DEFINITION

directive @glSkipOnClient on OBJECT | INPUT_OBJECT | SCALAR | FIELD_DEFINITION

directive @glExternal(glClass: String!, glImport: String) on SCALAR | OBJECT

directive @glInternal on OBJECT

directive @glTypeName(name: String!) on OBJECT | INPUT_OBJECT | ENUM

# ── Server (Spring Boot) ──────────────────────────────────────────────────────

directive @glDecorators(value: [String!]!) on OBJECT | INPUT_OBJECT | FIELD_DEFINITION

directive @glServiceName(name: String!) on OBJECT | FIELD_DEFINITION

directive @glValidate on FIELD_DEFINITION

directive @glRepository(glType: String!, glIdType: String!) on OBJECT

# ── Equality ──────────────────────────────────────────────────────────────────

directive @glEqualsHashcode(fields: [String!]!) on OBJECT | INPUT_OBJECT

# ── Input mapping ─────────────────────────────────────────────────────────────

directive @glMapsTo(type: String!) on INPUT_OBJECT

directive @glMapField(to: String!) on FIELD_DEFINITION

# ── File upload ───────────────────────────────────────────────────────────────

directive @glUpload on SCALAR

# ── Cyclic expansion ──────────────────────────────────────────────────────────

directive @glExpand(depth: Int) on OBJECT

# ── Error capture ─────────────────────────────────────────────────────────────

directive @glCaptureErrors on FIELD_DEFINITION

# ── Strict server generation (v5.0.0+) ────────────────────────────────────────

directive @glServerLenient on OBJECT | INTERFACE

directive @glInjectContext on FIELD_DEFINITION
```

---

## @glCache

**Target:** CLIENT · **Placement:** `FIELD_DEFINITION` on `Query` fields

Caches the result of a query field. The generated client checks the cache before making a network request and stores the result on a cache miss.

| Argument | Type | Required | Description |
|---|---|---|---|
| `ttl` | `String!` | Yes | Time-to-live as a duration string (`"30s"`, `"4m"`, `"2h"`, `"1d"`) or a bare integer string (`"300"` = 300 seconds). |
| `tags` | `[String!]` | No | Tags to associate with this cache entry for group invalidation. |
| `staleIfOffline` | `Boolean` | No | When `true`, return the expired cached value if the network request fails. |

**TTL duration formats:**

| Format | Unit | Example | Seconds |
|--------|------|---------|---------|
| `"<n>s"` | seconds | `"90s"` | 90 |
| `"<n>m"` | minutes | `"4m"` | 240 |
| `"<n>h"` | hours | `"2h"` | 7200 |
| `"<n>d"` | days | `"1d"` | 86400 |
| `"<n>"` | seconds (bare) | `"300"` | 300 |

```graphql title="Example"
type Query {
  getVehicle(id: ID!): Vehicle! @glCache(ttl: "2m", tags: ["vehicles"])
  getUserProfile(id: ID!): UserProfile @glCache(ttl: "1m", tags: ["users"], staleIfOffline: true)
  getConfig: AppConfig! @glCache(ttl: "1h")
}
```

---

## @glCacheInvalidate

**Target:** CLIENT · **Placement:** `FIELD_DEFINITION` on `Mutation` fields

Invalidates cache entries after a successful mutation. Either specify `tags` to evict by tag, or set `all: true` to wipe the entire cache.

| Argument | Type | Description |
|---|---|---|
| `tags` | `[String!]` | Evict all entries tagged with any of these values. |
| `all` | `Boolean` | When `true`, evict the entire cache store. |

```graphql title="Example"
type Mutation {
  addVehicle(input: AddVehicleInput!): Vehicle! @glCacheInvalidate(tags: ["vehicles"])
  updatePerson(input: UpdatePersonInput!): Person! @glCacheInvalidate(tags: ["persons", "vehicles"])
  resetDatabase: Boolean! @glCacheInvalidate(all: true)
}
```

---

## @glCaptureErrors

**Target:** CLIENT · **Placement:** `FIELD_DEFINITION` on `Query` and `Mutation` fields

Changes the method contract so errors are returned inline instead of thrown. The generated method return type changes from `{OperationName}Response` to `{OperationName}FullResponse`. A separate `{OperationName}FullResponse` class is generated alongside the original response class (which is left unchanged). The caller inspects `response.errors` directly — the method never throws for GraphQL errors.

No arguments.

```graphql title="Example"
type Query {
  getUser(id: ID!): User! @glCaptureErrors
  listUsers: [User!]! @glCaptureErrors
}

type Mutation {
  createUser(input: CreateUserInput!): User! @glCaptureErrors
}
```

Generated wrapper class (Dart):

```dart title="Generated GetUserFullResponse"
class GetUserFullResponse {
  final GetUserResponse? data;
  final List<GraphLinkError>? errors;

  GetUserFullResponse({this.data, this.errors});
}
```

Generated wrapper interface (TypeScript):

```typescript title="Generated GetUserFullResponse"
export interface GetUserFullResponse {
  data?: GetUserResponse;
  errors?: GraphLinkError[];
}
```

Generated wrapper class (Java):

```java title="Generated GetUserFullResponse.java"
public class GetUserFullResponse {
    private final GetUserResponse data;       // nullable
    private final List<GraphLinkError> errors; // nullable
}
```

**Call-site comparison:**

| Without `@glCaptureErrors` | With `@glCaptureErrors` |
|---|---|
| `try { final user = await client.queries.getUser(id: id); } catch (e) { … }` | `final r = await client.queries.getUser(id: id); if (r.errors != null) { … }` |

**Caching interaction:** error responses are never cached. On a cache hit, `errors` is always `null`.

**Validation:** applying `@glCaptureErrors` to a subscription field is rejected at parse time with a `ParseException`.

**Global config alternative:** instead of annotating each field, set `captureErrors: true` in `clientConfig.dart` / `clientConfig.java` / `clientConfig.typescript` to apply the behaviour to every query and mutation automatically.

---

## @glServerLenient

**Target:** SERVER · **Placement:** `OBJECT`, `INTERFACE`

Since v5.0.0, server generation is **strict by default**: every generated type and interface enforces the schema's real nullability (a non-null field stays non-null in the generated getters/constructors/setters). `@glServerLenient` opts a specific type or interface back out of that, restoring the pre-v5.0.0 behavior where all of its own fields are generated as nullable — useful for legacy resolvers that can't guarantee every field is populated on every path.

No arguments.

```graphql title="Example"
# Every field on LegacyReport is generated as nullable, regardless of the schema's "!" markers
type LegacyReport @glServerLenient {
  id: ID!
  title: String!
  total: Float!
}
```

Because generated controllers serialize responses via `toJson()` to a `Map`, a `@glServerLenient` resolver can return a partially-populated object with un-fetched fields left `null` — enough for selection-driven partial fetches.

→ **[Full explanation of strict server generation](spring-server.md#strict-server-generation)**

---

## @glInjectContext

**Target:** SERVER · **Placement:** `FIELD_DEFINITION` on `Query`, `Mutation`, `Subscription` fields, or a `@glSkipOnServer` relation field

Injects the request **context** into that one resolver/service method so it can read per-request state (authenticated user, tenant, headers, etc.). The generated method gains the target's context parameter — Spring `GraphQLContext graphQLContext`, Apollo `context: GraphLinkContext`. Without it, the method has no context parameter.

No arguments. Equivalent to enabling the global `injectContext` config for just that field; the directive and the global flag are OR'd together.

```graphql title="Example"
type Query {
  # Only this resolver receives the request context
  me: User! @glInjectContext
  publicStats: Stats!
}
```

```java title="Generated UserService.java (Spring)"
User me(GraphQLContext graphQLContext);
Stats publicStats();
```

```typescript title="Generated UserService.ts (Apollo)"
me(context: GraphLinkContext): Promise<User>;
publicStats(): Promise<Stats>;
```

To inject context into **every** resolver instead, set `injectContext: true` in the server config (`serverConfig.spring`, `serverConfig.kotlinSpring`, or `serverConfig.expressApollo`).

---

## @glSkipOnServer

**Target:** SERVER · **Placement:** `OBJECT`, `SCALAR`, `FIELD_DEFINITION`

Excludes a type or field from server generation and generates `@SchemaMapping` or `@BatchMapping` to resolve it. Supports `mapTo` for substituting an existing class and `batch` for N+1-safe batch resolution.

→ **[Full reference with generated code examples](skip-directives.md)**

---

## @glSkipOnClient

**Target:** BOTH · **Placement:** `OBJECT`, `INPUT_OBJECT`, `SCALAR`, `FIELD_DEFINITION`

Enforces server-side access control at two levels. **Always**: generates a `@SchemaMapping` that throws `GraphQLException("Access denied")` — no client can read the field at runtime. **With `generateSchema: true`**: also strips the field from the schema Spring Boot serves, making it invisible in GraphiQL and rejected at validation before execution. Also excludes the type or field from all client-side code generation (Dart, Java, TypeScript).

→ **[Full reference including the server-side security guarantee](skip-directives.md)**

---

## @glExternal

**Target:** BOTH · **Placement:** `SCALAR`, `OBJECT`

Maps a GraphQL scalar or type to an external class, optionally specifying the import path. Unlike `typeMappings` in the config (which works for scalars globally), `@glExternal` is per-type and can specify an import statement so generated files get the correct import automatically.

| Argument | Type | Description |
|---|---|---|
| `glClass` | `String!` | The fully-qualified class name to use. |
| `glImport` | `String` | Optional import statement to add to generated files that reference this type. |

```graphql title="Example"
# Map the DateTime scalar to Java's OffsetDateTime
scalar DateTime @glExternal(
  glClass: "OffsetDateTime",
  glImport: "java.time.OffsetDateTime"
)

# Map the BigDecimal scalar to Java's BigDecimal
scalar BigDecimal @glExternal(
  glClass: "BigDecimal",
  glImport: "java.math.BigDecimal"
)
```

---

## @glTypeName

**Target:** CLIENT · **Placement:** `OBJECT`, `INPUT_OBJECT`, `ENUM`

Overrides the name of the generated class for a type. By default, GraphLink uses the GraphQL type name.

| Argument | Type | Description |
|---|---|---|
| `name` | `String!` | The class name to use in generated code. |

```graphql title="Example"
# GraphQL type is "GQLVehicle", but generated class will be named "Vehicle"
type GQLVehicle @glTypeName(name: "Vehicle") {
  id: ID!
  brand: String!
}
```

---

## @glDecorators

**Target:** SERVER · **Placement:** `OBJECT`, `INPUT_OBJECT`

Adds raw annotation strings to the generated class declaration. Useful for adding JPA annotations (`@Entity`, `@Table`), Lombok annotations, or any other annotation that belongs on the class.

| Argument | Type | Description |
|---|---|---|
| `value` | `[String!]!` | List of annotation strings to emit before the class declaration. |

```graphql title="Example"
type Vehicle @glDecorators(value: ["@Entity", "@Table(name = \"vehicles\")"]) {
  id: ID!
  brand: String!
  model: String!
}
```

Generated output:

```java title="Generated Vehicle.java"
@Entity
@Table(name = "vehicles")
public class Vehicle {
    // ...
}
```

---

## @glServiceName

**Target:** SERVER · **Placement:** `OBJECT`, `FIELD_DEFINITION`

Sets a custom name for the generated service interface associated with a type or operation. By default, the service is named `{TypeName}Service`.

| Argument | Type | Description |
|---|---|---|
| `name` | `String!` | The service interface name to generate. |

```graphql title="Example"
# Generates FleetManagementService instead of VehicleService
type Vehicle @glServiceName(name: "FleetManagementService") {
  id: ID!
  brand: String!
}
```

---

## @glEqualsHashcode

**Target:** BOTH · **Placement:** `OBJECT`, `INPUT_OBJECT`

Generates `equals()` and `hashCode()` methods on the produced class, based on the specified fields. In Dart, generates `==` and `hashCode` overrides. In Java, generates standard `equals`/`hashCode` based on the listed fields.

| Argument | Type | Description |
|---|---|---|
| `fields` | `[String!]!` | The field names to include in equality comparison. |

```graphql title="Example"
# Two Vehicles are equal if they have the same id
type Vehicle @glEqualsHashcode(fields: ["id"]) {
  id: ID!
  brand: String!
  model: String!
}

# Two AddVehicleInputs are equal if all fields match
input AddVehicleInput @glEqualsHashcode(fields: ["brand", "model", "year", "fuelType"]) {
  brand: String!
  model: String!
  year: Int!
  fuelType: FuelType!
}
```

---

## @glRepository

**Target:** SERVER · **Placement:** `OBJECT`

Generates a JPA `JpaRepository` interface for this type. Requires `generateRepositories: true` in the server config. The repository is named `{TypeName}Repository`.

| Argument | Type | Description |
|---|---|---|
| `glType` | `String!` | The entity class name. |
| `glIdType` | `String!` | The Java type of the ID field (e.g. `"String"`, `"Long"`, `"UUID"`). |

```graphql title="Example"
type Vehicle @glRepository(glType: "Vehicle", glIdType: "String") {
  id: ID!
  brand: String!
}
```

Generated output (when `generateRepositories: true`):

```java title="Generated VehicleRepository.java"
import org.springframework.data.jpa.repository.JpaRepository;

public interface VehicleRepository extends JpaRepository<Vehicle, String> {
}
```

---

## @glInternal

**Target:** BOTH · **Placement:** `OBJECT`

Marks a type as internal to the GraphLink runtime. Internal types are excluded from `_all_fields` fragment generation and from any UI widget generation. Use this for generated infrastructure types like error wrappers or pagination metadata that should not appear in user-facing code.

```graphql title="Example"
# This type will not get an _all_fields fragment and will be skipped by UI generators
type GraphLinkError @glInternal {
  message: String!
  locations: [GraphLinkErrorLocation]
  path: [String]
}
```

---

## @glValidate

**Target:** SERVER · **Placement:** `FIELD_DEFINITION` on `Mutation` fields

Generates a `validate{OperationName}()` method in the service interface. The generated controller calls this method before the main operation method. Throw any exception in the validate method to abort the mutation.

```graphql title="Example"
type Mutation {
  addVehicle(input: AddVehicleInput!): Vehicle! @glValidate
}
```

Generated service interface additions:

```java title="Generated VehicleService.java"
public interface VehicleService {
    // Called before addVehicle — throw to reject
    void validateAddVehicle(AddVehicleInput input);

    Vehicle addVehicle(AddVehicleInput input);
    // ...
}
```

---

## @glArray — Removed in v4.4.0

!!! danger "@glArray has been removed"
    This directive is no longer supported. As of v4.4.0, all list fields are generated as `List<T>` in Java and Dart regardless of this annotation. Remove any `@glArray` usages from your schema before upgrading to v4.4.0+.

---

## @glMapsTo

**Target:** BOTH · **Placement:** `INPUT_OBJECT`

Declares that a GraphQL input type maps to an existing class in the target language. GraphLink validates that the target class and all field mappings exist at generation time and emits a mapping constructor or method on the generated input class. Use `@glMapField` on individual fields to rename them during mapping.

| Argument | Type | Description |
|---|---|---|
| `type` | `String!` | The fully-qualified target class name to map to. |

```graphql title="Example"
# Map GraphQL input to an existing Java/Dart class
input UpdateVehicleInput @glMapsTo(type: "com.example.domain.UpdateVehicleCommand") {
  id: ID!
  brand: String!
  model: String!
  year: Int!
  # Rename during mapping — see @glMapField below
  fuelKind: FuelType! @glMapField(to: "fuelType")
}
```

GraphLink generates a `toMappedType()` method on the input class that constructs the target type from the input fields, applying any `@glMapField` renames in the process.

---

## @glMapField

**Target:** BOTH · **Placement:** `FIELD_DEFINITION` on `input` types annotated with `@glMapsTo`

Renames a field during the input-to-target mapping. The GraphQL field name is used in the schema and the generated input class; the `to` value is the field name on the target class.

| Argument | Type | Description |
|---|---|---|
| `to` | `String!` | The field name on the target mapped class. |

```graphql title="Example"
input UpdateVehicleInput @glMapsTo(type: "com.example.domain.UpdateVehicleCommand") {
  id: ID!
  brand: String!
  # GraphQL field is "fuelKind", target class field is "fuelType"
  fuelKind: FuelType! @glMapField(to: "fuelType")
}
```

GraphLink validates at generation time that the `to` field name exists on the target class. If it does not, generation fails with a clear error message.

---

## @glUpload

**Target:** BOTH · **Placement:** `SCALAR`

Marks a scalar as a file upload type. In Dart, the scalar is mapped to `GLUpload`. In Java MVC, mutation arguments become `MultipartFile` (or `List<MultipartFile>`). In WebFlux, they become `FilePart` (or `List<FilePart>`). The generated client adapter handles multipart encoding automatically.

```graphql title="Example"
scalar Upload @glUpload

type Mutation {
  uploadAvatar(userId: ID!, file: Upload!): User!
  uploadDocuments(files: [Upload!]!): [Document!]!
}
```

---

## @glExpand

**Target:** CLIENT · **Placement:** `OBJECT`

Controls how cyclic type references are handled during `_all_fields` fragment generation. When a type references itself (directly or through a chain), GraphLink cannot emit a recursive fragment spread — it would be invalid GraphQL. Instead, it inlines the cyclic type's fields up to `depth` levels deep.

| Argument | Type | Default | Description |
|---|---|---|---|
| `depth` | `Int` | `1` | Number of inline expansion levels for cyclic back-references. `0` omits the cyclic field entirely. |

```graphql title="Example — self-referential type"
type Employee @glExpand(depth: 2) {
  id: ID!
  name: String!
  manager: Employee
}
```

Generated fragment (depth 2 — two levels of inline expansion):

```graphql title="Generated _all_fields_Employee"
fragment _all_fields_Employee on Employee {
  id
  name
  manager {
    id
    name
    manager {
      id
      name
    }
  }
}
```

Without `@glExpand`, the default depth is `1` — one level of inline expansion. Use `depth: 0` to omit the cyclic field entirely from the fragment.

!!! note "Multi-type cycles"
    `@glExpand` also handles indirect cycles — for example `Customer → Order → Product → Supplier → Customer`. Each type in the cycle should declare `@glExpand` if a non-default depth is needed. The cycle is detected automatically; `@glExpand` only controls how deep the inline expansion goes before truncating.

!!! warning "Cyclic fields are always nullable (v5.0.0+)"
    Since v5.0.0, GraphLink runs SCC-based cycle detection by default on the generated *types themselves*, not just on `_all_fields` fragment expansion. Any field participating in a dependency cycle between types (e.g. `Employee.manager: Employee!` in a self-referential type) is generated as nullable in Dart/Java/Kotlin/TypeScript, even though the schema marks it non-null. Code that force-unwraps such a field (`!` in Dart/Kotlin, an unguarded getter call in Java/TS) may need updating after regenerating. `@glExpand` still controls only how deep `_all_fields` fragments inline the cycle — it does not opt a field back into non-null.

---

## @deprecated

**Target:** BOTH · **Placement:** `FIELD_DEFINITION`, `ENUM_VALUE` (standard GraphQL directive)

The spec-standard `@deprecated(reason: "...")` directive is picked up by GraphLink and translated into the target language's native deprecation annotation, carrying the reason through.

```graphql title="Example"
type Vehicle {
  id: ID!
  brand: String!
  # Deprecated field
  fuelKind: FuelType @deprecated(reason: "Use `fuelType` instead")
}

enum FuelType {
  GASOLINE
  DIESEL
  ELECTRIC
  LEGACY_HYBRID @deprecated(reason: "Use HYBRID instead")
}
```

| Target | Emitted annotation |
|---|---|
| Dart | `@Deprecated('Use \`fuelType\` instead')` |
| Java / Kotlin | `@Deprecated` with the reason in a preceding Javadoc/KDoc `@deprecated` line |
| TypeScript | `/** @deprecated Use \`fuelType\` instead */` JSDoc comment |

---

## _all_fields — the magic fragment

When `generateAllFieldsFragments: true` is set in the config, GraphLink generates a named fragment for every type in the schema. The fragment selects all fields of that type and is named `_all_fields_{TypeName}`:

```graphql title="Generated _all_fields_Vehicle fragment"
fragment _all_fields_Vehicle on Vehicle {
  id
  brand
  model
  year
  fuelType
  ownerId
}
```

You can reference these fragments in hand-written queries as a shorthand:

```graphql title="Using _all_fields in a query"
query getVehicle($id: ID!) {
  getVehicle(id: $id) {
    ... _all_fields_Vehicle
  }
}

# Or use the shorthand — resolves to the type-appropriate fragment
query getVehicle($id: ID!) {
  getVehicle(id: $id) {
    ... _all_fields
  }
}
```

The shorthand `... _all_fields` (without the type suffix) is resolved by GraphLink based on the return type of the field. It is equivalent to writing `... _all_fields_Vehicle` when the field returns `Vehicle`.

The `autoGenerateQueries: true` config option uses these fragments internally to generate query strings for every operation in the schema — you never write query strings by hand at all.

!!! warning "Types annotated with @glInternal are excluded"
    Internal types (annotated with `@glInternal`) do not get `_all_fields` fragments. This prevents GraphLink's own runtime types from being included in user queries.
