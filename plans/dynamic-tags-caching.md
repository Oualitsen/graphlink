# Argument-Aware Dynamic Tags — Feature Plan

## Overview

Allow tag strings in `@glCache` and `@glCacheInvalidate` to interpolate resolver or mutation argument values using `$argName` syntax. This enables surgical, per-entry cache invalidation without introducing new serializer logic or a new invalidation primitive — the existing tag index mechanism handles everything.

---

## Goals

- Enable targeted invalidation of a single cached entry (e.g. only `getUser(id: "5")`) via mutations
- Reuse the existing tag infrastructure with no new runtime concept
- Minimal, uniform change across all three serializers (Dart, Java, TypeScript)
- Validate interpolated argument names at generation time

## Non-Goals

- Interpolating response fields (unreliable due to GraphQL projections — callers are not required to request any given field)
- Interpolating nested object arguments (only scalar arguments)
- Dynamic tag generation outside of `@glCache` / `@glCacheInvalidate`

---

## Syntax

A `$` prefix inside a tag string marks an argument interpolation:

```graphql
tags: ["user-detail-$id"]
```

`$id` resolves to the value of argument `id` at runtime. Multiple interpolations are supported:

```graphql
tags: ["user-role-$userId-$role"]
```

### Escaping

A literal `$` in a tag string is written as `$$`:

```graphql
tags: ["price-$$usd"]   # produces the tag "price-$usd"
```

---

## Query Side — `@glCache`

`$argName` refers to the **resolver's arguments**.

```graphql
type Query {
  getUser(id: ID!): User!
    @glCache(ttl: "1m", tags: ["users", "user-detail-$id"])

  getUserRole(userId: ID!, role: String!): UserRole!
    @glCache(ttl: "5m", tags: ["user-role-$userId-$role"])
}
```

At cache write time the generator emits tag interpolation from the variables map:

```dart
// generated — resolves tags at runtime from variables
final tags = ["users", "user-detail-${variables['id']}"];
```

Each unique argument combination produces a unique tag: `getUser("5")` writes tag `"user-detail-5"`, `getUser("42")` writes tag `"user-detail-42"`.

---

## Mutation Side — `@glCacheInvalidate`

`$argName` refers to the **mutation's arguments**.

```graphql
type Mutation {
  updateUser(id: ID!, input: UpdateUserInput!): User!
    @glCacheInvalidate(tags: ["user-detail-$id"])

  deleteUser(id: ID!): Boolean!
    @glCacheInvalidate(tags: ["user-detail-$id"])

  createUser(input: CreateUserInput!): User!
    @glCacheInvalidate(tags: ["users"])   # no specific id available — bulk is correct here
}
```

At mutation-success time the generator emits:

```dart
// generated — resolves tag at runtime from mutation arguments
await invalidateTag("user-detail-${mutationArgs['id']}");
```

---

## Mixing Static and Dynamic Tags

Static and dynamic tags can be combined freely on the same resolver:

```graphql
type Query {
  getUser(id: ID!): User!
    @glCache(ttl: "1m", tags: ["users", "user-detail-$id"])
}

type Mutation {
  # Surgical — only evicts the specific user
  updateUser(id: ID!, input: UpdateUserInput!): User!
    @glCacheInvalidate(tags: ["user-detail-$id"])

  # Bulk — evicts every cached user entry
  purgeUsers: Boolean!
    @glCacheInvalidate(tags: ["users"])
}
```

---

## Generator Validation

At generation time the generator must:

1. **Resolve `$argName`** — confirm the argument exists on the resolver (for `@glCache`) or on the mutation/subscription (for `@glCacheInvalidate`). Emit a generation error if not:

```
Error: dynamic tag "$userId" in @glCacheInvalidate on deleteUser references unknown argument "userId".
       Available arguments: id, input
```

2. **Scalar-only** — warn if `$argName` resolves to a non-scalar argument (object or list). Object serialization in a tag string produces unpredictable results:

```
Warning: dynamic tag "$input" in @glCache on getUser references a non-scalar argument.
         Only scalar arguments produce reliable tag strings.
```

3. **No `$` in static tag names** — a bare `$` without a valid identifier following it is a generation error:

```
Error: invalid tag string "user-$" in @glCache on getUser.
       Use "$$" for a literal dollar sign or "$argName" for interpolation.
```

---

## Tag Index Behavior

The tag index (`__tag__<tagValue>`) works identically to static tags. Each interpolated tag value gets its own index entry:

```
__tag__users              →  ["hash1", "hash2", "hash3", ...]   # all users
__tag__user-detail-5      →  ["hash_for_getUser_id5"]
__tag__user-detail-42     →  ["hash_for_getUser_id42"]
```

`invalidateTag("user-detail-5")` evicts only the entry for `getUser(id: "5")`. The `"users"` tag still covers all of them for bulk invalidation.

**Tag index growth:** one entry per unique argument value. Acceptable in practice — the index lives in the same store as the data, and `invalidateAll()` clears everything including orphaned tag entries.

---

## Serializer Changes

All three serializers (Dart, Java, TypeScript) need one uniform change: wherever tags are written as a static list, emit a runtime-interpolated list instead when any tag contains a `$` marker.

### Dart

```dart
// Before (static tags)
final tags = ["users"];

// After (dynamic tags)
final tags = ["users", "user-detail-${variables['id']}"];
```

### Java

```java
// Before
List<String> tags = List.of("users");

// After
List<String> tags = List.of("users", "user-detail-" + variables.get("id"));
```

### TypeScript

```typescript
// Before
const tags = ["users"];

// After
const tags = ["users", `user-detail-${variables['id']}`];
```

The tag interpolation logic in `invalidateTag` calls is identical in shape — just resolved from mutation arguments instead of query variables.

---

## Affected Files

- Generator directive parser / validator — interpolation detection and argument validation
- Dart client serializer — tag list code generation
- Java client serializer — tag list code generation
- TypeScript client serializer — tag list code generation
- Documentation (`site/docs-src/caching.md`, `site/docs-src/directives.md`)

---

## Full Example

```graphql
type Query {
  getUser(id: ID!): User!
    @glCache(ttl: "1m", tags: ["users", "user-detail-$id"])

  listUsers(page: Int!): [User!]!
    @glCache(ttl: "2m", tags: ["users"])
}

type Mutation {
  createUser(input: CreateUserInput!): User!
    @glCacheInvalidate(tags: ["users"])

  updateUser(id: ID!, input: UpdateUserInput!): User!
    @glCacheInvalidate(tags: ["user-detail-$id"])

  deleteUser(id: ID!): Boolean!
    @glCacheInvalidate(tags: ["user-detail-$id"])

  purgeAllUsers: Boolean!
    @glCacheInvalidate(tags: ["users"])
}
```

Result:
- `createUser` → evicts all users (list caches)
- `updateUser(id: "5")` → evicts only the `getUser("5")` cache entry
- `deleteUser(id: "5")` → evicts only the `getUser("5")` cache entry
- `purgeAllUsers` → evicts every `users`-tagged entry
- `listUsers` cache is unaffected by `updateUser` / `deleteUser` — it carries the `"users"` tag, not `"user-detail-*"`
