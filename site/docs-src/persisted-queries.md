---
title: "GraphQL Persisted Queries (APQ)"
description: "Automatic Persisted Queries in every generated client: send a SHA-256 hash instead of the query, retry once on PersistedQueryNotFound, optional GET for queries, Apollo-compatible wire format."
---

# Persisted Queries (APQ)

Send a hash of the query instead of its text. Generated clients speak the Apollo **Automatic Persisted Queries** protocol, so they work with Apollo Server and any server that implements it, with no build step and no manifest.

It is available for Dart, Java (blocking, Reactor, RxJava3, Mutiny), Kotlin, TypeScript, Swift and Python, and is off by default.

## Enable it

```json title="glink.json"
{
  "clientConfig": {
    "typescript": {
      "persistedQueries": "apq",
      "persistedQueriesUseGet": true
    }
  }
}
```

| Option | Values | Default | Description |
|---|---|---|---|
| `persistedQueries` | `false` \| `"apq"` | `false` | `"apq"` hashes long operations and retries on a miss. Any other value is a generation error. With `false` the generated output is unchanged. |
| `persistedQueriesUseGet` | `boolean` | `false` | Send hash-only **queries** with HTTP GET so CDNs and browsers can cache them. Requires `persistedQueries: "apq"`; setting it alone is an error. |

Both options exist under `clientConfig.dart`, `java`, `typescript`, `kotlin`, `swift` and `python`.

## How it works

1. The client computes the SHA-256 of the exact query string it is about to send, fragments included.
2. It sends the operation name, variables and `extensions.persistedQuery` with the hash, and no query text.
3. If the server answers `PersistedQueryNotFound`, the client sends the same request once more with the query text added. That second request makes the server register the query.
4. Every later call is hash-only again.

```json title="hash-only request"
{
  "operationName": "GetUser",
  "variables": { "id": "1" },
  "extensions": { "persistedQuery": { "version": 1, "sha256Hash": "<hash>" } }
}
```

The retry is invisible to your code: `client.queries.getUser(...)` returns the data as usual.

### Rules worth knowing

- **Short operations are not hashed.** Below about 144 characters the hash payload is bigger than the query, so the normal request is sent. There is no option for this.
- **The client keeps no registration state.** Every call starts hash-only, so a server restart or cache eviction costs one extra request and nothing else.
- **Retries are strict.** The query text is re-sent only on `PersistedQueryNotFound`. Timeouts, 5xx responses and other errors are never retried, so a mutation cannot run twice because of APQ.
- **`PersistedQueryNotSupported`** means the server has APQ switched off. The client sends the full query and stops hashing for the rest of that client's life.
- **Mutations always use POST,** hash-only first and then the retry. Subscriptions and file uploads are unchanged.
- **`@glCache` partial queries:** the merged query that is actually sent is hashed as a whole.
- **`@glCaptureErrors`:** a `PersistedQueryNotFound` on the first attempt is never surfaced as a captured error.

## GET for queries

With `persistedQueriesUseGet`, hash-only queries go out as

```
GET /graphql?operationName=GetUser&variables={"id":"1"}&extensions={"persistedQuery":{...}}
```

Variables and extensions are JSON in the URL and are percent-encoded by the generated adapter. The retry that registers the query is always a **POST**, because a full query may not fit in a URL.

If the server refuses GET (typically a 405), the GET adapter throws `GraphLinkGetNotSupported`. The client then sends that request as a POST and uses POST from then on. Any other error from the GET adapter propagates unchanged, because sending the request twice would hide real network failures.

## Adapters

The POST adapter is unchanged, but it now receives payloads **without a `query` field** for persisted operations. An adapter that forwards the body as-is keeps working; one that reads `query` must be updated.

With `persistedQueriesUseGet` the client also needs a **GET adapter** with the same signature as the POST adapter. It receives the JSON payload and turns `operationName`, `variables` and `extensions` into the query string.

| Language | Default GET adapter | Custom GET adapter |
|---|---|---|
| Dart | `GraphLinkClient.withHttp(...)` (http) or the Dio adapter | `getAdapter:` constructor argument, right after `adapter` |
| TypeScript | `createFetchGetAdapter(url)` / `createAxiosGetAdapter(url)` | second constructor argument |
| Kotlin | `DefaultGraphLinkGetAdapter` (OkHttp) | `getAdapter` argument, right after `adapter` |
| Java | `DefaultGraphLinkGetAdapter` for the JDK and OkHttp transports; the convenience constructor wires it | `getAdapter` argument, right after `adapter` |
| Swift | `DefaultGraphLinkURLSessionGetAdapter` | `getAdapter:` argument, right after `adapter:` |
| Python | `GraphLinkHttpxAdapter.get_call` (wired by `GraphLinkClient.with_http`) | `get_adapter=` keyword argument |

If your adapter cannot do GET, throw `GraphLinkGetNotSupported` from it. If you use the convenience constructors (`withHttp` and friends) both adapters are wired for you.

## Server side

The server must implement APQ: look up the hash, run the stored query, and register a query when it receives text with a matching hash.

**Apollo Server / Express** supports APQ out of the box. Keep its cache bounded.

**Spring for GraphQL** has no turnkey support. A hash-only request arrives as a placeholder document named `PersistedQueryMarker` and fails with a syntax error, so you need a `WebGraphQlInterceptor` that:

1. reads `extensions.persistedQuery.sha256Hash`;
2. for a hash-only request, looks the hash up and replaces the execution input's query, or answers `PersistedQueryNotFound` (`extensions.code` = `PERSISTED_QUERY_NOT_FOUND`);
3. for a request with text and hash, checks that SHA-256 of the text equals the hash, stores it, and continues.

Spring GraphQL only accepts POST on `/graphql`. To use `persistedQueriesUseGet` you also need a filter that turns `GET /graphql?...` into the POST the handler understands, and you should reject mutations over GET with 405. A reference implementation lives in `integration_tests/persisted_queries/real/spring_persisted_queries_server` in the GraphLink repository.

!!! warning "Bound the server cache"
    Any anonymous client can register any query. An unbounded store is a memory-exhaustion risk, so use a size-limited (LRU) cache with a TTL, and consider registering only for authenticated or allow-listed callers. The test server in the repository uses an unbounded map and is not meant for production.

## Not included yet

- **Manifest / safelist mode,** where the server rejects unknown queries and every operation is registered at build time.
- **Subscriptions over WebSocket.**

## Related

- [Configuration](configuration.md) — every client option
- [Caching](caching.md) — `@glCache` and how it combines with hashing
