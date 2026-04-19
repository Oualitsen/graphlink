---
title: Caching — GraphLink Docs
description: GraphLink's built-in caching — @glCache and @glCacheInvalidate directives, TTL, tag-based invalidation, partial query caching, staleIfOffline, and custom cache stores.
---

# Built-In Caching

Cache control belongs in the schema, not scattered across your application code.

## How it works

GraphLink caching is opt-in and declared entirely at the schema level using two directives: `@glCache` on queries and `@glCacheInvalidate` on mutations. The generated client handles all cache logic automatically — reading from cache, writing to cache, and evicting entries on mutation. No application code is needed to enable or configure caching.

The cache operates on the client side. It stores serialized response data keyed by operation name + variables. The server never knows about client-side caching.

## @glCache — caching a query

Annotate any query field with `@glCache` to have its response cached:

```graphql title="@glCache directive"
type Query {
  # Cache for 120 seconds, tagged "vehicles"
  getVehicle(id: ID!): Vehicle! @glCache(ttl: 120, tags: ["vehicles"])

  # Cache for 60 seconds, same tag group
  listVehicles: [Vehicle!]! @glCache(ttl: 60, tags: ["vehicles"])

  # Cache for 300 seconds, no tags (cannot be tag-invalidated)
  getStaticConfig: AppConfig! @glCache(ttl: 300)

  # Cache with staleIfOffline — serve stale data if network fails
  getUserProfile(id: ID!): UserProfile @glCache(ttl: 60, staleIfOffline: true)
}
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `ttl` | `Int` | Yes | Time-to-live in seconds. After this duration, the entry is considered expired and the next call will hit the server. |
| `tags` | `[String!]` | No | List of tags to associate with this cache entry. Used for group invalidation via `@glCacheInvalidate`. |
| `staleIfOffline` | `Boolean` | No | If `true`, serve the expired cached value when the network call fails instead of throwing. |

## Cache keys

Cache entries are keyed by a combination of the operation name and the serialized variables. The key is computed as an FNV1a hash of `operationName + JSON(variables)`. This means:

- `getVehicle("42")` and `getVehicle("99")` produce different cache entries
- `getVehicle("42")` called twice produces the same cache key — the second call returns the cached result
- `listVehicles()` (no variables) always produces the same cache key regardless of call site

!!! info "Per-argument caching"
    Each unique argument combination gets its own cache entry. Calling `getVehicle` with 100 different IDs stores 100 separate cache entries. All of them share the `"vehicles"` tag, so a single `addVehicle` mutation invalidates all 100 at once.

## @glCacheInvalidate — busting the cache

Annotate a mutation with `@glCacheInvalidate` to automatically evict cache entries when the mutation succeeds:

```graphql title="@glCacheInvalidate directive"
type Mutation {
  # Evicts all cache entries tagged "vehicles"
  addVehicle(input: AddVehicleInput!): Vehicle! @glCacheInvalidate(tags: ["vehicles"])

  # Evicts entries tagged "vehicles" AND "persons"
  transferVehicle(vehicleId: ID!, newOwnerId: ID!): Vehicle!
    @glCacheInvalidate(tags: ["vehicles", "persons"])

  # Wipes the ENTIRE cache
  resetAllData: Boolean! @glCacheInvalidate(all: true)
}
```

| Argument | Type | Description |
|---|---|---|
| `tags` | `[String!]` | Evict all cache entries that were stored with any of these tags. |
| `all` | `Boolean` | When `true`, evict the entire cache regardless of tags. |

## Tag-based invalidation

Tags are labels you attach to cache entries at write time. When you later invalidate a tag, all entries carrying that tag are evicted simultaneously.

This allows a single mutation to invalidate many different cached queries at once, even if those queries have different operation names and different variable sets:

```graphql title="Tag invalidation in action"
type Query {
  getVehicle(id: ID!): Vehicle!       @glCache(ttl: 120, tags: ["vehicles"])
  listVehicles: [Vehicle!]!           @glCache(ttl: 60,  tags: ["vehicles"])
  getFleet(ownerId: ID!): [Vehicle!]! @glCache(ttl: 90,  tags: ["vehicles"])
}

type Mutation {
  # One mutation invalidates ALL three queries above
  addVehicle(input: AddVehicleInput!): Vehicle!      @glCacheInvalidate(tags: ["vehicles"])
  updateVehicle(id: ID!, input: AddVehicleInput!): Vehicle! @glCacheInvalidate(tags: ["vehicles"])
  deleteVehicle(id: ID!): Boolean!                   @glCacheInvalidate(tags: ["vehicles"])
}
```

After calling `addVehicle`, the next call to `getVehicle`, `listVehicles`, or `getFleet` will always go to the server — no stale data.

## Partial query caching

This is GraphLink's most powerful caching feature. When a query returns multiple aliased fields, each field can carry its own `@glCache` directive. The client fetches each field independently and caches them separately.

The result: if one tag is invalidated, only the affected portion of the query is re-fetched. The rest is still served from cache.

```graphql title="Partial caching — schema"
type Query {
  # These two aliases will be cached separately
  vehicle: Vehicle! @glCache(ttl: 120, tags: ["vehicles"])
  owner:   Person!  @glCache(ttl: 300, tags: ["persons"])
}
```

Here is what happens step by step:

1. **First call** — both `vehicle` and `owner` are cache misses. The client sends requests to the server for both. Results are stored: `vehicle` tagged `["vehicles"]`, `owner` tagged `["persons"]`.
2. **Second call (within TTL)** — both hits. No network requests.
3. **addVehicle mutation runs** — `@glCacheInvalidate(tags: ["vehicles"])` evicts the `vehicle` entry. The `owner` entry is unaffected.
4. **Third call** — `vehicle` is a miss (re-fetched from server). `owner` is still a hit (served from cache). One network request instead of two.

Partial query caching is especially valuable in dashboard or profile screens that combine volatile data (frequently updated) with stable data (rarely changed). The stable portion never leaves the cache even when the volatile portion is invalidated.

## staleIfOffline

When `staleIfOffline: true` is set on a cached query and the cache entry has expired, GraphLink attempts a server request. If that request fails (network error, timeout, server unreachable), it falls back to the expired cached value instead of throwing an exception.

This is especially useful on mobile apps where network connectivity is unreliable. Users see slightly outdated data rather than an error screen:

```graphql title="staleIfOffline example"
type Query {
  # If expired and network fails, return the last known value
  getUserProfile(id: ID!): UserProfile @glCache(ttl: 60, staleIfOffline: true)

  # Without staleIfOffline — throws on network failure after TTL
  getVehicle(id: ID!): Vehicle! @glCache(ttl: 120)
}
```

## Custom cache store

The default cache store is `InMemoryGraphLinkCacheStore`. It is an in-process, non-persistent LRU map. For most apps this is sufficient. If you need persistence, cross-process sharing, or custom eviction, implement the `GraphLinkCacheStore` interface:

```java title="GraphLinkCacheStore interface (generated)"
public interface GraphLinkCacheStore {
    // Store an entry with its TTL (in seconds) and tags
    void set(String key, Object value, int ttl, List<String> tags);

    // Retrieve a cached entry, or null if expired/absent
    Object get(String key);

    // Evict all entries matching any of the given tags
    void invalidate(List<String> tags);

    // Evict all entries in the store
    void invalidateAll();
}
```

Examples of custom implementations you might write:

- **SharedPreferences (Flutter)** — persist cache across app restarts on mobile
- **Redis-backed (Java)** — share cache across multiple service instances
- **Encrypted store** — encrypt sensitive data at rest on device
- **Size-limited LRU** — evict least-recently-used entries when a size cap is reached

Pass the custom store as the last argument to the client constructor:

=== "Dart"

    ```dart
    final client = GraphLinkClient(
      graphLinkAdapter,
      SimpleWebSocketAdapter('ws://localhost:8080/graphql'),
      MyCustomCacheStore(), // implements GraphLinkCacheStore
    );
    ```

=== "Java"

    ```java
    GraphLinkClient client = new GraphLinkClient(
        adapter, encoder, decoder,
        new MyRedisCacheStore(redisClient) // implements GraphLinkCacheStore
    );
    ```

## Dart usage — full cache flow

```dart title="Cache flow in Dart"
// 1. First call — cache miss, hits the server
//    Result stored with key=hash("getVehicle"+"42"), ttl=120s, tags=["vehicles"]
final res1 = await client.queries.getVehicle(id: '42');
print(res1.getVehicle.brand); // Toyota — from server

// 2. Second call within 120s — cache hit, no network request
final res2 = await client.queries.getVehicle(id: '42');
print(res2.getVehicle.brand); // Toyota — from cache

// 3. Different ID — separate cache entry
final res3 = await client.queries.getVehicle(id: '99');
print(res3.getVehicle.brand); // Honda — from server (different cache key)

// 4. Mutation — @glCacheInvalidate(tags: ["vehicles"]) evicts all "vehicles" entries
await client.mutations.addVehicle(
  input: AddVehicleInput(brand: 'Ford', model: 'Focus', year: 2024, fuelType: FuelType.GASOLINE),
);

// 5. After mutation — cache miss again for all "vehicles" entries
final res5 = await client.queries.getVehicle(id: '42');
print(res5.getVehicle.brand); // Toyota — from server again (cache was cleared)
```

## Java usage — full cache flow

```java title="Cache flow in Java"
// 1. First call — cache miss, hits the server
GetVehicleResponse res1 = client.queries.getVehicle("42");
System.out.println(res1.getGetVehicle().getBrand()); // Toyota — from server

// 2. Second call within 120s — cache hit, no network
GetVehicleResponse res2 = client.queries.getVehicle("42");
System.out.println(res2.getGetVehicle().getBrand()); // Toyota — from cache

// 3. List query — its own cache entry (ttl=60, tags=["vehicles"])
ListVehiclesResponse list1 = client.queries.listVehicles();
System.out.println(list1.getListVehicles().size()); // 3 — from server

// 4. Mutation — evicts all "vehicles" cache entries
client.mutations.addVehicle(
    AddVehicleInput.builder()
        .brand("Ford").model("Focus").year(2024)
        .fuelType(FuelType.GASOLINE).build()
);

// 5. After mutation — getVehicle("42") and listVehicles() both miss cache
GetVehicleResponse res5 = client.queries.getVehicle("42");
System.out.println(res5.getGetVehicle().getBrand()); // Toyota — from server again

ListVehiclesResponse list2 = client.queries.listVehicles();
System.out.println(list2.getListVehicles().size()); // 4 — from server (includes new Ford)
```
