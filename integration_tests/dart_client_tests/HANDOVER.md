# Client Integration Tests — Handover

## What this is

Mock-adapter integration tests for the GraphLink Dart client generator.
No server required. The mock adapter intercepts outgoing requests, returns
pre-registered JSON, and records calls for assertion.

Pipeline: `schema → glink → generated Dart client → tests with mock adapter`

---

## Current state

**120 tests, all passing.** Run with:
```bash
make generate   # regenerates lib/generated/ from schema
make test       # runs dart test test/
make ci         # generate + test
```

---

## What has been done

### Generator bug fixes (in `../../lib/src/serializers/client_serializers/dart_client_serializer.dart`)

Two bugs were found and fixed during this session:

**Bug 1 — Spurious `graph_link_http_adapter.dart` import when `httpAdapter: "none"`**

The import guard only checked `generateAdapters`, not whether the http adapter
was set to `none`. Fixed by adding `&& httpAdapter != DartHttpAdapter.none` to
three conditions: the import line, the `_withHttpConstructor` guard, and the
`_fromUrlConstructor` guard.

**Bug 2 — `wsAdapter` required even when subscriptions aren't used in tests**

This is intentional generator behaviour (when the schema has subscriptions,
a wsAdapter is required). Resolved by adding `MockWebSocketAdapter` to
`test/mock_adapter.dart` and passing it everywhere.

---

### Schema (`schema/schema.gql`)

Added `posts: [Post!]` to `User`, creating a **`User → Post → User` cycle**.

The generator handles it correctly:
- `_all_fields_User` uses `..._all_fields_Post` (posts field expanded)
- `_all_fields_Post` expands `author` **inline** with scalar fields only — it does NOT recurse back to `..._all_fields_User`
- Consequence: `res.getPost.author` is a projected type (`User_AddressBillingAddressEmail_aep45g`) that has all scalars and address, but **no `posts` field** — the cycle is broken at the Dart type level too

---

### Project infrastructure

- `config.json` — glink config (Dart client, `httpAdapter: none`, autoGenerateQueries, allFieldsFragments)
- `pubspec.yaml` — package `graphlink_client_integration_tests`, depends on `graphlink: path: ../../`
- `lib/generate.dart` — runs `dart run lib/generate.dart` to regenerate
- `Makefile` — `make generate`, `make test`, `make clean`, `make ci`
- `.gitignore` — ignores `lib/generated/`

---

### Test utilities

**`test/mock_adapter.dart`**
- `MockAdapter` — intercepts HTTP calls, records them, returns pre-registered JSON
  - `register(opName, jsonString)` / `registerData(opName, map)` / `registerErrors(opName, errors)`
  - `calls`, `lastCall`, `callCount` for assertion
  - `simulateFailure` flag — makes every call throw (used for staleIfOffline tests)
  - `reset()` — clears calls, responses, and simulateFailure flag
- `MockWebSocketAdapter` — no-op WS adapter for tests that don't use subscriptions
  - `push(String message)` — injects a synthetic event (for future subscription tests)
  - `reconnect()` — fires the onReconnect stream

**All test `setUp` calls use:**
```dart
adapter = MockAdapter();
client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
```

**`test/fixtures.dart`** — shared JSON constants:
- `kUserAliceJson`, `kUserBobJson`
- `kAllScalarsNullJson`, `kAllScalarsPresentJson`
- `kPostJson`, `kPostWithCoAuthorJson`
- `kAuditEntryJson`, `kAuditEntryWithExtraJson`
- `kTagsJson`, `kAddressJson`, `kBillingAddressJson`
- `kPostWithAuthorCycleJson` — Post whose author has `posts: null` (cycle broken)
- `kUserWithPostsJson` — User with one post (Alice, for cycle tests)
- `dataResponse(map)` and `errorResponse(errors)` helpers

---

### Test files written

| File | Tests | What it covers |
|------|-------|----------------|
| `scalars_test.dart` | ✅ | AllScalars deserialization, nullables, outgoing variables |
| `nullability_test.dart` | ✅ | Nullable query return, nullable nested objects, nullable list fields |
| `enums_test.dart` | ✅ | Enum deserialization, serialization in variables, enum in list |
| `inputs_test.dart` | ✅ | CreateUserInput (scalars, nested input, enum, list, optional), UpdateUserInput |
| `nested_types_test.dart` | ✅ | Required/nullable nested objects, 3-level nesting, @glSkipOnClient |
| `lists_test.dart` | ✅ | List of objects, list of scalars, empty list, nullable list |
| `mutations_test.dart` | ✅ | createUser/deleteUser/updateUser response deserialization + variable shape |
| `cache_test.dart` | ✅ | Hit, miss, tag invalidation, multi-tag, invalidate-all, TTL expiry, staleIfOffline, no-cache |
| `cycle_test.dart` | ✅ | User→Post→User cycle: User.posts deserialization, projected author type |

---

## What still needs to be written

### `test/error_capture_test.dart`

- `getUserOrErrors` with error response → `res.errors != null`, `res.data == null`
- `getUserOrErrors` with success response → `res.errors == null`, `res.data.getUserOrErrors.name` correct
- `findUserOrErrors` with null data + errors → same pattern
- Without `@glCaptureErrors`: plain `getUser` throws `GraphLinkException` when server returns errors

Response type naming: `GetUserOrErrorsFullResponse` with `.data` (`GetUserOrErrorsResponse?`)
and `.errors` (`List<GraphLinkError>?`).

Register an error response using:
```dart
adapter.registerErrors('getUserOrErrors', [kGraphQLError]);
```
(`kGraphQLError` is already defined in `fixtures.dart`)

---

### `test/custom_queries_test.dart`

- `fetchUserAndPost` → `res.user.name` and `res.post.title` accessible (alias-based accessors)
- `fetchUserSummary` → projected type has `id`, `name`, `status` — that's all
- `fetchCachedPair` → both resolvers cached independently (use `callCount`)
- `runSearch` → list of `SearchResult_` dispatched by `__typename`:
  - `UserResult_IdNameEmail` for `__typename: "UserResult"`
  - `PostResult_IdTitle` for `__typename: "PostResult"`

For `runSearch` response JSON:
```json
{
  "data": {
    "search": [
      {"__typename": "UserResult", "id": "ur-1", "name": "Alice", "email": "alice@test.com"},
      {"__typename": "PostResult", "id": "pr-1", "title": "Hello World"}
    ]
  }
}
```

These are **custom operations** defined directly in `schema/schema.gql` (section 14),
not auto-generated. They are called on `client.queries` just like auto-generated ones.

---

### `test/subscriptions_test.dart` (lower priority)

Needs a mock WebSocket adapter — `MockWebSocketAdapter` in `mock_adapter.dart`
already has `push(String message)` for injecting synthetic events.

Cover:
- Typed event deserialized correctly from a pushed JSON string
- Stream emits multiple events
- Stream can be cancelled

---

## Important decisions made

- **One schema, one generated client** — all tests share the same generated client
- **Generate in CI, not pre-committed** — `lib/generated/` is gitignored
- **`httpAdapter: "none"`** — no adapter file generated; tests pass their own mock
- **`autoGenerateQueriesDefaultAlias` NOT set** — response accessors match field names (e.g. `.getUser`, not `.data`)
- **`ttl` is a String** — duration strings like `"2m"`, `"1s"`, `"10m"` (not integers)
- **Fresh client per cache test** — each cache test creates a new `GraphLinkClient` in `setUp`
- **Cycle broken by generator at one level** — `_all_fields_Post` does not recurse back to `_all_fields_User`; `Post.author` is a projected type without a `posts` field
- **`wsAdapter` is always required when schema has subscriptions** — pass `MockWebSocketAdapter()` in every `setUp`

## How to continue

1. Read this file to restore context
2. Read `test/mock_adapter.dart` and `test/fixtures.dart` to understand utilities
3. Read one existing test (e.g. `mutations_test.dart`) to confirm the pattern
4. Write `error_capture_test.dart` and `custom_queries_test.dart`
5. Run `make generate` then `make test` to verify
