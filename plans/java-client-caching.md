# Plan: Java Client Cache Generator

## Overview

Add a Java client generator that mirrors the Dart implementation — same directive-based caching,
same granular partial-query execution, same tag invalidation, and `staleIfOffline` support from day one.

The generated Java client targets Android/JVM with no external dependencies beyond the JSON library
already in the project (Jackson or Gson — configurable via `config.json`).

Java is multi-threaded, so all network and cache calls are **blocking** — no futures or async wrappers
needed. The adapter simply calls the network on the calling thread and returns a `String`.

---

## Directive Support

Same directives as the Dart client — no schema changes required:

```graphql
getCar(id: ID!): Car! @glCache(ttl: 60, tags: ["cars"], staleIfOffline: true)
createCar(input: CreateCarInput!): Car! @glCacheInvalidate(tags: ["cars"])
```

---

## Generated Class Overview

### `GraphLinkCacheStore` (interface)

```java
public interface GraphLinkCacheStore {
    void set(String key, String value);
    String get(String key);
    void invalidate(String key);
    void invalidateAll();
}
```

### `InMemoryGraphLinkCacheStore`

Default implementation backed by `ConcurrentHashMap<String, String>`.

```java
public class InMemoryGraphLinkCacheStore implements GraphLinkCacheStore {
    private final Map<String, String> store = new ConcurrentHashMap<>();

    public void set(String key, String value) { store.put(key, value); }
    public String get(String key) { return store.get(key); }
    public void invalidate(String key) { store.remove(key); }
    public void invalidateAll() { store.clear(); }
}
```

### `GraphLinkCacheEntry`

```java
class GraphLinkCacheEntry {
    final String data;
    final long expiry;
    final boolean stale;

    GraphLinkCacheEntry(String data, long expiry) { // stale = false
        this.data = data;
        this.expiry = expiry;
        this.stale = false;
    }

    private GraphLinkCacheEntry(String data, long expiry, boolean stale) { ... }

    static GraphLinkCacheEntry fromJson(Map<String, Object> json) { ... }
    Map<String, Object> toJson() { ... } // does NOT include stale
    String encode() { ... }
    boolean isExpired() { return System.currentTimeMillis() > expiry; }
    GraphLinkCacheEntry asStale() { return new GraphLinkCacheEntry(data, expiry, true); }
}
```

### `GraphLinkPartialQuery`

```java
class GraphLinkPartialQuery {
    final String query;
    final Map<String, Object> variables;
    final int ttl;
    final List<String> tags;
    final String operationName;
    final String elementKey;
    final Set<String> fragmentNames;
    final List<String> argumentDeclarations;
    final boolean staleIfOffline;
    final String cacheKey; // null when ttl == 0

    // FNV-1a hash — same algorithm as Dart
    static String computeCacheKey(String operationName, Map<String, Object> variables) { ... }
}
```

### `GraphLinkTagEntry`

```java
class GraphLinkTagEntry {
    Set<String> keys = new HashSet<>();
    static GraphLinkTagEntry decode(String raw) { ... }
    String encode() { ... }
    void add(String key) { ... }
    void remove(String key) { ... }
}
```

---

## HTTP Adapter Interface

A single-method functional interface — easy to implement with Retrofit, OkHttp, or any HTTP client:

```java
@FunctionalInterface
public interface GraphLinkAdapter {
    String execute(String payload);
}
```

Retrofit (synchronous) example:
```java
GraphLinkClient client = new GraphLinkClient(
    payload -> retrofitService.query(payload).execute().body(),
    null
);
```

---

## `ResolverBase` (generated base class)

Holds shared infrastructure. Tag operations use `synchronized` on a per-tag lock object to be
thread-safe without blocking unrelated tags.

```java
abstract class ResolverBase {
    final Map<String, String> fragmentMap;
    final GraphLinkCacheStore store;
    final Map<String, Object> tagLocks; // one lock object per tag

    GraphLinkCacheEntry getFromCache(String key, List<String> tags, boolean staleIfOffline) {
        String result = store.get(key);
        if (result == null) return null;
        var entry = GraphLinkCacheEntry.fromJson(parseJson(result));
        if (entry.isExpired()) {
            if (staleIfOffline) return entry.asStale();
            store.invalidate(key);
            if (!tags.isEmpty()) removeKeyFromTags(key, tags);
            return null;
        }
        return entry;
    }

    void invalidateByTags(List<String> tags) {
        for (var tag : tags) {
            synchronized (tagLocks.get(tag)) {
                String data = store.get(tagKeyPrefix + tag);
                if (data != null) {
                    var entry = GraphLinkTagEntry.decode(data);
                    for (var key : entry.keys) store.invalidate(key);
                    store.invalidate(tagKeyPrefix + tag);
                }
            }
        }
    }

    void addKeyToTags(String key, List<String> tags) { ... }    // same pattern
    void removeKeyFromTags(String key, List<String> tags) { ... } // same pattern
}
```

---

## Generated Query Method Shape

```java
public GetCarResponse getCar(String id) {
    final var variables = new HashMap<String, Object>();
    variables.put("id", id);

    final var partialQueries = List.of(
        new GraphLinkPartialQuery(
            "getCar(id: $id){...}", "getCar__getCar",
            List.of("cars"), 60, "getCar",
            Set.of("_all_fields_Car"), List.of("$id: ID!"),
            Map.of("id", variables.get("id")),
            false  // staleIfOffline
        )
    );

    final var responseMap = new HashMap<String, Object>();
    final var staleData   = new HashMap<String, Object>();

    // 1. Cache lookups
    for (var q : partialQueries) {
        if (q.ttl == 0) continue;
        var entry = getFromCache(q.cacheKey, q.tags, q.staleIfOffline);
        if (entry == null) continue;
        if (entry.stale) staleData.put(q.elementKey, parseJson(entry.data));
        else             responseMap.put(q.elementKey, parseJson(entry.data));
    }

    // 2. All cached — return immediately
    var remaining = partialQueries.stream()
        .filter(q -> !responseMap.containsKey(q.elementKey))
        .collect(toList());
    if (remaining.isEmpty()) return GetCarResponse.fromJson(responseMap);

    // 3. Partial network fetch
    var payload = buildPayload(remaining, operationName, "");
    try {
        var responseText = getFromSource(payload);
        return parseToObjectAndCache(responseText, responseMap, GetCarResponse::fromJson, remaining);
    } catch (Exception ex) {
        // 4. staleIfOffline fallback
        responseMap.putAll(staleData);
        long stillMissing = partialQueries.stream()
            .filter(q -> !responseMap.containsKey(q.elementKey))
            .count();
        if (stillMissing > 0) throw ex;
        return GetCarResponse.fromJson(responseMap);
    }
}
```

---

## `parseToObjectAndCache`

```java
<T> T parseToObjectAndCache(
    String data,
    Map<String, Object> cachedResponse,
    Function<Map<String, Object>, T> parser,
    List<GraphLinkPartialQuery> remainingQueries
) {
    var result = parseJson(data);
    if (result.containsKey("errors")) throw new GraphLinkException(result.get("errors"));
    var dataMap = (Map<String, Object>) result.get("data");
    for (var q : remainingQueries) {
        if (q.ttl > 0 && dataMap.get(q.elementKey) != null) {
            var entry = new GraphLinkCacheEntry(
                encodeJson(dataMap.get(q.elementKey)),
                System.currentTimeMillis() + q.ttl * 1000L
            );
            store.set(q.cacheKey, entry.encode());
            if (!q.tags.isEmpty()) addKeyToTags(q.cacheKey, q.tags);
        }
    }
    return parser.apply(dataMap);
}
```

---

## `GraphLinkClient` (top-level generated class)

```java
public class GraphLinkClient {
    public final GraphLinkQueries queries;
    public final GraphLinkMutations mutations;
    public final GraphLinkCacheStore store;

    public GraphLinkClient(GraphLinkAdapter adapter, GraphLinkCacheStore store) {
        this.store = store != null ? store : new InMemoryGraphLinkCacheStore();
        var tagLocks = new HashMap<String, Object>();
        for (var tag : ALL_TAGS) tagLocks.put(tag, new Object());
        var fragments = buildFragmentMap();
        this.queries   = new GraphLinkQueries(adapter, fragments, this.store, tagLocks);
        this.mutations = new GraphLinkMutations(adapter, fragments, this.store, tagLocks);
    }
}
```

---

## New Generator Files

```
lib/src/serializers/client_serializers/java_client_serializer.dart
lib/src/cache_store_java.dart   // Java template strings (equivalent of cache_store_dart.dart)
lib/src/code_gen_utils_java.dart // Java-flavoured code gen helpers
```

`JavaClientSerializer` mirrors `DartClientSerializer`:
- `generateClient(String importPrefix)` — top-level entry point
- `queryToMethod(GLQueryDefinition)` — generates the blocking query method
- `mutationToMethod(GLQueryDefinition)` — generates mutation method with tag invalidation
- `serialzePartialQuery(DividedQuery)` — emits `new GraphLinkPartialQuery(...)` constructor call
- Reuses `gl_grammar_cache_extension.dart` for `staleIfOffline` parsing (already done)

---

## config.json Changes

```json
{
  "clientConfig": {
    "targetLanguage": "java",
    "jsonLibrary": "jackson",
    "packageName": "com.example.generated"
  }
}
```

---

## Behaviour Rules (identical to Dart)

| Situation | staleIfOffline = false | staleIfOffline = true |
|---|---|---|
| Cache fresh | Return cached | Return cached |
| Cache expired, network ok | Fetch, update cache | Fetch, update cache |
| Cache expired, network fails | Throw | Return stale data |
| Cache expired, server returns GraphQL errors | Throw | Throw |
| No cache, network fails | Throw | Throw |

---

## What Does NOT Change

- `gl_grammar_cache_extension.dart` — `staleIfOffline` parsing already implemented
- `DividedQuery` model — already carries `staleIfOffline`
- Directive definitions — already support `staleIfOffline`
- Tag invalidation logic — identical semantics

---

## What Needs to Be Built

1. `JavaClientSerializer` — main generator class
2. `cache_store_java.dart` — Java template strings
3. `JavaCodeGenUtils` — Java code gen helpers (class/method/loop/if emit, no async wrappers)
4. Wire up `targetLanguage: "java"` in the serializer factory
