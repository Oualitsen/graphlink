# Backend (Spring Server) Cache — Feature Plan

## Overview

Reuse the existing `@glCache` / `@glCacheInvalidate` / `@glNoCache` directives — already
consumed by the client generators — to also drive **server-side response caching** at the
generated Spring GraphQL controller layer. Same directive vocabulary, same TTL/tag model,
same partial-resolution idea (some resolvers served from cache, others hit the service
layer) — just moved one hop downstream, from the generated client to the generated
controller.

This is a deliberate step toward a GraphQL gateway: field-level cached resolution with
tag invalidation is the core value-add a gateway provides. Building it into the
single-service backend first, with a swappable store, gets there without committing to
gateway architecture yet.

Today `gl_grammar_cache_extension.dart` only validates these directives (no cache/invalidate
on mutations/subscriptions, TTL required, tag syntax) and only the **client** serializers
(`dart`, `java`, `kotlin` — TS partially) consume them to generate `GraphLinkResolverBase`,
`GraphLinkCacheStore`, `GraphLinkPartialQuery`, etc. The server generators
(`java_spring_server_serializer.dart`, `java_spring_controller_serializer.dart`,
`kotlin_spring_*`, `jvm_spring_*_base.dart`, `server_generator.dart`) currently have **zero**
awareness of these directives — this is greenfield on the server side.

---

## Goals

- Generate a server-side cache layer at the **controller** boundary (`@QueryMapping` /
  `@SchemaMapping` / `@BatchMapping` methods), mirroring where JSON translation already
  happens — no cache-aware code should leak into the generated `*Service` interfaces or
  hand-written `*ServiceImpl` classes.
- Reuse the same TTL + static-tag model already validated client-side. No new directive
  syntax for the common case.
- Support a **configurable, per-tenant/per-context cache key** — extra key material beyond
  the resolver's GraphQL arguments (e.g. current user/tenant), sourced from a
  user-implemented hook, not from schema-declared params. Null/absent extra params
  collapse to `""` so the entry is shared across all callers when no scoping is needed —
  this is what makes public/global data cacheable without extra ceremony while still
  allowing precise per-tenant scoping where required.
- Generate an in-memory store by default (matches client parity) and a **Redis-backed
  store** as an opt-in generated implementation, since a horizontally-scaled backend can't
  rely on in-memory state for either the cache or the tag index.
- Generate a typed, per-cached-resolver invalidation twin (`invalidate<OperationName>(args...)`)
  exposed on an injectable "cache admin" surface — same shape as the client-side
  `client.cache.invalidate<OperationName>(...)` from `cache-control.md` (planned, not yet
  built) — plus tag-based bulk invalidation for edge cases the generated mutation flow
  doesn't cover (external events, admin tooling).
- Tie automatic invalidation to a well-defined **service-layer success contract**, not to
  the controller's HTTP/GraphQL envelope — see Open Questions, this is intentionally not
  fully resolved yet.

## Non-Goals (for now)

- **Dynamic/argument-interpolated tags** (`"user-detail-$id"`, see `dynamic-tags-caching.md`).
  Explicitly rejected in favor of per-resolver invalidate twins — tags stay static strings,
  full stop. Precise single-entry invalidation is the twin method's job; tags remain a
  coarse, human-declared grouping mechanism.
- Federation / true multi-service gateway. This plan caches one generated service's own
  resolvers; it does not aggregate across services.
- Caching nested `@SchemaMapping`/`@BatchMapping` field resolvers (e.g. `Author.articles`).
  `@glCache` today is only valid on root `Query` fields (validated in
  `gl_grammar_cache_extension.dart`); this plan keeps that restriction. Extending caching
  to field resolvers is a separate, larger design (batched cache lookups inside a
  `@BatchMapping`) — noted as future work, not in scope here.
- Response-level HTTP caching (`Cache-Control` headers, CDN caching) — this is
  application-level cache-store caching, same as the client, not an HTTP semantics change.

---

## Directive Reuse — No New Directives for the Core Case

`@glCache(ttl: "…", tags: […], staleIfOffline: …)` and `@glCacheInvalidate(tags: […], all: …)`
already exist and are already fully validated (`lib/src/model/built_in_dirctive_definitions.dart`
lines 89–95; `gl_grammar_cache_extension.dart`). Server generation consumes the *same*
parsed directive data the client generators already read off `GLQueryDefinition`/
`GLQueryElement` — no schema changes needed for TTL, static tags, or `staleIfOffline`.

`staleIfOffline` server-side needs its own definition of "offline" — likely "the service
call threw / the downstream dependency it talks to is unreachable" rather than a network
adapter failing, since the backend *is* the network boundary the client was falling back
around. Worth confirming this reads sensibly once real service implementations exist
(most generated `*ServiceImpl` here are in-memory/mocked, so "offline" has no natural
meaning yet in the integration-test fixtures).

---

## Architecture

### Where the cache hooks in

Every generated `*ServiceController` method already looks like:

```java
@QueryMapping()
public CompletableFuture<Map<String, Object>> getAuthor(@Argument(name = "id") String id) {
   return CompletableFuture.supplyAsync(() ->
       authorService.getAuthor(id) == null ? null : authorService.getAuthor(id).toJson());
}
```

Cache resolution wraps this `CompletableFuture` stage — check cache before
`supplyAsync`, write to cache in a `.thenApply`, same shape as the client's
`executeCached`/`parseToObjectAndCache` pair, just operating on a single resolver instead
of a batch of partial queries (root-query-only scope makes this simpler than the client's
multi-resolver-per-request case). The `*ServiceImpl` is never touched or made
cache-aware — this preserves the existing "interface = contract, controller = glue, impl
= logic" split (`ARCHITECTURE.md` / the earlier conversation in this session).

**This lines up cleanly with `controller-mapification-summary.md` (already shipped):**
controllers already return `Map<String, Object>`/`List<Map<...>>` (`.toJson()` output),
not typed service objects — the service layer stays typed, only the controller boundary
is map-ified. That means the value this plan caches is *already* the same JSON-shaped
`Map` the client wraps as `{"__gl_v__": ...}` — no extra serialization step needed at the
cache-write site, and the cache sits at exactly the layer that already does this
typed-to-Map conversion. Good confirmation the hook point (controller, not service) is
right, not just convenient.

### Cache key composition

Client-side: `computeCacheKey(operationName, variables)`. Server-side needs one more
input: **extra context params** that aren't part of the GraphQL arguments at all (tenant
ID, authenticated user, locale — whatever the schema author decides matters). Proposed
shape:

```java
public interface GraphLinkCacheKeyContext {
    Map<String, String> extraKeyParams(String operationName);
}
```

A user-implemented Spring bean the generated controller layer calls once per cached
request; return values get folded into `computeCacheKey` alongside the resolver's own
arguments, same FNV-1a hash, same sorted-map-for-determinism approach already used
client-side (`cache_store_java.dart`, `GraphLinkPartialQuery.computeCacheKey`). Missing
key → `""`, matching the "empty string shares the entry with everyone" rule agreed on
earlier — this is what lets the same mechanism serve both fully public data and
tenant-scoped data without two separate code paths.

### Store: in-memory default, generated Redis implementation

`GraphLinkCacheStore` (the interface) is unchanged — `set`/`get`/`invalidate`/
`invalidateAll`, all `String` keys and values, exactly as it already exists for every
client language. A generated `RedisGraphLinkCacheStore` becomes a second implementation:

- `String` values map directly to Redis `String` type — `SET key value PX <ttlMillis>`.
  Redis-native TTL replaces the manually-tracked `expiry` field in `GraphLinkCacheEntry`
  for this store (the entry wrapper can shrink to just `data` when backed by Redis, though
  keeping the shared `GraphLinkCacheEntry` shape across stores is simpler to reason about
  — worth deciding when implementing rather than now).
- `GraphLinkTagEntry` (a set of keys per tag) maps to a Redis `Set`
  (`SADD gl:tag:<tag> key1 key2`, `SMEMBERS`/`SREM`), which also removes the need for the
  hand-rolled per-tag `ReentrantLock` — Redis set operations are atomic, so the lock map
  in `GraphLinkResolverBase`/the server equivalent isn't needed for this store.
- Key namespacing: `gl:cache:<hash>` / `gl:tag:<tag>` prefixes, per Redis convention (flat
  keyspace, colon-delimited namespacing) so `SCAN`/`KEYS gl:cache:*` works for debugging.
- This is a **new runtime dependency** (a Redis client — Lettuce or Jedis) for servers that
  opt into it. That's a departure from "generated code has zero runtime dependency on
  GraphLink," but that principle is about not depending on the *glink tool*, not about
  zero third-party libraries — generated Spring servers already depend on Spring itself.
  Gate it behind config (`cache.store: "memory" | "redis"`) so it's opt-in, matching how
  `SpringServerConfig` already gates other generation choices.

### Generated invalidation surface

One `invalidate<OperationName>(sameArgsAsQuery...)` per `@glCache`-annotated query,
computing the same key internally (mirrors `cache-control.md`'s already-planned client-side
`GraphLinkCacheControl`, not yet built for any client language) — plus `invalidateTag(tag)`
and `invalidateAll()` for the coarse/edge-case path discussed in this session. Exposed as
an injectable Spring bean (e.g. `GraphLinkCacheAdmin`) so hand-written code (webhook
handlers, admin endpoints, anything outside the generated mutation flow) can call it
directly — this is the answer to "the user will access it and can invalidate for things
he wants on edge cases."

### Automatic invalidation on mutation success

`@glCacheInvalidate` on a mutation fires tag invalidation after the service call
completes without error — same "invalidate after success, never on error" rule already
documented in `graphql-client-caching.md`. The precise definition of "success" for the
generated `*ServiceImpl` contract is the main open design question below.

---

## Relationship to Existing Plans

- **`cache-control.md`** — describes the client-side `GraphLinkCacheControl` class
  (per-query invalidate twins + `invalidateByTags` + `invalidateAll`). Planned, not yet
  implemented in any client language. This backend plan is the server-side mirror of the
  same idea, and should probably share naming/shape conventions with it once
  `cache-control.md` is actually built — implement client-side first, since server-side
  cache-key composition is more involved (extra context params, pluggable stores) and
  benefits from the client's simpler version existing as a reference.
- **`dynamic-tags-caching.md`** — proposes argument-interpolated tags (`"user-detail-$id"`)
  as the surgical-invalidation mechanism. **Explicitly rejected in this conversation** in
  favor of per-resolver invalidate twins. Note: `graphql-client-caching.md`'s "Open
  Questions" section currently says targeted invalidation is "Resolved" via dynamic tags —
  that resolution is now superseded and should be corrected when `cache-control.md` lands,
  to avoid the two plans contradicting each other.
- **`ttl-units.md`**, **`stale-if-offline.md`** — already-implemented directive behavior
  this plan reuses as-is.
- **`java-client-caching.md`** — the client-side Java cache architecture
  (`GraphLinkResolverBase`, `GraphLinkPartialQuery`, `GraphLinkCacheStore`) this plan's
  server-side classes are modeled after, confirmed against the actual generated output in
  `integration_tests/java_client_tests/client-app/.../generated/client/` during this
  session.
- **`controller-mapification-summary.md`** (shipped) — controllers already return
  `.toJson()`-mapified `Map`/`List<Map>`, service layer stays typed. Confirms the
  controller is the right cache hook point: the cache stores exactly the shape the
  controller already produces, no new conversion step. Batch mappings return `Map<K,V>`
  (keyed by entity, not by `elementKey`) — this plan explicitly excludes
  `@SchemaMapping`/`@BatchMapping` field resolvers from caching (see Non-Goals), so the
  batch-return-shape quirk noted in that summary doesn't block this plan, but it's the
  first thing to re-examine if field-resolver caching is ever added later.
- **`hexagonal-server-layout.md`** (opt-in, Kotlin Spring 5.1) — relocates generated
  controllers/services from by-kind packages (`controllers/`, `services/`) into
  `adapter/in/graphql/` and `port/in/`. Whatever cache-admin/store classes this plan
  generates need a package placement that works under **both** layouts — likely a
  layout-neutral location (e.g. alongside `config/`, which hexagonal mode leaves
  untouched) rather than assuming the legacy `controllers/`-adjacent path. Not resolved
  here; added to Open Questions below.

---

## Open Questions (unresolved — for later review)

1. **How exactly is `GraphLinkCacheKeyContext` sourced per request?** Spring request scope,
   GraphQL context propagation (`DataFetchingEnvironment`/`graphql.GraphQLContext`), or
   something simpler? This determines whether the hook can even see things like the
   authenticated principal without extra wiring in `main.dart`/generator config.
2. **Precise definition of mutation "success" for auto-invalidation.** Session leaned
   toward "the service method didn't throw," but flagged two unresolved gaps:
   - Non-throwing `null`/no-op returns (e.g. delete-by-id matching nothing) shouldn't
     necessarily trigger invalidation — needs either a dedicated not-found exception
     convention or a richer return contract (`wasModified` flag) so "didn't throw" reliably
     means "a write happened."
   - Batch/bulk mutations (`BulkCreateService`-style) that swallow partial failures instead
     of throwing — "no throw" doesn't tell you *which* items actually wrote, so tag
     invalidation would be all-or-nothing even when only some items succeeded.
3. **Is invalidation triggered per-field or per-envelope** when a GraphQL response has
   partial data + partial errors? Session position: per-field, tied to whether that
   specific resolver's service call threw — needs to be nailed down against how Spring
   GraphQL actually surfaces partial failures before implementing.
4. **Redis entry shape** — keep the shared `GraphLinkCacheEntry` (with manually-tracked
   `expiry`) for store-implementation consistency, or let Redis-backed entries drop
   `expiry` in favor of native `PX` TTL? Affects whether `GraphLinkCacheEntry` needs to
   stay store-agnostic or can specialize.
5. **Should the Redis client (Lettuce vs Jedis) be a fixed choice or configurable**, given
   it's the first real runtime dependency introduced into generated server code by this
   feature?
6. **Naming/shape of the generated invalidation bean** — one aggregate `GraphLinkCacheAdmin`
   (mirrors the client's single `GraphLinkCacheControl`), or split per generated
   `*ServiceController` group (`AuthorCacheAdmin`, `TeamCacheAdmin`, …) matching how
   controllers/services are already split per type? Not decided.
7. **Config surface** — new keys on `SpringServerConfig` (`cache.store`, `cache.redis.*`)
   vs. a separate top-level cache config block. Follow existing `SpringServerConfig`
   `fromJson` conventions once shape is settled.
8. **Package placement under `hexagonal-server-layout.md`'s opt-in layout.** Generated
   cache classes (store implementations, `GraphLinkCacheAdmin`, the key-context hook)
   need one placement that's valid whether the server uses the legacy by-kind layout or
   the hexagonal `port/`/`adapter/` layout — not decided which, or whether this plan
   should just ship after hexagonal layout lands to avoid building on a package structure
   about to change.
