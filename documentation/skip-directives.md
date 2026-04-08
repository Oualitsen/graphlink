# @glSkipOnClient and @glSkipOnServer

These two directives control which parts of your schema are generated for each target. They are the primary mechanism for managing the boundary between client and server code when a single `.graphql` file drives both.

---

## Overview

| Directive | Effect |
|---|---|
| `@glSkipOnClient` | The annotated element is **omitted from client code** (Dart, Flutter, Java client) |
| `@glSkipOnServer` | The annotated element is **omitted from server code** (Spring Boot) |

Neither directive affects the other target. A field marked `@glSkipOnClient` is still fully generated on the server, and vice versa.

---

## Where Each Directive Can Appear

| Location | `@glSkipOnClient` | `@glSkipOnServer` |
|---|---|---|
| Type definition | Yes | Yes (+ optional `mapTo`, `batch`) |
| Interface definition | Yes | Yes |
| Enum definition | Yes | Yes |
| Input type definition | Yes | Yes (no arguments allowed) |
| Type field | Yes | Yes (optional `batch`, no `mapTo`) |
| **Input field** | **No — error** | **No — error** |

---

## @glSkipOnClient

### Skipping a type

The entire type is excluded from client code generation. Use this for types that only exist on the server — internal domain objects, JPA entities, etc.

```graphql
# Generated on the server, invisible to the client
type AuditLog @glSkipOnClient {
  id: ID!
  action: String!
  performedBy: String!
  timestamp: String!
}
```

### Skipping an enum

```graphql
enum InternalStatus @glSkipOnClient {
  PENDING_REVIEW
  FLAGGED
  CLEARED
}
```

### Skipping an input

```graphql
# The server may declare this input internally; the client never sees it
input ServerPatchInput @glSkipOnClient {
  id: ID!
  patch: String!
}
```

### Skipping a field on a type

The field is omitted from the client's generated class. On the Spring Boot server, GraphLink generates a `@SchemaMapping` that **forbids** the client from requesting it, returning an error if it does.

```graphql
type User {
  id: ID!
  name: String!
  password: String! @glSkipOnClient   # never sent to the client
}
```

**Client generates:**
```dart
class User {
  final String id;
  final String name;
  // password is absent
}
```

**Server generates a forbidden mapping:**
```java
// GraphLink generates this automatically — accessing password throws
@SchemaMapping
public String password(User user) {
  throw new UnsupportedOperationException("Field 'password' is not accessible");
}
```

### Error: @glSkipOnClient on an input field

Input fields define a contract between client and server. Skipping a single field breaks that contract because one side would have a field the other does not.

```graphql
# ERROR — @glSkipOnClient is not allowed on an input field
input CreateUserInput {
  name: String!
  internalNote: String @glSkipOnClient   # throws ParseException
}
```

Apply the directive to the input type itself instead:

```graphql
# Correct — the whole input is skipped on the client
input CreateUserInput @glSkipOnClient {
  name: String!
  internalNote: String
}
```

---

## @glSkipOnServer

### Arguments

| Argument | Applies to | Description |
|---|---|---|
| `mapTo: String` | Type definitions only | Maps the client type to an existing server type for schema mapping generation |
| `batch: Boolean` | Type definitions, type fields | Controls whether `@BatchMapping` (`true`, default) or `@SchemaMapping` (`false`) is generated |

### Skipping a type (no mapTo)

The type is not generated on the server at all. Fields of other types that reference this type must also be marked `@glSkipOnServer` to make the intent explicit.

```graphql
type CarInfo @glSkipOnServer {
  brand: String!
  model: String!
}

type Person {
  id: ID!
  name: String!
  carInfo: CarInfo @glSkipOnServer   # field must mirror the type's skip
}
```

The server generates no class for `CarInfo`. The `carInfo` field on `Person` generates a `@BatchMapping` that the service implementation must provide.

### Skipping a type with mapTo

Use `mapTo` when a client-facing type does not exist on the server verbatim, but an equivalent server type does. GraphLink replaces the client type with the server type in the generated schema mappings.

```graphql
type Car {
  id: ID!
  brand: String!
  model: String!
}

# Client sees CarInfo; server maps it to Car
type CarInfo @glSkipOnServer(mapTo: "Car") {
  id: ID!
  brand: String!
  model: String!
}

type Person {
  id: ID!
  name: String!
  carInfo: CarInfo @glSkipOnServer   # generates @BatchMapping returning Car
}
```

**What GraphLink generates on the server:**

```java
// Service interface — receives and returns the server type
public interface PersonSchemaMappingsService {
  List<Car> carInfo(List<Person> persons);
}

// Controller — Spring wires the @BatchMapping
@Controller
public class PersonSchemaMappingsController {
  @BatchMapping
  public List<Car> carInfo(List<Person> persons) {
    return service.carInfo(persons);
  }
}
```

### Skipping a field

When only a specific field needs server-side resolution (not the whole type), annotate the field directly.

```graphql
type User {
  id: ID!
  name: String!
  cars: [Car!]! @glSkipOnServer(batch: true)   # resolved via @BatchMapping
}
```

**Server generates:**

```java
@BatchMapping
public Map<User, List<Car>> cars(List<User> users) {
  return service.cars(users);
}
```

### Controlling batch vs. individual mapping

By default, `@glSkipOnServer` on a field generates a `@BatchMapping`. Use `batch: false` to generate a `@SchemaMapping` instead. This is **required** when the field has arguments, because `@BatchMapping` does not support field arguments.

```graphql
type User {
  id: ID!
  # No arguments — @BatchMapping (default, efficient)
  cars: [Car!]! @glSkipOnServer

  # Has arguments — must use batch: false
  carsByYear(year: Int!): [Car!]! @glSkipOnServer(batch: false)
}
```

**Server generates:**

```java
@BatchMapping
public Map<User, List<Car>> cars(List<User> users) { ... }

@SchemaMapping
public List<Car> carsByYear(User user, @Argument Integer year) { ... }
```

### Skipping an enum

```graphql
enum ServerOnlyRole @glSkipOnServer {
  SUPER_ADMIN
  SYSTEM
}
```

### Skipping an input

```graphql
input InternalInput @glSkipOnServer {
  rawPayload: String!
}
```

---

## Validation Rules and Errors

### 1. @glSkipOnClient or @glSkipOnServer on an input field

```graphql
# ERROR
input CreateUserInput {
  name: String!
  note: String @glSkipOnServer   # throws
}

# Correct: apply to the input type
input CreateUserInput @glSkipOnServer {
  name: String!
  note: String
}
```

**Error:** `@glSkipOnServer cannot be applied to an input field. Apply it to the input type itself instead.`

---

### 2. @glSkipOnServer with mapTo on an input

`mapTo` only makes sense on output types that participate in schema mapping. Inputs that are skipped on the server simply do not exist there.

```graphql
# ERROR
input MyInput @glSkipOnServer(mapTo: "ServerInput") {
  name: String!
}

# Correct
input MyInput @glSkipOnServer {
  name: String!
}
```

**Error:** `@glSkipOnServer on input 'MyInput' cannot have a 'mapTo' argument: the input is not generated on the server`

---

### 3. @glSkipOnServer with mapTo on a type field

`mapTo` is a property of the type definition, not of individual field annotations. Fields use the type's `mapTo` automatically.

```graphql
type Company { id: ID! }

type User {
  # ERROR
  company: Company! @glSkipOnServer(mapTo: "something")

  # Correct — no mapTo on the field
  company: Company! @glSkipOnServer
}
```

**Error:** `@glSkipOnServer on field 'User.company' cannot have a 'mapTo' argument`

---

### 4. A @glSkipOnServer input referenced in another input or query/mutation

An input skipped on the server cannot be referenced anywhere — there is no generated type to reference.

```graphql
input SkippedInput @glSkipOnServer {
  name: String!
}

# ERROR — SkippedInput is used as a field type
input WrapperInput {
  nested: SkippedInput!
}
```

**Error:** `Input 'WrapperInput' references 'SkippedInput' which is marked @glSkipOnServer`

```graphql
# ERROR — SkippedInput is used as a mutation argument
type Mutation {
  create(input: SkippedInput!): User!
}
```

**Error:** `Argument 'input' of 'Mutation.create' references 'SkippedInput' which is marked @glSkipOnServer`

---

### 5. mapTo target is also @glSkipOnServer

The target of `mapTo` must be a real server type. If the target is itself skipped, there is nothing to map to.

```graphql
type ServerType @glSkipOnServer {
  id: ID!
}

# ERROR — ServerType is skipped on server, cannot be a mapTo target
type ClientType @glSkipOnServer(mapTo: "ServerType") {
  id: ID!
}
```

**Error:** `Cannot use 'mapTo: "ServerType"' on 'ClientType': 'ServerType' is also marked @glSkipOnServer`

---

### 6. Field is @glSkipOnServer, its type is also @glSkipOnServer but has no mapTo

When a field's type is also `@glSkipOnServer`, the generator needs to know what server type to substitute. Without `mapTo` on the type, it has no replacement.

```graphql
type CarInfo @glSkipOnServer {   # no mapTo — ERROR
  brand: String!
}

type Person {
  carInfo: CarInfo @glSkipOnServer   # throws because CarInfo has no mapTo
}
```

**Error:** `Field 'Person.carInfo' has @glSkipOnServer and its type 'CarInfo' also has @glSkipOnServer — 'mapTo' is required on 'CarInfo'`

**Fix — add mapTo to the type:**

```graphql
type Car { brand: String! }

type CarInfo @glSkipOnServer(mapTo: "Car") {
  brand: String!
}

type Person {
  carInfo: CarInfo @glSkipOnServer   # valid — CarInfo maps to Car
}
```

---

### 7. Field with arguments missing @glSkipOnServer(batch: false)

On the Spring Boot server, non-root type fields with arguments must use `@SchemaMapping`, not `@BatchMapping`. Any such field must be explicitly marked.

```graphql
type User {
  # ERROR — has arguments but no @glSkipOnServer
  carsByYear(year: Int!): [Car!]!

  # ERROR — has arguments but batch: true is incompatible
  carsByYear(year: Int!): [Car!]! @glSkipOnServer

  # Correct
  carsByYear(year: Int!): [Car!]! @glSkipOnServer(batch: false)
}
```

**Error:** `Field 'carsByYear' on type 'User' has arguments but is missing @glSkipOnServer — add @glSkipOnServer(batch: false) to generate a @SchemaMapping for it`

---

## Quick Reference

```graphql
# Skip entire type on client
type ServerOnly @glSkipOnClient { ... }

# Skip entire type on server
type ClientOnly @glSkipOnServer { ... }

# Skip type on server, map to existing server type
type ClientView @glSkipOnServer(mapTo: "ServerEntity") { ... }

# Skip type on server with explicit batch control
type ClientView @glSkipOnServer(mapTo: "ServerEntity", batch: false) { ... }

# Skip a field on client (server forbids access)
type User {
  password: String! @glSkipOnClient
}

# Skip a field on server — generates @BatchMapping
type User {
  orders: [Order!]! @glSkipOnServer
}

# Skip a field on server — generates @SchemaMapping (required when field has arguments)
type User {
  ordersByStatus(status: String!): [Order!]! @glSkipOnServer(batch: false)
}

# Skip an input on client or server
input InternalInput @glSkipOnClient { ... }
input ServerOnlyInput @glSkipOnServer { ... }

# Skip an enum on client or server
enum InternalRole @glSkipOnClient { ... }
enum ServerRole @glSkipOnServer { ... }
```
