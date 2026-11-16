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

## 1. An error response is never cached (GraphQL)

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

## 2. Headers and auth (HTTP and WebSocket)

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

## 3. Reconnect edge cases

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

## 4. Remove or implement `counterTickRestart`

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

## 8. Python and Go have about a third of the assertions

Both call every operation, but in error capture, normalization, default values and scalars they check far fewer fields
than the other 5 languages:

| Area | Dart | TS | Java | Kotlin | Swift | Python | Go |
|---|---|---|---|---|---|---|---|
| error capture | 43 | 46 | 54 | 49 | 39 | 15 | 15 |
| normalization | 14 | 14 | 21 | 14 | 14 | 4 | 4 |
| default values | 67 | 105 | 136 | 100 | 98 | 26 | 29 |
| scalars | 62 | 58 | 62 | 53 | 55 | 26 | 26 |

(Mentions of the operations in each area's tests; total tests: Python 209, Go 191, the others about 355–370.)
Port the per-field assertions from `dart_client_tests_real/test/{error_capture,normalization,default_values,scalars,nullability}_test.dart`.

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
