# SQL Client Generation

## Context

GraphLink generates fully-typed HTTP clients (Dart, Java, TypeScript, Kotlin) from a GraphQL schema.
This plan adds a **SQL client target** — instead of emitting HTTP calls, the generated client
emits SQL against a relational database. The schema drives everything: table mapping, field
selection, filter conditions, mutation strategy, and transaction boundaries.

Target languages: **Java first**, then Kotlin, TypeScript, maybe Dart.

No DDL generation in scope — tables are assumed to exist and match the schema.

---

## Core idea

The same schema that drives the API client drives the database client:

```graphql
type User {
  id: ID!
  firstName: String!
  email: String!
  vehicles: [Vehicle!]!
}

type Query {
  findUser(input: FindUserInput): User
}

type Mutation {
  updateUser(id: ID!, input: UserUpdateInput): User!
  deleteUser(id: ID!): Boolean!
}
```

Generated Java usage:

```java
client.queries.findUser(ctx, new FindUserInput().email("r@example.com"));
client.mutations.updateUser(ctx, "1", new UserUpdateInput().firstName("Ramdane"));
client.mutations.deleteUser(ctx, "1");
```

---

## Projection context

The client receives a `ProjectionContext` that carries which fields the GraphQL client
requested. This drives both the SELECT columns and which relationships to load.

```java
// Generated method signature
public User findUser(ProjectionContext ctx, FindUserInput input)
```

**All generated server-side types have fully nullable fields** — regardless of schema
nullability — because a field being `null` in the returned object means it was not
requested, not that it is absent from the database.

```java
// Generated — always fully nullable
public class User {
  String id;
  String firstName;
  String email;
  List<Vehicle> vehicles;
}
```

### Honest concern #1 — ProjectionContext coupling

`ProjectionContext` must be populated by the middleware layer (Spring GraphQL's
`DataFetchingEnvironment`, Express graphql-js resolver `info`). This is non-trivial
and couples the SQL client to the GraphQL execution framework. It is not pure
generation — the middleware must extract and pass the selection set. This needs
a clear adapter per framework and good documentation.

---

## Naming convention

GraphQL field names (camelCase) map to SQL column names (snake_case) by default:

| GraphQL field | SQL column |
|---|---|
| `firstName` | `first_name` |
| `userId` | `user_id` |
| `createdAt` | `created_at` |

Type name maps to table name: `User` → `user`, `UserProfile` → `user_profile`.

Override with a directive when convention is not enough:

```graphql
type User @glTable(name: "app_users") {
  firstName: String! @glColumn(name: "f_name")
}
```

---

## New directives

### `@glFilter`

Declares the SQL operator for a filter input field:

```graphql
input FindUserInput {
  id: ID
  firstName: String @glFilter(op: LIKE)
  email: String     @glFilter(op: EQ)
  minAge: Int       @glFilter(field: "age", op: GTE)
  maxAge: Int       @glFilter(field: "age", op: LTE)
}
```

No directive = `EQ` by default. Supported operators: `EQ`, `NEQ`, `LIKE`, `GT`, `GTE`,
`LT`, `LTE`, `IN`.

GraphLink validates at generation time that `field` (or the field name by convention)
exists on the corresponding return type. Generation fails if not — not a runtime error.

### `@glTransactional`

Wraps a composite mutation in a single database transaction:

```graphql
mutation updateUserAndVehicle(
  userId: ID!
  vehicleId: ID!
  userInput: UserUpdateInput!
  vehicleInput: VehicleUpdateInput!
): UpdateUserAndVehicleResult! @glTransactional {
  updateUser(id: $userId, input: $userInput)
  updateVehicle(id: $vehicleId, input: $vehicleInput)
}
```

Generated: `BEGIN` → each inner operation → `COMMIT`, or `ROLLBACK` on any error.
Each inner operation is treated as a unit (see mutation strategy below).

### `@glJoinTable`

Required for many-to-many relationships where the join table name cannot be inferred:

```graphql
type User {
  roles: [Role!]! @glJoinTable(name: "user_roles", from: "user_id", to: "role_id")
}
```

### `@glTable` / `@glColumn`

Override the default camelCase → snake_case naming convention (see above).

---

## Query generation

```graphql
type Query {
  findUser(input: FindUserInput): User
}
```

Generated SQL (driven by `ProjectionContext` + non-null filter fields):

```sql
-- Only requested columns SELECTed
-- Only non-null filter fields included in WHERE
SELECT id, first_name FROM user
WHERE email = ? AND first_name LIKE ?
```

All WHERE conditions are `AND`. `OR` logic is out of scope for now.

---

## Mutation generation

### INSERT

```graphql
mutation createUser(input: CreateUserInput!): User!
```

```sql
BEGIN;
INSERT INTO user (first_name, last_name, email) VALUES (?, ?, ?);
SELECT id, first_name, last_name, email FROM user WHERE id = LAST_INSERT_ID();
COMMIT;
```

SELECT after INSERT is driven by the return type — same as UPDATE below.

### UPDATE

```graphql
mutation updateUser(id: ID!, input: UserUpdateInput): User!
```

**Only non-null fields in `UserUpdateInput` are included in SET** — patch semantics,
not replace. This requires **runtime SQL building** — a small query builder is generated
alongside the client. This is the one honest compromise: the SET clause cannot be fully
baked at generation time without generating 2^n permutations.

```sql
BEGIN;
UPDATE user SET first_name = ? WHERE id = ?;  -- only non-null fields
SELECT id, first_name, email FROM user WHERE id = ?;  -- driven by projection
COMMIT;
```

### DELETE — `Boolean` return

```sql
DELETE FROM user WHERE id = ?;
-- rows affected > 0 → true
```

### DELETE — `User` return (fetch-before-delete)

```sql
BEGIN;
SELECT id, first_name, email FROM user WHERE id = ?;
DELETE FROM user WHERE id = ?;
COMMIT;
-- return pre-fetched User (null / throw if not found, driven by nullability)
```

Return type nullability drives not-found behavior:
- `User!` → throw if not found, skip DELETE
- `User` → return null if not found, skip DELETE

---

## Relationship loading

Driven entirely by `ProjectionContext` — relationships not in the projection are never
loaded.

### One-to-One

```sql
-- JOIN — single round trip
SELECT u.id, u.first_name, p.bio
FROM user u
JOIN user_profile p ON p.user_id = u.id
WHERE u.id = ?
```

### One-to-Many

```sql
-- Two queries — avoids row duplication
SELECT id, first_name FROM user WHERE id = ?;
SELECT id, brand FROM vehicle WHERE user_id = ?;
```

### Many-to-Many

```sql
SELECT r.id, r.name FROM role r
JOIN user_role ur ON ur.role_id = r.id
WHERE ur.user_id = ?
```

Requires `@glJoinTable` when table name cannot be inferred.

---

## Honest concern #2 — Dynamic UPDATE is not zero-runtime

The vision is "SQL baked at generation time." For queries and deletes this holds.
For UPDATE with nullable input fields it does not — the SET clause is built at runtime
based on which fields are non-null. The generated code carries a minimal query builder
for this case. It is not annotation magic, it is explicit and readable, but it is
runtime SQL construction.

---

## Honest concern #3 — FilterInput ↔ type field mapping

Without `@glFilter(field: ...)`, GraphLink infers the column from the filter field name
by convention. This works for `firstName → first_name` but breaks silently for
`minAge → min_age` (no such column). Generation-time validation catches this — but
only if the return type is known from the query signature. If `FindUserInput` is reused
across multiple queries returning different types, validation becomes ambiguous.

**Recommendation:** require `@glFilter(field: ...)` whenever the filter field name
does not directly match a field on the return type.

---

## Honest concern #4 — No subscriptions

Subscriptions are out of scope. SQL databases do not have a universal push mechanism.
PostgreSQL `LISTEN/NOTIFY` is the only clean option and is dialect-specific.
Adding subscriptions later should be a separate plan, PostgreSQL-only.

---

## Configuration

Config key: `clientConfig.sql` (same level as `clientConfig.java`).

```json
{
  "mode": "client",
  "outputDir": "src/main/java/com/example/generated",
  "clientConfig": {
    "sql": {
      "packageName": "com.example.generated",
      "dialect": "postgresql",
      "namingConvention": "snake_case"
    }
  }
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `packageName` | string | required | Java package name |
| `dialect` | string | `postgresql` | `postgresql`, `mysql`, `sqlite` |
| `namingConvention` | string | `snake_case` | Column naming: `snake_case` or `as_is` |

---

## Implementation steps

1. Register new directives in `model/built_in_dirctive_definitions.dart`:
   `@glFilter`, `@glTransactional`, `@glJoinTable`, `@glTable`, `@glColumn`
2. Add getters on `gl_grammar_extension.dart` for SQL-relevant derived data
3. Add `SqlClientConfig` to `config.dart`
4. Create `generators/sql_client_generator.dart`
5. Create `serializers/client_serializers/java_sql_client_serializer.dart`
6. Add runtime query builder (minimal — UPDATE SET clause only) as a generated
   utility class, not a GraphLink dependency
7. Wire into `main.dart` dispatch
8. Add tests under `test/sql/`
9. Add example under `examples/java-sql/`

---

## Out of scope (for now)

- DDL / migration generation
- Subscriptions
- OR filter conditions
- Aggregations (`COUNT`, `SUM`, etc.)
- Pagination (`LIMIT` / `OFFSET`) — needs its own design
- TypeScript and Dart SQL clients — follow Java once stable
