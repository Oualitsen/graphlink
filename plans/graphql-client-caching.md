# GraphQL Client Caching — Feature Plan

## Overview

Add opt-in, statically generated caching support to the Dart GraphQL client.
Cache behavior is declared at the **resolver level** (individual fields within a query) via custom directives, with an optional global config fallback.
The cache implementation is fully generated — no external dependencies required.

GraphLink uses **granular caching**: within a single query containing multiple resolvers, each resolver is evaluated independently. Some resolvers can be served from cache while others hit the network — all in the same request cycle. The final response is always a merged result of cached and freshly fetched data.

---

## Goals

- Cache individual GraphQL resolver responses with TTL-based expiration
- Support partial query execution — only fetch resolvers that are not cached
- Support tag-based invalidation across related resolvers
- Generate a type-safe cache invalidation API per cached resolver
- Zero runtime configuration required (all derived from directives + config at generation time)
- Memory cache by default (extensible later to persistent storage)

## Non-Goals (for now)

- Java client caching (planned, later iteration)
- Network policies other than cache-first
- Normalized / entity-level caching (Apollo-style)
- Persistent cache (disk, SharedPreferences, Hive, SQLite)
- Cache-and-Network / stale-while-revalidate strategy
- Per-variable cache key customization

---

## Directives

### `@gqCache`

Applied to **individual resolvers** within a query. Each resolver is cached independently.

```graphql
query UsersQuery($page: Page) {
  getUsers(page: $page) @gqCache(ttl: 300, tag: "users") {
    id
    username
  }
  getDrivers(page: $page) @gqCache(ttl: 120, tag: "drivers") {
    firstName
    lastName
  }
}
```

| Param | Type     | Required | Default              | Description                       |
|-------|----------|----------|----------------------|-----------------------------------|
| `ttl` | `Int`    | No       | global default or 300s | Cache duration in seconds       |
| `tag` | `String` | No       | —                    | Group label for bulk invalidation |

Resolvers without `@gqCache` are **always fetched from the network**, even when sibling resolvers are cached.

**Generator validation:** Using `@gqCache` on a mutation or subscription field is a **generation-time error**:

```
Error: @gqCache is not allowed on mutations (CreateUser.createUser).
       Mutations change server state — caching their response would silently skip the write.

Error: @gqCache is not allowed on subscriptions (OnUserCreated.userCreated).
       Subscriptions are event streams — there is no single response to cache.
```

---

### `@gqNoCache`

Applied to a resolver. Opts it out of caching even when global cache is enabled.

```graphql
query MarketQuery {
  getLivePrice @gqNoCache { value }
  getCategories @gqCache(ttl: 600, tag: "categories") { id name }
}
```

---

### `@gqInvalidate`

Applied to **queries, mutations, and subscriptions**. Evicts all cached resolvers matching the given tags.

```graphql
mutation CreateUser @gqInvalidate(tags: ["users"]) {
  createUser(input: $input) {
    id
  }
}
```

| Param  | Type       | Required | Description                                 |
|--------|------------|----------|---------------------------------------------|
| `tags` | `[String]` | Yes      | List of tags whose cached resolvers to evict |

**Timing differs by operation type:**

| Applied to   | When invalidation fires                                      |
|--------------|--------------------------------------------------------------|
| Query        | **Before** the query executes — forces a cache miss on matching resolvers, ensuring a fresh network fetch |
| Mutation     | **After** successful response — errors do not trigger invalidation |
| Subscription | **On each data event** — errors do not trigger invalidation  |

Query example — force-refresh `drivers` cache every time this query runs:

```graphql
query DriversQuery($page: Page) @gqInvalidate(tags: ["drivers"]) {
  getDrivers(page: $page) @gqCache(ttl: 120, tag: "drivers") {
    firstName
    lastName
  }
}
```

This evicts `drivers` entries before execution, so `getDrivers` always sees a cache miss and hits the network, then re-populates the cache with the fresh response.

---

## Global Configuration

Users can enable caching globally via config, applying to all resolvers not explicitly annotated.

```yaml
# gq_config.yaml
cache:
  enabled: true      # false by default — opt-in is safer
  ttl: 300           # default TTL in seconds (5 minutes)
```

**Priority order (highest to lowest):**
1. `@gqNoCache` — always wins, resolver is never cached
2. `@gqCache(ttl: X, tag: "Y")` — explicit per-resolver override
3. Global config `cache.enabled + cache.ttl` — fallback for all resolvers not annotated

---

## Cache Key Strategy

Cache keys are scoped to the **resolver**, not the query. Each resolver gets its own key:

```
<QueryName>.<resolverName>:<sortedJson(variables)>
```

Examples:
```
UsersQuery.getUsers:{"page":{"number":1}}
UsersQuery.getDrivers:{"page":{"number":1}}
```

- If no variables: key is `<QueryName>.<resolverName>`
- Variables are JSON-encoded with **keys sorted alphabetically** for determinism
- Keys are auto-derived — the developer never constructs them manually

---

## Partial Query Execution — Core Mechanic (Granular Caching)

This is the central design decision. GraphLink resolves caching at the **resolver level, not the query level**: within a single query, each resolver is independently checked against the cache. The result is that one resolver may be served from cache while a sibling resolver fires a network request — all transparently within one `client.usersQuery()` call.

Since `@gqCache` is resolver-level, a query may have a mix of cache hits, misses, and non-cached resolvers.

### Resolver states

| Resolver type           | Cache state | Action              |
|-------------------------|-------------|---------------------|
| `@gqCache` annotated    | Hit         | Serve from cache    |
| `@gqCache` annotated    | Miss/Expired| Include in network request |
| No `@gqCache`           | —           | Always include in network request |

### Execution flow

```
query fires
    ↓
for each resolver:
    → @gqCache + hit?  → read from cache
    → @gqCache + miss? → add to "needs network" list
    → no @gqCache?     → add to "needs network" list
    ↓
any resolvers in "needs network" list?
    → YES → generate + fire partial query with only those resolvers
           → cache any @gqCache resolvers from the response
           → merge with cached results
    → NO  → return fully cached response, no network call
    ↓
return merged response
```

### Generated partial query builder

The generator produces a dynamic query builder per query that constructs a valid GraphQL query string including only the requested resolvers:

```dart
String _buildUsersQueryPartial({
  bool includeGetUsers = false,
  bool includeGetDrivers = false,
}) {
  final fields = StringBuffer();
  if (includeGetUsers) fields.write('getUsers(page: $page) { id username }');
  if (includeGetDrivers) fields.write('getDrivers(page: $page) { firstName lastName }');
  return 'query UsersQuery(\$page: Page) { ${fields.toString()} }';
}
```

---

## Generated Query Method Shape (conceptual)

```dart
Future<UsersQueryResponse> usersQuery(Page page) async {
  final response = UsersQueryResponse();
  final variables = {"page": page.toJson()};

  // --- cache resolution ---
  final cachedUsers = _getIfValid("UsersQuery.getUsers", variables);
  final cachedDrivers = _getIfValid("UsersQuery.getDrivers", variables);

  if (cachedUsers != null) response.getUsers = cachedUsers;
  if (cachedDrivers != null) response.getDrivers = cachedDrivers;

  // --- partial network fetch ---
  final needsUsers = cachedUsers == null;
  final needsDrivers = cachedDrivers == null;

  if (needsUsers || needsDrivers) {
    final partial = await _executePartial(
      _buildUsersQueryPartial(
        includeGetUsers: needsUsers,
        includeGetDrivers: needsDrivers,
      ),
      variables,
    );

    if (needsUsers) {
      response.getUsers = partial.getUsers;
      _cacheStore("UsersQuery.getUsers", variables, partial.getUsers, ttl: 300);
    }
    if (needsDrivers) {
      response.getDrivers = partial.getDrivers;
      _cacheStore("UsersQuery.getDrivers", variables, partial.getDrivers, ttl: 120);
    }
  }

  return response;
}
```

---

## `GraphLinkCache` Interface

A minimal storage interface. Users can implement it to plug in any backend.

```dart
abstract class GraphLinkCache {
  void cache(String key, String value);
  String? getCache(String key);
  void deleteCache(String key);
}
```

**Three methods, nothing more.** No TTL, no tags, no expiry — those are the generated layer's concern.

### Default generated implementation

```dart
class InMemoryGraphLinkCache implements GraphLinkCache {
  final Map<String, String> _store = {};

  @override
  void cache(String key, String value) => _store[key] = value;

  @override
  String? getCache(String key) => _store[key];

  @override
  void deleteCache(String key) => _store.remove(key);
}
```

Users can replace it by passing their own implementation to the client constructor.

---

## TTL & Expiry — Generated Layer Responsibility

TTL tracking lives in the generated client, not in `GraphLinkCache`:

```dart
// Internal to generated client — not exposed to user
final Map<String, DateTime> _cacheExpiry = {};
final Map<String, Set<String>> _tagIndex = {};  // tag → set of cache keys
```

`_getIfValid(key, variables)` checks expiry before reading:
- Expired → call `cache.deleteCache(key)`, return null (treat as miss)
- Valid → return deserialized value

---

## Client Integration

```dart
// Default — in-memory cache
final client = MyGraphQLClient(link: ...);

// Custom — bring your own cache backend
final client = MyGraphQLClient(link: ..., cache: MyHiveCache());
```

Call site is unchanged — caching is fully transparent:

```dart
final result = await client.usersQuery(page);
```

---

## Manual Invalidation API

```dart
client.invalidateGetUsers();       // generated per @gqCache resolver
client.invalidateGetDrivers();     // generated per @gqCache resolver
client.invalidateTag("users");     // bulk by tag
client.invalidateAll();            // wipe everything
```

| Method | Scope | Generated? |
|---|---|---|
| `client.invalidate<ResolverName>()` | Single resolver (all variable combinations) | Yes — one per `@gqCache` resolver |
| `client.invalidateTag(String tag)` | All resolvers sharing a tag | No — always present |
| `client.invalidateAll()` | Entire cache | No — always present |

All methods delegate to `cache.deleteCache(key)` internally and clean up `_cacheExpiry` and `_tagIndex` entries.

---

## Mutation Invalidation Flow

```
mutation fires
    ↓
network request executes
    ↓
success? → YES → for each tag in @gqInvalidate:
                   → find all keys in _tagIndex[tag]
                   → call cache.deleteCache(key) for each
                   → remove from _cacheExpiry and _tagIndex
         → NO  → do nothing, cache remains untouched
```

---

## Subscription Cache Invalidation

`@gqInvalidate` is also supported on subscriptions. The semantics are the same as mutations — each incoming event that is **not an error** triggers tag-based invalidation. This ensures that any query caches affected by server-side changes are evicted as events arrive.

```graphql
subscription OnUserCreated @gqInvalidate(tags: ["users"]) {
  userCreated {
    id
    username
  }
}
```

### Behavior

- Invalidation fires on **each received event**, not on subscription start or close.
- Error events (stream errors or GraphQL errors in the event payload) do **not** trigger invalidation — same rule as mutations.
- The subscription itself is never cached; only the tags it references are evicted from the query cache.

### Subscription Invalidation Flow

```
subscription event received
    ↓
event is a data event (no error)?
    → YES → for each tag in @gqInvalidate:
               → find all keys in _tagIndex[tag]
               → call cache.deleteCache(key) for each
               → remove from _cacheExpiry and _tagIndex
    → NO  → do nothing, cache remains untouched
    ↓
yield event to caller as normal
```

The invalidation is **fire-and-forget** relative to the stream — it does not delay or alter the event delivered to the caller.

---

## Future Considerations

- **Java client** — mirror the same directive-based approach once Dart implementation is stable
- **Persistent cache** — `GraphLinkCache` interface already supports this, just implement it
- **Cache-and-Network** — return cached resolvers immediately, stream updates when network responds
- **Cache size limits** — max entries or max memory cap with LRU eviction
- **Cache inspector** — debug utility to inspect current cache state during development

---

## Open Questions

- Should `invalidate<ResolverName>()` evict all entries for that resolver (across all variable combinations) or only for a specific variable set? **Current assumption: all variable combinations.**
- Should the generated code handle concurrent async requests to the same resolver key (request deduplication / in-flight tracking)?
