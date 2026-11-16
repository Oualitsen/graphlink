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

Tests, one per case, in all 7 clients (own port 9930 to 9936, so the suites can run in parallel; each needs `SERVER_JAR`):
`reconnect_cases_test.go`, `test_reconnect_cases.py`, `subscription-reconnect-cases.test.ts`, `subscription_reconnect_cases_test.dart`, `SubscriptionReconnectCasesTest.{java,kt}`, `ReconnectCasesTest.swift` (`make reconnect-test` in the Swift package).
Cases: same variables on resubscribe, completed subscription not resubscribed, cancelled subscription not revived, two subscriptions on one socket both resume, restart during `connection_init` subscribes once, give-up after `maxReconnectAttempts` ends the stream with an error.
Not covered: the cancelled case in Java, because the callback API (`labelTicks(..., listener)` returns `void`) has no way to cancel a subscription.

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

## 5. WebSocket faults

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

## 6. Many cached requests at the same time

The runtimes have a cache lock, but no real test sends identical cached requests at the same time.

- Assert: 5 simultaneous `getCachedUser("user-1")` calls make **1** network call and all 5 get the same data. Also check
  `getCachedUser("user-1")` and `getCachedUser("user-2")` at the same time make 2 calls (the lock must be per key, not
  global).
- Same with an invalidation in the middle: start a cached query, run `createCachedUser` before it answers; the
  value stored afterwards must not be the stale one.

## 7. GraphQL error details from a real server

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
- **Large responses**: no GraphQL response above a few KB. Add `bigUsers(count: Int!)` and fetch about 5 MB (decoding
  speed, no truncation, the TS/Python/Go readers buffer correctly).
- **Variables with very large / special values over the real wire**: `Int` limits (`2147483647`, `-2147483648`),
  `Float` `1e308`, `-0.0`, a string with `\u0000` and lone surrogates (the server may reject; the client must
  serialize them without crashing).
- **Same operation, two different clients**: two client instances must not share a cache (each `newClient()` starts
  empty). Cheap, and catches accidental static stores.
