# integration_tests/real: hardening proposals

Date: 2026-11-16. Read-only audit: no test was run, all suites are assumed green.

## Where the suites stand

- GraphQL (`schema_real/`, Spring server): all 110 root operations and the named operations in
  `custom_query.graphql` are called by all 7 languages (Dart, TS, Java, Kotlin, Swift, Python, Go).
- REST (`schema_rest/`, `rest_server/server.py`): all 90 operations are called by all 7 languages. Swift skips the
  strict twins by design.
- Faults (`fault_server/`): about 60 HTTP faults, 12 of them GraphQL-shaped, run from every REST real package.
- Cache-hit counting and `staleIfOffline` are covered by the mock suites, so they are left out here.

The proposals below are ordered by value. Each says what to add to the server/schema and what each client asserts.

---

## 1. An error response is never cached (GraphQL) — DONE

Added in all 7 clients: `cachedFlaky` / `cachedFlakyNullable` fail on the first call per id, `cachedFlakyCalls(id)` exposes the server counter. Tests: `cache_errors_test.dart`, `cache-errors.test.ts`, `CacheErrorsTest.{java,kt,swift}`, `test_cache_errors.py`, `cache_errors_test.go`. All pass.

Failures are not cached, but nothing on the GraphQL side proves it: `failingAttachments` has no `@glCache`.
REST has `cachedBad`.

- Schema: `cachedFlaky(id: ID!): User @glCache(ttl: "1m", tags: ["users"])`.
- Server: a per-id call counter; the first call for an id throws, the next ones return the user.
- Assert, in every language with a counting adapter (or the server counter exposed through a `cachedFlakyCalls(id)` query):
  1. call 1 fails;
  2. call 2 succeeds and reaches the server (counter = 2);
  3. call 3 is served from the cache (counter still 2).
- Variant: a 200 response with `errors` and `data: null` must not be cached either (`errorPolicy`-style partial
  failures are the case users hit most).

## 2. Headers and auth (HTTP and WebSocket) — DONE

Added `echoHeader`, `whoAmI`, `secureTicks`, `secureTickStarts` (server: `AuthInterceptor`, `AuthController`). Header-provider tests for HTTP in Go, Python, Java, Kotlin, Swift (Dart and TypeScript have no generated HTTP adapter); `connection_init` token tests in all 7; rotated-token-on-reconnect test in Go, Python, TypeScript, Dart, Java, Kotlin (Swift has no reconnect suite, see #3). All pass. The original proposal follows.

No GraphQL real suite sends a header, in any language. The REST suites test headers; GraphQL `headersProvider` and the
`connection_init` payload are only covered by mocks.

- Schema/server:
  - `echoHeader(name: String!): String`: returns the request header value (Spring `@ContextValue` / a
    `WebGraphQlInterceptor` that copies headers into the context).
  - `whoAmI: String!` requiring `Authorization: Bearer <token>` (error otherwise).
  - `secureTicks(count: Int!): Int!` subscription that reads the token from the `connection_init` payload and rejects the
    connection otherwise.
- Assert:
  - `headersProvider` values reach the server, and are re-evaluated per request (rotate the token between two calls).
  - A missing token gives the language's normal error type, not a crash.
  - The WebSocket sends the auth payload on `connection_init`, and sends it again after a reconnect (a token rotated
    while disconnected must be the new one).

## 3. Reconnect edge cases — DONE

Server: `labelTicks(label, count)` (100 ms ticks, then completes), `labelTickStarts(label)` (per-label start counter, reset by a server restart) and an `Ack-Delay` entry in the `connection_init` payload that delays `connection_ack`.

Tests, one per case, in all 7 clients (own port 9930 to 9936, so the suites can run in parallel). They start and kill `real/fault_server/server.py --live` per port (it serves `labelTicks`, `secureTicks`, the `*Starts` queries, `Ack-Delay` and a ticking `counterTick` like the Spring server), not the Spring JAR, so they run in every `make test`:
`reconnect_cases_test.go`, `test_reconnect_cases.py`, `subscription-reconnect-cases.test.ts`, `subscription_reconnect_cases_test.dart`, `SubscriptionReconnectCasesTest.{java,kt}`, `ReconnectCasesTest.swift`; the older `SubscriptionReconnectTest` files (resume after halt, subscribe before the server is up, endless retries, rotated token) use the same server.
Cases: same variables on resubscribe, completed subscription not resubscribed, cancelled subscription not revived, two subscriptions on one socket both resume, restart during `connection_init` subscribes once, give-up after `maxReconnectAttempts` ends the stream with an error.
Not covered: the cancelled case in Java, because the callback API (`labelTicks(..., listener)` returns `void`) has no way to cancel a subscription.
Fixed (Swift, Python): the 5 s `connection_ack` timer kept running while the socket was down and the client was backing off, so a server that took longer than that to come back (the GitHub macOS runner, or a restart during `connection_init`) failed every open stream with "did not send connection_ack within 5 s". Both adapters now have a disconnect hook (`setDisconnectListener`, `on_disconnect`) and the handler invalidates the timer when the socket drops, like Java and Kotlin. Python also used `asyncio.wait_for` on a future shared by the first handshake and the reconnect handshake, so one timeout cancelled the other's wait; it is now a re-armable timer. `test_aServerDownLongerThanTheAckTimeoutStillResumes` / `test_a_server_down_longer_than_the_ack_timeout_still_resumes` hold the server down for 8 s. No open defects.

Client defects the tests found, all fixed in the runtime templates (`lib/src/serializers/client_serializers/<lang>/*_client_constants.dart`):

| Defect | Clients | Fix |
|---|---|---|
| Give-up is silent: when the reconnect attempts run out nothing tells the open subscriptions, so the stream hangs | Go, Python, TypeScript, Dart | Adapters expose an optional give-up hook (`SetGiveUpHandler`, `on_give_up`, `onGiveUp`); the handler fails every open subscription |
| A reconnect during `connection_init` leaves the original handshake waiting for an ack that never comes | Python, TypeScript, Dart (Go: waited out the 30 s handshake timeout) | The reconnect aborts the pending handshake and runs a fresh one; the subscribe message is sent once |
| `maxReconnectAttempts` never reached: the attempt counter was reset when the socket was created, not when it opened | Swift | Reset when the first frame arrives |

Java and Kotlin needed no change. The Kotlin cases were silently skipped at first because a `runBlocking { ... }` body ending in `assertNotNull` returns a value and JUnit ignores non-`Unit` test methods; use `runBlocking<Unit>`.

The original proposal follows.

Reconnect is only tested with `counterTick`, which takes no arguments. Swift has no reconnect test at all.

Add to the reconnect suites (`subscription_reconnect_test.*`, `SubscriptionReconnectTest`), and create Swift's:

| Case | Expectation after the server restarts |
|---|---|
| `userStatusChanged(userId: "user-2")` | Resubscribes with the **same variables** (events are for Bob) |
| `finiteTicks(count: 2)` completed before the restart | Not resubscribed; no new events |
| Subscription cancelled before the restart | Not revived |
| Two open subscriptions on one socket | Both resume, each with its own id |
| Restart during `connection_init` (before the ack) | The client retries and then subscribes once (no duplicate) |
| `maxReconnectAttempts` reached | The stream ends with an error the caller can see, not a silent hang |

## 4. Remove or implement `counterTickRestart` — DONE (removed)

Deleted from `schema_real/schema.gql`: `plans/reconnect-feature-and-tests.md` already records it as removed on purpose (the harness restarts the server from outside), the Spring schema never had it, and no test called it. The `lsof … | kill -9` port killing in the reconnect tests stays; replacing it needs a different mechanism (for example a server-side way to drop WebSocket sessions), which is not part of this item. The original note follows.

`Subscription.counterTickRestart(stopAt: Int!)` is declared in `schema_real/schema.gql` with the comment "the server
self-restarts after emitting tick stopAt", but `SubscriptionController` has no resolver and no test calls it. Either
delete it, or implement it and use it for the reconnect cases above. That would remove the `lsof … | kill -9` port
killing from the tests (fragile, and not portable to Windows).

## 5. WebSocket faults — DONE (7 targets, 6 defects fixed)

`fault_server/server.py` is HTTP only, so the subscription transport is never fed a bad server. Add a WebSocket mode
(armed like the HTTP faults: `POST /_arm?fault=<name>`), add rows to `cases.json`, and give every subscription-capable
real package a WS fault test.

| Fault | Expected client behaviour |
|---|---|
| `ws-no-ack` (never sends `connection_ack`) | Times out with an error; no subscribe is sent before the ack |
| `ws-invalid-json` frame | Error surfaced or reconnect; no crash, no hang |
| `ws-unknown-type` message | Ignored or error, connection stays usable |
| `ws-next-unknown-id` | Ignored; other subscriptions unaffected |
| `ws-next-after-complete` | Ignored; the stream stays completed |
| `ws-error-message` (`type: error` with an errors array) | That subscription fails with the server's message; others continue |
| `ws-ping` (server `ping`) | Client answers `pong` |
| close `4400` / `4401` / `4403` | No reconnect (client or auth error); error surfaced |
| close `4409` (duplicate subscriber id) | Error surfaced |
| close `4429` (too many init requests) | Not retried in a tight loop |
| close `4500` / `1011` / abrupt TCP close | Reconnect with backoff |
| binary frame | Ignored or error, no crash |

Built: `fault_server/server.py` speaks `graphql-transport-ws` (stdlib RFC 6455) and `POST /_arm?fault=ws-...&times=N` makes the next N
connections misbehave; `GET /_ws_log` lists every connection with the frames the client sent. `fault_server/ws_cases.json` is the one table
(`expect`: `value`, `error` or `settles`, plus `pong`, `noSubscribeBeforeAck`, `min/maxConnections`). Every GraphQL real package has a
`ws_faults` test on its own fault port (Dart 9940, Python 9942, TypeScript 9943, Go 9944, Swift 9945, Java 9946, Kotlin 9947), started by
`make ci`. The reactive Java flavors run the same suites; the listener-style tests (`AuthSubscriptionTest`, `WsFaultsTest`, `SubscriptionReconnectCasesTest`) are excluded in `generate_reactor_tests.dart` and have stream-based copies in `java_reactive_shared/` (`*StreamsTest`).

Fixed, in every runtime:
- **Kotlin hung forever when the server closed the socket with a close frame** (any code, 1011 and 4500 included). The adapter only handled `onClosed`, which OkHttp fires only after the app answers `onClosing`. The Java OkHttp adapter had the same gap.
- **No timeout on `connection_ack`**: the handshake now fails after 5 s and the subscription gets an error (Go already had a 30 s timeout, now 5 s).
- **Close 4400 / 4401 / 4403 / 4409** are final: no reconnect, every open subscription fails with a message naming the code (Dart, TypeScript, Python, Go and Swift reuse their give-up path, Java and Kotlin call `onFailure`). The headers provider is therefore not asked for a new token after a 4401; a client that wants that has to resubscribe itself.
- **A frame that is not JSON, or a binary frame**, is ignored (Dart, TypeScript, Python and the JVM clients).
- **Dart answers the server `ping`** from the connection, not from a subscription listener.
- **Swift keeps the server's error message** (`GraphLinkException`, like the other clients).

`KNOWN_DEFECTS` is empty in all seven tests. The reactive Java packages were run (400/401/401 tests) with stream-based copies of the three listener-style tests (fault ports 9948, 9949, 9955).

## 6. Many cached requests at the same time — DONE (1 defect fixed, in-flight coalescing added)

Server: `cachedSlow(id, delayMs)` (`@glCache`, tag `slow`; returns the id's version as it was when the request arrived, then waits), `cachedSlowCalls(id)`, `bumpSlow(id)` (`@glCacheInvalidate(tags: ["slow"])`). Tests, in all 7: `cache_concurrency_test.dart`, `cache-concurrency.test.ts`, `test_cache_concurrency.py`, `cache_concurrency_test.go`, `CacheConcurrencyTest.{java,kt,swift}`.

- Two keys at the same time make two calls: passes in all 7.
- Five identical requests at the same time used to make **five** calls. Now identical concurrent cached queries share one network call (single-flight). The in-flight key is the operation name, the sorted cache keys of the elements still to fetch and the combined epoch, so a request that starts after an invalidation never joins an earlier one. Only the network call is shared: each caller parses and caches its own copy, and a failure is shared by all joined callers (each still falls back to its own stale data). Queries with an element that has `ttl` 0 are not coalesced. Tests: `concurrent requests for the same key share one call` in all 7 languages. The three reactive Java packages coalesce too (shared `CompletableFuture` map, registered at subscription). REST cached calls coalesce too (key: operation name, arguments and epoch; the shared result is the parsed JSON). Not covered: failure sharing has no real-server test.
- A response still in flight when its tag is invalidated **is stored**: the next call is served the stale value. Failed in all 7 (`expected 1 but was 0`). Fixed in all 7 runtimes: an in-memory invalidation counter per tag plus one for `all: true` is read before the request is sent, and the cache write is skipped when it changed (the caller still gets the response). Dart, TypeScript, Python and Go keep the counters on the per-tag lock objects; Java and Kotlin keep them per cache store (the query and mutation classes do not share their lock maps); Swift passes a shared `GraphLinkEpochs` object to the query, mutation and subscription classes. All `invalidateAll` call sites (GraphQL and REST) now go through `invalidateAllEntries`. REST cached responses use the same counter before writing. Not covered: the gap between `store.set` and `addKeyToTags` is not closed.

The original proposal follows.

The runtimes have a cache lock, but no real test sends identical cached requests at the same time.

- Assert: 5 simultaneous `getCachedUser("user-1")` calls make **1** network call and all 5 get the same data. Also check
  `getCachedUser("user-1")` and `getCachedUser("user-2")` at the same time make 2 calls (the lock must be per key, not
  global).
- Same with an invalidation in the middle: start a cached query, run `createCachedUser` before it answers; the
  value stored afterwards must not be the stale one.

## 7. GraphQL error details from a real server — DONE

Server: `getUserOrErrors("missing")` throws a `GraphqlErrorException` with `extensions {code: NOT_FOUND, retryable: false, detail: {id, attempts: 3}}`, and a new `GraphqlErrorResolver` passes it through with its path, location and extensions (Spring masked it as `INTERNAL_ERROR` before, so every earlier error message check only saw a generated id). New custom operation `partialAliased` (`ok: getUser`, `bad: findUser("error-id")`, `@glCaptureErrors`). Tests: `error_details_test.dart`, `error-details.test.ts`, `test_error_details.py`, `error_details_test.go`, `ErrorDetailsTest.{java,kt,swift}`. All pass.

Generator defect found: `@glCaptureErrors` on a custom operation (`query x @glCaptureErrors { ... }`) was accepted by the parser but ignored; `isCaptureErrors` only looked at the first root field. Fixed in `capture_errors_utils.dart`, unit test in `test/serializers/dart/capture_errors_test.dart`. The original proposal follows.

Error `path`, `locations` and `extensions` are barely asserted against Spring (Swift, Python and Go never).

- Server: make `getUserOrErrors("missing")` throw a `GraphqlErrorException` with
  `extensions: {code: "NOT_FOUND", retryable: false, detail: {id: "missing"}}`.
- Assert in every language: `message`, `path == ["getUserOrErrors"]`, `locations[0].line`, `extensions.code`, and that
  a nested `extensions` object and a boolean are decoded with their types.
- Partial data: a query with a failing **nullable** field next to a working one (`{ ok: getUser(id: "user-1") { id }
  bad: findUserOrErrors(id: "error") { id } }`) returns data for `ok`, null for `bad`, and one error with
  `path == ["bad"]` (alias, not field name).

## 8. Python and Go assertion counts (checked, no gap)

The first pass counted mentions of operation names per area (Python and Go about a third of the other languages) and
read that as missing assertions. Compared case by case against `dart_client_tests_real/test/{error_capture,normalization,default_values,scalars,nullability}_test.dart`,
Python and Go already cover every case; they put several checks in one test, so the counts differ by file layout, not coverage.

| Area | Python | Go |
|---|---|---|
| error capture | `ErrorCaptureTest` (`test_queries.py`) | `error_capture_test.go` |
| normalization | `KeywordAndNormalizationTest` (`test_mutations.py`) | `TestNormalization` (`queries_test.go`) |
| default values | `DefaultValuesTest` (`test_mutations.py`) | `default_values_test.go` |
| scalars, nullability | `ScalarsTest`, `NullabilityAndNestingTest` (`test_queries.py`) | `TestScalars` and the nullability tests (`queries_test.go`) |

Only trivial differences remain (Dart also calls `getDriver` with `odometerKm` 100 and 300 and an explicit `liters: 10`).
Nothing to port.

## 9. Smaller gaps

- **Cancelling an in-flight query/mutation**: no real test cancels a request while the server is slow (task cancel,
  context cancel, `AbortSignal`, coroutine cancel). Use `fault_server`'s `slow` on GraphQL and assert the cancel
  returns quickly and the next request works.
- **Large responses**: **DONE (7 targets, no defects).** The fault server serves a 10.3 MB GraphQL response (`huge-users`, 50,000 users, built in memory by `server.py` from `fault_server/huge_case.json`, with non-ASCII names). Each client fetches it through the custom query `fetchBigUsers` and checks the count, first and last element, UTF-8, an enum, a list, a null, a 30 s ceiling, and a second call on the same client. All decode it in 0.6 to 1.4 s with nothing lost. The reactive Java packages run the derived test.
- **Variables with very large / special values over the real wire**: `Int` limits (`2147483647`, `-2147483648`),
  `Float` `1e308`, `-0.0`, a string with `\u0000` and lone surrogates (the server may reject; the client must
  serialize them without crashing).
- **Same operation, two different clients**: two client instances must not share a cache (each `newClient()` starts
  empty). Cheap, and catches accidental static stores.
