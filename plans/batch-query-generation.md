# Plan: @glBatch — Client-Side Batch Query Generation

## Context

Developers with a schema like `getUser(id: ID!): User!` who need to fetch N users have no typed client option: they either make N separate round-trips or hand-write a raw aliased query string with no type safety. GraphLink should detect the `@glBatch` directive and generate a fully typed batch method that sends one HTTP request using GraphQL aliases, then maps the response back by index.

---

## Design Summary

Given:
```graphql
type Query {
  getUser(id: ID!): User! @glBatch
}
```

GraphLink generates (in addition to the normal `getUser` method):

```dart
// Generated method — returns List<ReturnType>, index-matched to inputs
Future<List<User>> getUserBatch(List<String> ids) async {
  // Builds at runtime:
  // query($id_0: ID!, $id_1: ID!) {
  //   item_0: getUser(id: $id_0) { ..._all_fields_User }
  //   item_1: getUser(id: $id_1) { ..._all_fields_User }
  // }
  // fragment _all_fields_User on User { ... }
  // results[i] corresponds to ids[i]
}
```

For nullable return: `getUser(id: ID!): User` → `Future<List<User?>>`.

For scalar return (no fragment): `getName(id: ID!): String! @glBatch` → `Future<List<String>>`.

**No wrapper classes.** The method returns `List<ReturnType>` directly. Correlation is index-based — the caller already has the input list, so `inputs[i] → results[i]` is always reliable.

**Scalar-only argument constraint:** `@glBatch` is only valid on queries whose single argument is a scalar or enum type (ID, String, Int, Float, Boolean, or any custom scalar/enum). Complex input objects are not supported.

**Single return type constraint:** `@glBatch` is only valid on queries whose return type is a single object, scalar, or enum — not a list. `[User!]!` is rejected at parse time.

**No directive arguments:** `@glBatch` takes no arguments. The generated method name is always `{queryName}Batch`.

**Fragment:** Generated only when the return type is an object type. Scalar and enum returns produce no fragment — the field is selected directly.

**Index-based mapping (key insight):** The response is matched to inputs purely by index. `inputs[i]` is aliased as `item_i` in the query, so `response["item_$i"]` always corresponds to `inputs[i]`.

**Caching:** Batch methods bypass the cache system entirely (documented limitation).

**Partial errors:** Not handled — deferred until GraphLink has general partial error support.

---

## Files to Change

### 1. `lib/src/model/built_in_dirctive_definitions.dart`
- Add `const glBatchDirective = "@glBatch";`
- Note: `glBatch = "batch"` already exists as a server-side schema mapping argument — no conflict

### 2. `lib/src/model/new_parser/gl_parser.dart`
- Register `@glBatch` in the `directives` map with scope `{GLDirectiveScope.FIELD_DEFINITION}` and no arguments

### 3. `lib/src/gl_validation_extension.dart`
- Add `checkGLBatchDirectives()` — validates:
  - `@glBatch` on a field with 0 or 2+ arguments → `ParseException`
  - `@glBatch` argument is a complex input type (not scalar/enum) → `ParseException`
  - `@glBatch` return type is a list → `ParseException`
  - `@glBatch` on a mutation or subscription field → `ParseException`
  - `@glBatch` when `autoGenerateQueries = false` → `ParseException`
  - Two or more `@glBatch` fields generate the same batch method name → `ParseException`
- Call `checkGLBatchDirectives()` in `validateSemantics()` inside the client mode block

### 4. `lib/src/model/gl_queries.dart`
- Add `final bool isBatch` field to `GLQueryDefinition` (default `false`)
- Add `final String? batchArgName` — the single argument's token name (used when building runtime variables)
- Update constructor

### 5. `lib/src/gl_grammar_extension.dart`
- In `generateQueries()`, after `_generateForField(field, queryType)`, check if field has `@glBatch`
- If yes, call new `_generateBatchForField(field, queryType)`:
  - Generated name: `${field.name.token}Batch`
  - Creates a `GLQueryDefinition` with `isBatch: true`, same elements as the original query, `batchArgName` = `field.arguments.first.token`
  - Calls `addQueryDefinitionSkipIfExists(def)`

### 6. Dart: `lib/src/serializers/client_serializers/dart_client_serializer.dart`
- In `queryToMethod(GLQueryDefinition def)`: when `def.isBatch`, delegate to `_batchQueryToMethod(def)`
- `_batchQueryToMethod` emits:
  - Method `Future<List<ReturnType>> ${name}(List<ArgType> ${argName}s) async`:
    1. Guard: `if (${argName}s.isEmpty) return const [];`
    2. If return type is object: static fragment string constant (same fragment as single query, emitted at codegen time)
    3. Runtime: build variable declarations string with `List.generate`
    4. Runtime: build aliased field string with `List.generate` (with or without fragment spread)
    5. Runtime: build variables map
    6. Call adapter with raw payload (query string + variables)
    7. Parse:
       - Object return: `List.generate(n, (i) => ReturnType.fromJson(data['item_\$i']))`
       - Scalar/enum return: `List.generate(n, (i) => data['item_\$i'] as ReturnType)`
    8. Return the list

### 7. TypeScript: `lib/src/serializers/client_serializers/typescript_client_serializer.dart`
- Same pattern: when `def.isBatch`, delegate to `_batchQueryToMethod(def)`
- No extra interfaces needed
- Method: `async ${name}(${argName}s: ArgType[]): Promise<ReturnType[]>`
- Guard: `if (${argName}s.length === 0) return [];`
- Fragment only emitted for object return types
- Results index-matched to inputs

### 8. Java: `lib/src/serializers/client_serializers/java_client_serializer.dart`
- Same pattern: when `def.isBatch`, delegate to `_batchQueryToMethod(def)`
- No extra classes needed
- Method: `public List<ReturnType> ${name}(List<ArgType> ${argName}s)`
- Guard: `if (${argName}s.isEmpty()) return Collections.emptyList();`
- Fragment only emitted for object return types
- Results index-matched to inputs

---

## Runtime Query Building (all languages)

**Object return type** (fragment generated):
```
query($id_0: ID!, $id_1: ID!) {
  item_0: getUser(id: $id_0) { ..._all_fields_User }
  item_1: getUser(id: $id_1) { ..._all_fields_User }
}
fragment _all_fields_User on User { ... }
```

**Scalar/enum return type** (no fragment):
```
query($id_0: ID!, $id_1: ID!) {
  item_0: getName(id: $id_0)
  item_1: getName(id: $id_1)
}
```

The argument GraphQL type string (e.g. `"ID!"`, `"String!"`) is resolved from `GLArgumentDefinition.type` at codegen time and emitted as a string literal into the method body.

---

## Validation Rules (parse-time)

| Condition | Error |
|---|---|
| `@glBatch` with 0 or 2+ args | ParseException |
| `@glBatch` argument is a complex input type | ParseException |
| `@glBatch` return type is a list | ParseException |
| `@glBatch` on mutation/subscription | ParseException |
| Duplicate generated batch method name | ParseException |
| `@glBatch` when `autoGenerateQueries = false` | ParseException |

---

## Verification

### A. Generated signatures (all three targets)

For each case below, verify the generated method signature in Dart, TypeScript, and Java.

| Schema | Dart | TypeScript | Java |
|---|---|---|---|
| `getUser(id: ID!): User! @glBatch` | `Future<List<User>> getUserBatch(List<String> ids)` | `getUserBatch(ids: string[]): Promise<User[]>` | `List<User> getUserBatch(List<String> ids)` |
| `findUser(email: String!): User @glBatch` | `Future<List<User?>> findUserBatch(List<String> emails)` | `findUserBatch(emails: string[]): Promise<(User \| null)[]>` | `List<User> findUserBatch(List<String> emails)` |
| `getName(id: ID!): String! @glBatch` | `Future<List<String>> getNameBatch(List<String> ids)` | `getNameBatch(ids: string[]): Promise<string[]>` | `List<String> getNameBatch(List<String> ids)` |
| `getName(id: ID!): String @glBatch` | `Future<List<String?>> getNameBatch(List<String> ids)` | `getNameBatch(ids: string[]): Promise<(string \| null)[]>` | `List<String> getNameBatch(List<String> ids)` |
| `getStatus(role: UserRole!): UserRole! @glBatch` | `Future<List<UserRole>> getStatusBatch(List<UserRole> roles)` | `getStatusBatch(roles: UserRole[]): Promise<UserRole[]>` | `List<UserRole> getStatusBatch(List<UserRole> roles)` |

### B. Generated query string (runtime)

This is the most critical part — verify the exact query string the method builds at runtime.

**Object return (`getUser(id: ID!): User! @glBatch`) with inputs `['1', '2', '3']`:**
```graphql
query($id_0: ID!, $id_1: ID!, $id_2: ID!) {
  item_0: getUser(id: $id_0) { ..._all_fields_User }
  item_1: getUser(id: $id_1) { ..._all_fields_User }
  item_2: getUser(id: $id_2) { ..._all_fields_User }
}
fragment _all_fields_User on User { ... }
```
Variables: `{ "id_0": "1", "id_1": "2", "id_2": "3" }`

**Scalar return (`getName(id: ID!): String! @glBatch`) with inputs `['1', '2']`:**
```graphql
query($id_0: ID!, $id_1: ID!) {
  item_0: getName(id: $id_0)
  item_1: getName(id: $id_1)
}
```
Variables: `{ "id_0": "1", "id_1": "2" }`
No fragment emitted.

### C. Index mapping

Verify that `results[i]` corresponds to `inputs[i]` — mock a response where `item_1` returns a different user than `item_0` and confirm the list order is preserved.

### D. Empty list guard

Call `getUserBatch([])` — verify it returns an empty list immediately without making any network request.

### E. Original method unaffected

For `getUser(id: ID!): User! @glBatch`, verify that `getUser(id: '1')` still generates and works exactly as without `@glBatch`.

### F. Validation errors (parse-time)

Each schema below must produce a `ParseException` — verify the error message identifies the offending field and directive.

| Schema | Expected error |
|---|---|
| `getUsers(id: ID!): [User!]! @glBatch` | List return type not allowed |
| `getUser(filter: UserFilter!): User! @glBatch` | Complex input arg not allowed |
| `getUser(id: ID!, name: String!): User! @glBatch` | More than one argument |
| `getUser: User! @glBatch` | Zero arguments |
| `addUser(id: ID!): User! @glBatch` (on Mutation) | Not allowed on mutation |
