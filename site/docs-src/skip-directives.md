---
title: "@glSkipOnServer & @glSkipOnClient — GraphLink Docs"
description: "@glSkipOnServer and @glSkipOnClient — two-layer server-side access control, schema stripping, @SchemaMapping, @BatchMapping, mapTo, forward mappings, and the ID/object field-pair pattern for N+1-safe relationship loading."
---

# @glSkipOnServer & @glSkipOnClient

Two directives that give you fine-grained control over what GraphLink generates for each target.

| Directive | Target | Effect |
|---|---|---|
| `@glSkipOnServer` | Server (Spring Boot) | Excludes a type or field from server generation; generates `@SchemaMapping` / `@BatchMapping` to resolve it |
| `@glSkipOnClient` | Client (Dart, Java, TypeScript) | Strips the type or field from the generated schema — **no client can query it** |

Declaration (add to your schema or a dedicated `directives.graphql`):

```graphql
directive @glSkipOnServer(mapTo: String, batch: Boolean) on OBJECT | SCALAR | FIELD_DEFINITION
directive @glSkipOnClient on OBJECT | INPUT_OBJECT | SCALAR | FIELD_DEFINITION
```

---

## @glSkipOnClient is a server-side security guarantee

!!! danger "This is not just client code generation"
    `@glSkipOnClient` enforces access control **on the server**, at two levels depending on whether `generateSchema` is enabled. In both cases, the field cannot be read by any client — not GraphiQL, not Postman, not a rogue app.

GraphLink enforces `@glSkipOnClient` through two complementary mechanisms:

### Level 1 — Runtime rejection (always active)

Even without any schema generation, GraphLink generates a `@SchemaMapping` handler for every `@glSkipOnClient` field that immediately throws a `GraphQLException`:

```graphql title="Schema"
type User {
  id: ID!
  email: String!
  passwordHash: String! @glSkipOnClient
}
```

```java title="Generated VehicleServiceController.java (always generated)"
// Any client that queries passwordHash receives a GraphQL error — access denied.
@SchemaMapping(typeName="User", field="passwordHash")
public CompletableFuture<Object> passwordHash(User value) {
    throw new GraphQLException("Access denied to field 'User.passwordHash'");
}
```

Any query that includes `passwordHash` receives a GraphQL error in the response. The field is still visible via introspection at this level — but it is completely inaccessible at runtime.

### Level 2 — Schema stripping (with `generateSchema: true`)

When `generateSchema: true` is enabled, GraphLink also strips every `@glSkipOnClient` type, field, input, enum, and scalar from the schema file it writes to disk. Spring Boot serves this stripped schema as the authoritative GraphQL schema.

```graphql title="Your source schema"
type User {
  id: ID!
  email: String!
  passwordHash: String! @glSkipOnClient   # never exposed
  internalScore: Float! @glSkipOnClient   # never exposed
}
```

```graphql title="Generated schema served by Spring Boot (generateSchema: true)"
# passwordHash and internalScore are completely absent.
# Spring rejects any query referencing them at validation — before execution.
type User {
  id: ID!
  email: String!
}
```

With the stripped schema in place:

- The field does not appear in GraphiQL or any introspection result
- Spring Boot rejects any query referencing it at the **validation layer**, before execution even starts — `400 Bad Request`
- The `@SchemaMapping` exception handler from Level 1 is **not generated** for this field (it's not needed — the field doesn't exist in the schema)

### How to enable Level 2

Add `generateSchema: true` to your Spring Boot config:

```json title="glink.json"
{
  "mode": "server",
  "serverConfig": {
    "spring": {
      "basePackage": "com.example.generated",
      "generateSchema": true,
      "schemaTargetPath": "src/main/resources/graphql/schema.graphqls"
    }
  }
}
```

Run `glink` and the stripped schema lands at `src/main/resources/graphql/schema.graphqls`. Spring Boot picks it up automatically.

### Summary

| | `generateSchema: false` | `generateSchema: true` |
|---|---|---|
| Field visible in GraphiQL | Yes | **No** |
| Field accessible at runtime | **No** — throws `GraphQLException` | **No** — rejected at validation |
| Rejection layer | Execution (runtime error) | Validation (`400 Bad Request`) |
| `@SchemaMapping` generated | Yes — throws access denied | No — field stripped from schema |

!!! tip "Use both"
    Level 1 is always active and requires no configuration. Enable Level 2 (`generateSchema: true`) for the strongest guarantee — fields vanish from introspection entirely and are rejected before execution. Use both together in production.

---

---

## @glSkipOnServer

### Applied to a type — no `mapTo`

When placed on a type with no arguments, GraphLink skips generating a Java class for it. Any field on another type that returns this type is resolved via `@SchemaMapping`. The return type in service and controller signatures becomes `Object`.

```graphql title="Schema"
type Vehicle {
  id: ID!
  brand: String!
  stats: VehicleStats!
}

type VehicleStats @glSkipOnServer {
  totalMileage: Int!
  lastServiceDate: String!
}
```

=== "MVC"

    ```java title="Generated VehicleService.java"
    public interface VehicleService {
        Vehicle getVehicle(String id);
        Object stats(Vehicle vehicle);
    }
    ```

    ```java title="Generated VehicleServiceController.java"
    @Controller
    public class VehicleServiceController {

        @QueryMapping
        public CompletableFuture<Vehicle> getVehicle(@Argument String id) {
            return CompletableFuture.supplyAsync(() -> vehicleService.getVehicle(id));
        }

        // return type is Object — VehicleStats has no mapTo
        @SchemaMapping
        public CompletableFuture<Object> stats(Vehicle vehicle) {
            return CompletableFuture.supplyAsync(() -> vehicleService.stats(vehicle));
        }
    }
    ```

=== "WebFlux"

    ```java title="Generated VehicleService.java"
    public interface VehicleService {
        Mono<Vehicle> getVehicle(String id);
        Mono<Object> stats(Vehicle vehicle);
    }
    ```

    ```java title="Generated VehicleServiceController.java"
    @Controller
    public class VehicleServiceController {

        @QueryMapping
        public Mono<Vehicle> getVehicle(@Argument String id) {
            return vehicleService.getVehicle(id);
        }

        @SchemaMapping
        public Mono<Object> stats(Vehicle vehicle) {
            return vehicleService.stats(vehicle);
        }
    }
    ```

---

### Applied to a type — with `mapTo`

`mapTo` takes a **GraphQL type name defined in your schema**. GraphLink resolves it to the generated class for that type and uses it as the return type wherever the skipped type appears.

GraphLink also compares the fields of the two types. Fields that exist verbatim on the target type (same name and compatible type) are **auto-forwarded** — Spring resolves them directly from the mapped object, so no service method or `@SchemaMapping` is generated for them. Only fields absent from the target type get full delegation.

```graphql title="Schema"
type Vehicle {
  id: ID!
  brand: String!
  model: String!
}

type Query {
  searchVehicles(query: String!): [VehicleCard!]!
}

# Client-facing view model. On the server, resolve as a regular Vehicle —
# no VehicleCard class is generated.
type VehicleCard @glSkipOnServer(mapTo: "Vehicle") {
  id: ID!        # same field on Vehicle → auto-forwarded
  brand: String! # same field on Vehicle → auto-forwarded
  model: String! # same field on Vehicle → auto-forwarded
  displayLabel: String! # NOT on Vehicle → @SchemaMapping + service method
}
```

=== "MVC"

    ```java title="Generated VehicleService.java"
    public interface VehicleService {
        // returns Vehicle, not VehicleCard — no VehicleCard class is generated
        List<Vehicle> searchVehicles(String query);
        String displayLabel(Vehicle vehicle);
    }
    ```

    ```java title="Generated VehicleServiceController.java"
    @Controller
    public class VehicleServiceController {

        @QueryMapping
        public CompletableFuture<List<Vehicle>> searchVehicles(@Argument String query) {
            return CompletableFuture.supplyAsync(() -> vehicleService.searchVehicles(query));
        }

        // id, brand, model are auto-forwarded — Spring calls vehicle.getId() etc. directly.

        @SchemaMapping
        public CompletableFuture<String> displayLabel(Vehicle vehicle) {
            return CompletableFuture.supplyAsync(() -> vehicleService.displayLabel(vehicle));
        }
    }
    ```

=== "WebFlux"

    ```java title="Generated VehicleService.java"
    public interface VehicleService {
        Flux<Vehicle> searchVehicles(String query);
        Mono<String> displayLabel(Vehicle vehicle);
    }
    ```

    ```java title="Generated VehicleServiceController.java"
    @Controller
    public class VehicleServiceController {

        @QueryMapping
        public Flux<Vehicle> searchVehicles(@Argument String query) {
            return vehicleService.searchVehicles(query);
        }

        @SchemaMapping
        public Mono<String> displayLabel(Vehicle vehicle) {
            return vehicleService.displayLabel(vehicle);
        }
    }
    ```

---

### Applied to a type — with `batch: true`

`batch: true` swaps `@SchemaMapping` for `@BatchMapping`. The controller receives a list of parent objects and returns a map, eliminating N+1 queries when the field is requested for many parents at once.

```graphql title="Schema"
type Vehicle {
  id: ID!
  brand: String!
  stats: VehicleStats! @glSkipOnServer(batch: true)
}

type VehicleStats @glSkipOnServer {
  totalMileage: Int!
  lastServiceDate: String!
}
```

=== "MVC"

    ```java title="Generated VehicleService.java"
    public interface VehicleService {
        Vehicle getVehicle(String id);
        Map<Vehicle, Object> stats(List<Vehicle> vehicles);
    }
    ```

    ```java title="Generated VehicleServiceController.java"
    @BatchMapping
    public CompletableFuture<Map<Vehicle, Object>> stats(List<Vehicle> vehicles) {
        return CompletableFuture.supplyAsync(() -> vehicleService.stats(vehicles));
    }
    ```

=== "WebFlux"

    ```java title="Generated VehicleService.java"
    public interface VehicleService {
        Mono<Vehicle> getVehicle(String id);
        Flux<Object> stats(List<Vehicle> vehicles);
    }
    ```

    ```java title="Generated VehicleServiceController.java"
    @BatchMapping
    public Flux<Object> stats(List<Vehicle> vehicles) {
        return vehicleService.stats(vehicles);
    }
    ```

!!! tip "Combine `mapTo` with `batch: true`"
    You can use both together: `@glSkipOnServer(mapTo: "Vehicle", batch: true)` generates a `@BatchMapping` and uses the `Vehicle` generated class as the value type in the map.

---

### Applied to a field

When placed on a **field** of a non-root type (not on `Query`, `Mutation`, or `Subscription`), the field is excluded from the generated Java class and a `@SchemaMapping` is generated to resolve it. This is the correct way to declare computed fields or fields with arguments.

```graphql title="Schema"
type Vehicle {
  id: ID!
  brand: String!
  model: String!
  # Computed field — not stored, resolved server-side
  displayName: String! @glSkipOnServer
  # Field with arguments — must be marked so @SchemaMapping is generated
  similarVehicles(limit: Int = 5): [Vehicle!]! @glSkipOnServer
}
```

```java title="Generated Vehicle.java"
public class Vehicle {
    private final String id;
    private final String brand;
    private final String model;
    // displayName and similarVehicles are absent
}
```

=== "MVC"

    ```java title="Generated VehicleService.java"
    public interface VehicleService {
        Vehicle getVehicle(String id);
        String displayName(Vehicle vehicle);
        List<Vehicle> similarVehicles(Vehicle vehicle, Integer limit);
    }
    ```

    ```java title="Generated VehicleServiceController.java"
    @SchemaMapping
    public CompletableFuture<String> displayName(Vehicle vehicle) {
        return CompletableFuture.supplyAsync(() -> vehicleService.displayName(vehicle));
    }

    @SchemaMapping
    public CompletableFuture<List<Vehicle>> similarVehicles(
            Vehicle vehicle, @Argument Integer limit) {
        return CompletableFuture.supplyAsync(
                () -> vehicleService.similarVehicles(vehicle, limit));
    }
    ```

=== "WebFlux"

    ```java title="Generated VehicleService.java"
    public interface VehicleService {
        Mono<Vehicle> getVehicle(String id);
        Mono<String> displayName(Vehicle vehicle);
        Flux<Vehicle> similarVehicles(Vehicle vehicle, Integer limit);
    }
    ```

    ```java title="Generated VehicleServiceController.java"
    @SchemaMapping
    public Mono<String> displayName(Vehicle vehicle) {
        return vehicleService.displayName(vehicle);
    }

    @SchemaMapping
    public Flux<Vehicle> similarVehicles(Vehicle vehicle, @Argument Integer limit) {
        return vehicleService.similarVehicles(vehicle, limit);
    }
    ```

---

## @glSkipOnClient

Excludes a type or field from the generated schema and from client-side code generation. When `generateSchema: true` is set, the annotated type or field is **completely absent from the schema Spring Boot serves** — no client can request it. See the [security guarantee](#glskiponclient-is-a-server-side-security-guarantee) section above for details.

### Applied to a type

No class is generated. References to this type in queries are treated as opaque.

```graphql title="Schema"
# The server sends PageInfo but the client never instantiates it directly
type PageInfo @glSkipOnClient {
  hasNextPage: Boolean!
  endCursor: String
  startCursor: String
}

type VehicleConnection {
  nodes: [Vehicle!]!
  pageInfo: PageInfo!
}
```

```dart title="Generated VehicleConnection (Dart)"
class VehicleConnection {
  final List<Vehicle> nodes;
  // pageInfo is absent — PageInfo has no generated class
}
```

### Applied to a field

The field is excluded from the generated class. Use this for server-only fields — passwords, internal IDs, audit metadata — that should never reach the client.

```graphql title="Schema"
type User {
  id: ID!
  email: String!
  passwordHash: String! @glSkipOnClient   # never sent to clients
  createdAt: String!    @glSkipOnClient   # internal audit field
}
```

=== "Dart"

    ```dart title="Generated User (Dart)"
    class User {
      final String id;
      final String email;
      // passwordHash and createdAt are absent
    }
    ```

=== "Java client"

    ```java title="Generated User.java"
    public class User {
        private final String id;
        private final String email;
        // passwordHash and createdAt are absent
    }
    ```

=== "TypeScript"

    ```typescript title="Generated User (TypeScript)"
    export interface User {
      readonly id: string;
      readonly email: string;
      // passwordHash and createdAt are absent
    }
    ```

### Interaction with `@glMapsTo`

When a field is `@glSkipOnClient`, it is also excluded from any `@glMapsTo` mapping methods. GraphLink will not reference it in `toXxx()` or `fromXxx()` constructors, preventing broken type references in generated client code.

```graphql title="Schema"
input UpdateUserInput @glMapsTo(type: "UpdateUserCommand") {
  id: ID!
  email: String!
  internalFlag: Boolean! @glSkipOnClient  # excluded from client mapping
}
```

---

## Combining both directives on different fields

`@glSkipOnServer` and `@glSkipOnClient` are most often paired on **different fields of the same type** — not on the same whole type. This is the standard pattern for modelling a relationship where the server stores a raw foreign key but the client needs the resolved object.

```graphql title="Schema"
type Agency {
  id: ID!
  name: String!
  # Server stores this ID in the database — the client never needs it
  cashierId: ID! @glSkipOnClient
  # Server resolves this via @BatchMapping — the client fetches it
  cashier: Cashier @glSkipOnServer(batch: true)
}
```

- `cashierId` is `@glSkipOnClient`: the raw foreign key used for persistence. Invisible to the client — not generated in Dart/Java/TypeScript, and protected server-side by the access-denied `@SchemaMapping`.
- `cashier` is `@glSkipOnServer(batch: true)`: a resolved object the server produces via `@BatchMapping` using the stored `cashierId`. Not stored in the database.

Generated output:

```java title="Generated Agency.java (server)"
public class Agency {
    private String id;
    private String name;
    private String cashierId; // present on server — used for DB lookups
    // cashier is absent — resolved via @BatchMapping
}
```

```java title="Generated AgencyServiceController.java"
@BatchMapping(typeName="Agency", field="cashier")
public CompletableFuture<Map<Agency, Cashier>> cashier(List<Agency> agencies) {
    return CompletableFuture.supplyAsync(() -> agencyService.cashier(agencies));
}
// cashierId: access-denied @SchemaMapping generated (or stripped from schema if generateSchema: true)
```

```dart title="Generated Agency (Dart client)"
class Agency {
  final String id;
  final String name;
  final Cashier cashier; // present on client — typed object
  // cashierId is absent — @glSkipOnClient
}
```

This pattern scales naturally for any number of relationships:

```graphql title="Real-world example — lot movement tracking"
type LotMovement {
  id: ID!
  quantity: Int!

  lotId: ID!             @glSkipOnClient
  lot: Lot               @glSkipOnServer(batch: true)

  fromLocationId: ID     @glSkipOnClient
  fromLocation: Location @glSkipOnServer(batch: true)

  toLocationId: ID       @glSkipOnClient
  toLocation: Location   @glSkipOnServer(batch: true)
}
```

The client sees `lot`, `fromLocation`, and `toLocation` as fully typed objects. The server stores and works with the raw IDs, resolving the objects in batch to avoid N+1 queries. Neither side is aware of the other's representation — the schema is the only contract between them.
