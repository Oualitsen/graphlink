---
title: Directives Reference — GraphLink Docs
description: Complete reference for all GraphLink schema directives — @glCache, @glCacheInvalidate, @glMapsTo, @glMapField, @glSkipOnServer (with forward mappings), @glExternal, @glValidate, and more.
---

# Directives Reference

All GraphLink directives with arguments, placement, and examples.

## @glCache

**Target:** CLIENT · **Placement:** `FIELD_DEFINITION` on `Query` fields

Caches the result of a query field. The generated client checks the cache before making a network request and stores the result on a cache miss.

| Argument | Type | Required | Description |
|---|---|---|---|
| `ttl` | `Int!` | Yes | Time-to-live in seconds. |
| `tags` | `[String!]` | No | Tags to associate with this cache entry for group invalidation. |
| `staleIfOffline` | `Boolean` | No | When `true`, return the expired cached value if the network request fails. |

```graphql title="Example"
type Query {
  getVehicle(id: ID!): Vehicle! @glCache(ttl: 120, tags: ["vehicles"])
  getUserProfile(id: ID!): UserProfile @glCache(ttl: 60, tags: ["users"], staleIfOffline: true)
  getConfig: AppConfig! @glCache(ttl: 3600)
}
```

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

## @glSkipOnServer

**Target:** BOTH · **Placement:** `OBJECT`, `SCALAR`

Instructs GraphLink to skip generating a class for this type in server mode. If `mapTo` is provided, the generator substitutes the given class name wherever this type appears.

| Argument | Type | Description |
|---|---|---|
| `mapTo` | `String` | Optional. Fully-qualified class name to use in place of this type. |

```graphql title="Example"
# Don't generate a class — use Spring Data's Pageable from the framework
type Pageable @glSkipOnServer(mapTo: "org.springframework.data.domain.Pageable") {
  page: Int
  size: Int
  sort: String
}
```

**Forward mappings:** When `mapTo` is set, GraphLink automatically *forwards* fields that exist verbatim on the target type (same name and compatible structural type). These fields are resolved by Spring directly — no service method or `@SchemaMapping` is generated for them. Only fields absent from the target type, or explicitly annotated with `@glSkipOnServer`, still get full delegation.

## @glSkipOnClient

**Target:** BOTH · **Placement:** `OBJECT`, `INPUT_OBJECT`, `SCALAR`

Instructs GraphLink to skip generating a class for this type in client mode. Use this for server-side types that clients never need to instantiate directly.

```graphql title="Example"
# PageInfo is part of GraphQL responses but clients don't instantiate it
type PageInfo @glSkipOnClient {
  hasNextPage: Boolean!
  endCursor: String
}
```

## @glExternal

**Target:** BOTH · **Placement:** `SCALAR`, `OBJECT`

Maps a GraphQL scalar or type to an external class, optionally specifying the import path. Unlike `typeMappings` in the config (which works for all types globally), `@glExternal` is per-type and can specify an import statement.

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

## @glServiceName

**Target:** SERVER · **Placement:** `OBJECT`

Sets a custom name for the generated service interface associated with a type. By default, the service is named `{TypeName}Service`.

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

## @glArray — Removed in v4.4.0

!!! danger "@glArray has been removed"
    This directive is no longer supported. As of v4.4.0, all list fields are generated as `List<T>` in Java and Dart regardless of this annotation. Remove any `@glArray` usages from your schema before upgrading to v4.4.0+.

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
