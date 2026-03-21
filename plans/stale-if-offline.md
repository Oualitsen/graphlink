# Plan: staleIfOffline Cache Fallback

## Overview

When a cached entry is expired and the network is unreachable, fall back to the stale
cached value instead of throwing. Only applies to queries — mutations are unaffected.

---

## Directive Change

Add `staleIfOffline` argument to `@glCache`:

```graphql
getCar(id: ID!): Car! @glCache(ttl: 3600, tags: ["cars"], staleIfOffline: true)
```

Can also be set globally via generator config as a default for all cached queries.

---

## Behaviour Rules

| Situation | staleIfOffline = false (default) | staleIfOffline = true |
|---|---|---|
| Cache fresh | Return cached | Return cached |
| Cache expired, network ok | Fetch from server, update cache | Fetch from server, update cache |
| Cache expired, network fails | Throw | Return stale data |
| Cache expired, server returns GraphQL errors | Throw | Throw (do not return stale) |
| No cache, network fails | Throw | Throw (nothing to fall back to) |

---

## What Needs to Change

### 1. Schema / Directive Definition
- Add `staleIfOffline: Boolean` argument to the `@glCache` directive definition

### 2. `GLCacheDefinition` model
- Add `bool staleIfOffline` field

### 3. `gl_grammar_cache_extension.dart`
- Read `staleIfOffline` from the directive and populate `GLCacheDefinition`

### 4. Code generation — `_GraphLinkPartialQuery`
- Add `staleIfOffline` field to the generated class

### 5. Code generation — query method
- Pass `staleIfOffline` value when constructing `_GraphLinkPartialQuery`

### 6. Code generation — `_getFromCache`
- When entry is expired and `staleIfOffline = true`, keep the stale data aside
  instead of discarding it, and return it tagged so the caller knows it may be stale

### 7. Code generation — query execution flow
- After cache check, if stale data was kept aside:
  - Try network call
  - On success: update cache, return fresh data
  - On network exception: return stale data
  - On GraphQL errors in response: throw as normal

---

## What Does NOT Change
- Mutation code generation — no stale fallback for writes
- Cache invalidation logic — unaffected
- TTL expiry and tag-based invalidation — unaffected
