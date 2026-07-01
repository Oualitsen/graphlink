# CacheControl class — per-input cache invalidation

## Motivation

Today GraphLink clients cache query results via `@glCache(ttl, tags)`, and mutations can
invalidate cached entries via `@glCacheInvalidate(tags)` or `@glCacheInvalidate(all: true)`.
But there is no way for application code to **programmatically invalidate a specific cached
query result** — e.g. "bust the cache for `getUser(id: "42")`". Tag-based invalidation
nukes everything under a tag; `invalidateAll` nukes everything. Both are too coarse.

## What we're building

A `GraphLinkCacheControl` class, generated as a separate file in all 4 languages, that
exposes:

1. **Per-input invalidation methods** — one per `@glCache`-annotated query. Each mirrors
   the query's argument signature exactly and computes the cache key from those args.
2. **`invalidateByTags(tags)`** — tag-based invalidation (moved/duplicated from the
   resolver base for a clean public API).
3. **`invalidateAll()`** — clear all cache entries.

The class only generates when at least one `@glCache` directive exists in the schema.

### Example (Dart)

```dart
// Generated for: getUser(id: ID!): User @glCache(ttl: "5m", tags: ["users"])
class GraphLinkCacheControl {
  final GraphLinkCacheStore _store;
  final Map<String, GraphLinkLock> _tagLocks;

  GraphLinkCacheControl(this._store, this._tagLocks);

  Future<void> invalidateGetUser({required String id}) async {
    final key = GraphLinkPartialQuery.computeCacheKey('getUser', {'id': id});
    await _store.invalidate(key);
  }

  Future<void> invalidateByTags(List<String> tags) async { /* ... */ }
  Future<void> invalidateAll() => _store.invalidateAll();
}
```

Exposed on the client: `client.cacheControl.invalidateGetUser(id: "42")`.

---

## How `computeCacheKey` is shared

Each language already has a static `computeCacheKey` on `GraphLinkPartialQuery` — it's
used internally when constructing partial queries. CacheControl calls it directly.

| Language | Call site |
|----------|-----------|
| Dart | `GraphLinkPartialQuery.computeCacheKey(operationName, variables)` — already public static |
| Java | `GraphLinkPartialQuery.computeCacheKey(operationName, variables, encoder)` — already public static |
| TypeScript | `GraphLinkPartialQuery._computeCacheKey(...)` — currently **private**. Must be made public. |
| Kotlin | `computeCacheKey` in companion object — currently **private**. Must be made `internal` or `@JvmStatic`. |

The Dart `computeCacheKey` takes no encoder (it uses `jsonEncode` directly). Java takes
an encoder because `java.util.TreeMap` needs a `GraphLinkJsonEncoder.encode(...)` call.
Kotlin does the same. The per-input method must pass the variables map in the same shape
the query method does.

---

## Files to change

### Dart

1. **`lib/src/serializers/client_serializers/dart/dart_client_serializer.dart`**
   - Add `generateCacheControlFile()` → returns `GLClassModel`
   - Per-query methods: iterate `_parser.queries.values.where((q) => q.hasDirective(glCache) && q.type == GLQueryType.query)`
   - For each, generate `invalidate<OpName>(...)` with same arg list as query method
   - Reconstruct variables map using same `_serializeArgumentValue` logic
   - Generate `invalidateByTags` and `invalidateAll`
   - Wire `cacheControl` getter on `GraphLinkClient` — pass `store` and `tagLocks`

2. **`lib/src/generators/dart_client_generator.dart`**
   - Call `clientSerializer.generateCacheControlFile()` conditionally (when any `@glCache` query exists)
   - Output `graph_link_cache_control.dart`

3. **`lib/src/cache_store_dart.dart`**
   - `computeCacheKey` is already public static — no change needed

### Java

4. **`lib/src/serializers/client_serializers/java/java_client_serializer.dart`**
   - Add `generateCacheControlFile()` → returns `GLClassModel`
   - Per-query invalidation methods — each generates a `GraphLinkCacheControl` method
   - Variables map construction mirrors `serializePartialQueryJava`
   - Generate `invalidateByTags` and `invalidateAll`
   - `invalidateByTags` needs access to `tagLocks`; both receive them in constructor

5. **`lib/src/generators/java_client_generator.dart`**
   - Call conditionally

6. **`lib/src/cache_store_java.dart`**
   - `computeCacheKey` is already public static — no change needed

### TypeScript

7. **`lib/src/serializers/client_serializers/typescript/typescript_client_constants.dart`**
   - Rename `_computeCacheKey` → `computeCacheKey` (remove underscore so it's public)
   - Or add a public static wrapper that calls the private one

8. **`lib/src/serializers/client_serializers/typescript/typescript_client_serializer.dart`**
   - Add `generateCacheControlFile()`

9. **`lib/src/generators/typescript_client_generator.dart`**
   - Call conditionally

### Kotlin

10. **`lib/src/serializers/client_serializers/kotlin/kotlin_client_constants.dart`**
    - Make `computeCacheKey` in companion object non-private (remove `private` modifier)

11. **`lib/src/serializers/client_serializers/kotlin/kotlin_client_serializer.dart`**
    - Add `generateCacheControlFile()`

12. **`lib/src/generators/kotlin_client_generator.dart`**
    - Call conditionally

### Shared base

13. **`lib/src/serializers/gl_client_serializer.dart`**
    - Add a getter or helper that returns the set of `@glCache`-annotated query definitions
      (so each language serializer doesn't duplicate the filter)

### Tests

14. **`test/cache/dart/cache_control_test.dart`** — Dart test
    - Schema with one cached and one non-cached query
    - Assert `GraphLinkCacheControl` class is generated
    - Assert `invalidateGetUser(...)` method exists with correct signature
    - Assert non-cached query has no invalidation method
    - Assert no `CacheControl` file when schema has zero `@glCache` directives

### Docs

15. **`site/docs-src/caching.md`** — Add CacheControl section
16. **`site/docs-src/_llms_header.txt`** + **`_llms_concise_header.txt`** — Mention CacheControl
17. **`lib/src/main.dart`** — No config changes needed (CacheControl is always-on when
    `@glCache` exists; no new config key)

---

## Design decisions

### `invalidateByTags` stays on the resolver base for mutation invalidation

Mutations with `@glCacheInvalidate(tags: [...])` call `invalidateByTags` after success.
That path flows through the resolver base class, not CacheControl. So the base class
retains `invalidateByTags` as an internal method. CacheControl gets its own
`invalidateByTags` — same logic, different receiver. Both operate on the shared `store`
and `tagLocks` references.

### No config key

CacheControl is always generated when `@glCache` directives exist. There's no opt-out
because:
- It adds zero runtime overhead (just dead code if unused)
- `disableCache: true` already strips all cache directives, so no CacheControl would
  generate in that case

### Per-input methods only for queries (not mutations or subscriptions)

`@glCache` is only valid on queries — the validator already rejects it on mutations
and subscriptions. So per-input methods only iterate queries.

### Variables map mirrors the query method's construction

The same `_serializeArgumentValue` / `generateVariables` logic is used. For each arg:
- Scalar → raw value
- Input type → `.toJson()`
- Enum → `.toJson()`
- List → `.map((e) => e.toJson()).toList()`
- Upload → `null` (uploads can't appear on cached queries, but handled for safety)
- Hoist args (FieldArgs) → `...fieldArgs.toJson()` spread

---

## Implementation order

1. TypeScript: un-private `_computeCacheKey`
2. Kotlin: un-private `computeCacheKey`
3. Dart: `generateCacheControlFile()` + generator wiring + client wiring
4. Java: same
5. TypeScript: same
6. Kotlin: same
7. Test (Dart)
8. Docs
