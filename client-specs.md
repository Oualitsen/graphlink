# GraphLink — Client Target Specification

What every generated client MUST, SHOULD and MAY do. Derived from the Dart client (the reference target), read from
`lib/src/serializers/dart/dart_serializer.dart`, `lib/src/serializers/client_serializers/dart/` and `lib/src/cache_store_dart.dart`.
New targets follow Dart; a language-specific deviation is allowed only where the language forces it, and MUST be
documented under "Known limitations" on that language's page in `site/docs-src/`.

Keywords: **MUST** = a conformance requirement. **SHOULD** = expected unless the language makes it impractical.
**MAY** = optional.

Existing per-feature specs: `specs/client.md` (older, Dart/Java config tables), `specs/server.md`.

---

## 1. Generator-level rules

1. Output MUST have zero runtime dependency on GraphLink. Everything the client needs is emitted into the output.
2. Third-party dependencies MUST be limited to an HTTP and a WebSocket library, and each MUST be replaceable
   (`httpAdapter` / `wsAdapter: "none"`). With both set to `none` the output SHOULD use only the language's standard library.
3. Every generated file MUST start with the `// GENERATED` header (or the language's comment equivalent).
4. One type, input, enum, interface or union per file wherever the language allows it. Where it does not (Go: import cycles),
   use one flat package and keep one file per type.
5. All generated control flow, methods and classes MUST be built through the language's `*CodeGenUtils`
   (`CodeGenUtilsBase`), never hand-formatted strings (see `CLAUDE.md`).
6. Generated identifiers that are not part of the public API (locals, private helpers) MUST use the `gl<Name>__`
   pattern so they cannot collide with schema names (`dart_client_vars.dart`).
7. Names that collide with a reserved word of the target language MUST be renamed through `reserved_words.dart`
   while the wire name is preserved separately (`field.name` is the wire key, `field.codeName` is the identifier).
8. Wire the target into `config.dart` (`clientConfig.<lang>`), `main.dart`, `grammar_factory.dart` and `naming_convention.dart`.

## 2. Configuration surface

Every target MUST accept these keys under `clientConfig.<lang>`, with the same defaults as Dart unless noted:

| Key | Default | Effect |
|---|---|---|
| `packageName` / module name | required | Package, namespace or module of the output |
| `output` | required | Output directory |
| `autoGenerateQueries` | `false` | Build operation text from the schema, requesting all non-skipped fields |
| `generateAllFieldsFragments` | `false` | `_all_fields` fragment per type |
| `operationNameAsParameter` | `false` | Pass the operation name to the HTTP adapter as an extra argument |
| `captureErrors` | `false` | Same as `@glCaptureErrors` on every query and mutation |
| `nullableFieldsRequired` | `false` | Nullable fields have no default in constructors (N/A where the language has no constructors) |
| `immutableTypeFields` / `immutableInputFields` | `true` | Read-only fields (N/A where the language cannot express it; say so in the docs) |
| `strictEnums` | `false` | `false` adds the `unknownValue__` fallback; `true` fails on undeclared values |
| `typeMappings` | `{}` | Custom scalar name → language type |
| `httpAdapter` | the language's default | `none` disables the generated default adapter |
| `wsAdapter` | the language's default | `none` disables the generated default WebSocket adapter |
| `persistedQueries`, `persistedQueriesUseGet` | off | See section 13 |

Options that cannot apply MUST be accepted and ignored, and listed in the language's docs.

## 3. Scalars and nullability

| GraphQL | Dart reference | Requirement |
|---|---|---|
| `ID`, `String` | `String` | text |
| `Int` | `int` | 32-bit integer or wider |
| `Long` | `int` | 64-bit integer |
| `Float` | `double` | IEEE-754 double |
| `Boolean` | `bool` | boolean |
| JSON object (`gqlMapStrObj`) | `Map<String, dynamic>` | string-keyed map of untyped values |
| untyped (`dynamicValue`) | `dynamic` | any JSON value |
| custom scalar | from `typeMappings` or `@glExternal` | An unmapped custom scalar MUST fall back to the untyped value |

- A nullable GraphQL type MUST map to a nullable representation; non-null MUST NOT be nullable.
- A missing key and an explicit `null` MUST decode the same for a nullable field.

## 4. Types

For every non-internal object type, excluding fields marked `@glSkipOnClient`:

1. Fields map one to one, in schema order, under their wire names.
2. `fromJson(map)` reads each field from its wire key. Unknown keys MUST be ignored.
3. `toJson()` writes every field under its wire name and MUST include `__typename` for object types.
4. Nested types, lists (any depth), maps and enums are converted recursively, honoring list and item nullability.
5. Types with `@glEqualsHashcode` or `identityFields` MUST get value equality and a matching hash over exactly those fields.
6. `@glDecorators(applyOnClient: true)` annotations MUST be emitted on the type or field.
7. `@glTypeName(name: "X")` renames the generated type; the wire `__typename` stays the schema name.
8. Types are immutable by default (`immutableTypeFields`).

## 5. Inputs

1. Same rules as types, controlled by `immutableInputFields`.
2. `toJson()` MUST NOT emit `__typename`.
3. Schema default values MUST be applied when the caller omits the value, in a way idiomatic to the language
   (constructor default, factory, builder). If the language cannot default struct fields (Go), a constructor function MUST exist.
4. `@glMapsTo` / `@glMapField` generate the conversion method to the target type.
5. Upload scalars (section 11) are not serialized by `toJson`.

## 6. Enums

1. One member per schema value, `toJson` returns the exact wire string, `fromJson` is the inverse.
2. Unless `strictEnums` is `true`, every enum gets an extra member named **`unknownValue__`** (language-cased where the
   language dictates, e.g. `<Enum>UnknownValue__` in Go).
3. `fromJson` of a value the schema does not declare MUST return `unknownValue__` (or fail when `strictEnums` is `true`).
4. `toJson` on `unknownValue__` MUST throw/raise/return an error so the fallback is never sent to the server.
   If the language cannot do this (Swift: non-throwing `toJson`), it is a documented known limitation.
5. Deprecated enum values keep their language-native deprecation marker.

## 7. Interfaces and unions

1. Each is a polymorphic type with a marker so implementations can be told apart.
2. `fromJson` reads `__typename` and dispatches to the implementation's `fromJson`.
3. An unknown `__typename` MUST fail with a clear error naming the type (no fallback exists).
4. Interface fields are exposed on the interface (getter, protocol requirement, abstract property).
5. Responses use **projected types**: each unique selection shape of an operation generates its own type
   (see `projections/`), not the full schema type. Fragments are respected in the projection.

## 8. Operation text

1. The client sends only the fields the operation selects, never the full schema.
2. Operation text is produced by `GLGraphqlSerializer`; query text MUST NOT be re-implemented per language.
3. Fragments are assembled at send time: the operation text plus the definitions of the fragments it uses, resolved
   through a name → definition map (`assembleQuery`). Missing names are skipped. Fragments over `maxFragmentBodySize` are omitted.
4. Variables are a JSON object keyed by argument name, built via each value's `toJson` (enums, inputs and lists thereof
   are converted; scalars pass through).
5. `$` in operation text MUST NOT be escaped in the output unless the language treats it as interpolation (Dart only).

## 9. Client surface

1. A root client exposes `queries`, `mutations` and `subscriptions`, each present only when the schema has at least one.
2. Each operation is one method named after its schema field (`codeName`).
3. Arguments: required (non-null, no default) arguments are mandatory; nullable and defaulted ones are optional.
   Defaults on operation arguments are applied by the method when the caller omits them.
4. Hoisted field arguments (`<Op>FieldArgs`) are spread into the variables map; an absent optional object leaves those
   variables absent so document defaults apply.
5. The default return is the operation's data object (`data!`). With `@glCaptureErrors` / `captureErrors` the method
   returns the `FullResponse` (`data` and `errors`) and MUST NOT raise on GraphQL errors.
6. Asynchrony follows the language's native model (Future, Promise, coroutine, `async`, `(value, error)` + `context`).
7. Subscriptions return the language's native stream (Stream, Flow, AsyncSequence, AsyncIterator, channel, Flux).
8. The client MUST be constructible with a single injected transport function and no other setup; a `withHttp` / URL
   convenience constructor MAY build the default adapters.

## 10. Transport

### HTTP adapter

- Contract: a function from the serialized payload string to the response body string
  (`Future<String> Function(String payload [, String operationName])`).
- The payload is `{"query": ..., "operationName": ..., "variables": ...}`.
- The adapter, not the generated client, owns headers, auth, retries and status handling.
- The client parses the returned body as JSON and never inspects HTTP status.

### Errors

- Types: `GraphLinkError { message, path?, locations?[{line, column}], extensions? }` and an exception wrapping
  `[GraphLinkError]`.
- When the response contains a non-empty `errors` array and capture is off, the method MUST raise that exception
  carrying all errors. The exception SHOULD be catchable by type.
- Transport failures MUST propagate as-is, not wrapped as GraphQL errors.

### WebSocket and subscriptions

- Protocol: `graphql-transport-ws`, message types `connection_init`, `connection_ack`, `subscribe`, `next`, `error`,
  `complete`, `ping`, `pong`.
- Adapter contract: `connect`, `sendMessage`, `close`, an incoming message stream (MUST be broadcast / multicast),
  `connectionInitPayload` (default none) and a reconnect notification.
- One connection is shared by all subscriptions.
- Handshake: connect, send `connection_init` with the payload, wait for `connection_ack`. Concurrent subscribers share one handshake.
- Each subscription gets a random UUID-formatted id and sends `subscribe` with query, operation name and variables.
- `next` yields the payload `data`; `complete` closes that subscription's stream; `error` emits the error then closes it;
  `ping` is answered with `pong`.
- Cancelling the consumer MUST remove the subscription and, when none remain, release the connection.
- On reconnect the handler re-handshakes and re-sends `subscribe` for every live subscription with the same id.
- Default adapter reconnect policy: exponential backoff starting at 1 s, doubling, capped at 30 s, plus up to 1 s random jitter,
  at most 10 attempts, attempt counter reset on success, no reconnect after a normal closure (code 1000) or after `close`.
- A connection failure surfaces as an error event on live subscription streams without closing them while reconnect is possible.

## 11. File uploads

1. Triggered by upload scalars (`@glUpload`).
2. Upload argument types: single and list. The variable for an upload is `null` in `operations`.
3. Request follows the GraphQL multipart request spec: parts `operations` (JSON `{query, variables}`), `map`
   (`{"0": ["variables.file"], "1": ["variables.files.0"]}`), then one part per file under its slot number.
   List elements get consecutive slots.
4. `GLUpload` carries a byte stream or bytes, optional length, optional filename, MIME type (default `application/octet-stream`).
5. Mutations with uploads accept an optional progress callback `(sent, total)`.
6. The multipart adapter and the upload converter are injectable; a default is generated for the default HTTP adapter.
7. Error and invalidation behaviour is identical to a plain mutation.

## 12. Caching (`@glCache`, `@glCacheInvalidate`, `@glNoCache`)

1. A query is split per root field (`divideQueryDefinition`). Each part carries `ttl`, `tags`, `staleIfOffline`,
   its variables and the argument declarations it uses.
2. If every part has `ttl == 0` the method takes the plain path. Otherwise it takes the cached path.
3. **Cache key**: `fnv1a32("<operationName>:<json of variables sorted by key>")`, hex, left-padded to 8. Operation name is
   `<operation>_<alias or empty>_<field>`. The hash MUST be reproduced exactly so stores are portable across languages.
4. **Store contract** (4 methods): `get(key)`, `set(key, value)`, `invalidate(key)`, `invalidateAll()`, over strings.
   An in-memory store MUST be the default and the store MUST be injectable.
5. **Entry** (stored as JSON): `{"data": <JSON string of the root field's value>, "expiry": <epoch ms>}`.
   `ttl` is in seconds; `expiry = now_ms + ttl * 1000`.
6. **Read path**: look up all cacheable parts concurrently; a lookup failure counts as a miss. A fresh hit is used as-is.
   An expired entry with `staleIfOffline` is kept aside as stale; without it, the entry and its tag membership are removed.
7. If every part is satisfied, return the cached response without a network call.
8. Otherwise send one request for the missing parts only: build `query <operationName>(<deduped argument declarations>)
   <directives>{ part part ... }` plus the fragments they use; variables are merged.
9. **Write path**: after a successful response, store every part with `ttl > 0` and non-null data, and register its key
   under each of its tags.
10. **Offline fallback**: if the request throws and stale parts fill every missing part, return the stale data; otherwise rethrow.
11. **Tags**: key `"__tag__" + tag`, value `{"keys": [<cache keys>]}`. Invalidating a tag invalidates every key then
    the tag entry. A key is removed from its tags when its entry expires.
12. Tag reads and writes MUST be serialized per tag (a lock per tag created at construction), so concurrent updates do not lose keys.
13. **Mutation invalidation**: after a successful mutation (and only when no errors were captured), invalidate
    `invalidateAll()` if `all: true`, otherwise the union of the mutation's tags.
14. Cached data is stored only for non-error responses; with `captureErrors` the parsed response still carries any `errors`.

## 13. Persisted queries (APQ)

Enabled by `persistedQueries: "apq"`; GET by `persistedQueriesUseGet`. Wire behaviour MUST match Dart; see `site/docs-src/persisted-queries.md`.

1. Hash: SHA-256 of the assembled query text, lower-case hex, memoized per query string. Use the standard library when it has SHA-256.
2. Extensions: `{"persistedQuery": {"version": 1, "sha256Hash": <hash>}}`.
3. Queries of length `<= persistedQueryMinLength` are sent in full without a hash.
4. First attempt sends the hash only (`operationName`, `variables`, `extensions`, no `query`).
5. Failure detection: the response contains `PersistedQueryNotFound` / `PERSISTED_QUERY_NOT_FOUND` (message or
   `extensions.code`) → resend the full query with the extension attached.
   `PersistedQueryNotSupported` / `PERSISTED_QUERY_NOT_SUPPORTED` → resend the full query without the extension and
   stop using the hash for the life of the client.
6. GET: hash-only requests go through a GET adapter with query parameters `operationName`, `variables` (JSON, omitted when
   empty) and `extensions` (JSON). Mutations never use GET. A `GraphLinkGetNotSupported` signal from the adapter falls
   back to POST permanently.
7. Fragment names assembled into the hash input MUST have a deterministic order.

## 14. Concurrency and lifecycle

- Stores and tag locks MUST be safe for concurrent use in languages with threads.
- Closing the client or WebSocket adapter MUST stop reconnection.
- A cancelled or abandoned operation MUST NOT leak a subscription or a pending handshake.

## 15. Documentation

For a new target `<lang>`:

1. `site/docs-src/<lang>-client.md` with: Configuration, Generated output, Types, Enums (including `unknownValue__`),
   Queries, Mutations, Subscriptions, Errors, Caching, File uploads, Persisted queries, **Known limitations**, Configuration reference.
2. Rows for the target in `configuration.md`, `index.md`, `getting-started.md`, `_llms_header.txt`, `_llms_concise_header.txt`, `mkdocs.yml`.
3. `CHANGELOG.md` entry, `ARCHITECTURE.md` and `CLAUDE.md` map entries, `plans/<lang>-client.md`.
4. Every deviation from this spec is a bullet under **Known limitations**.

## 16. Test conformance

A target is complete when all of these exist and pass:

1. `test/<lang>/` — generator unit tests with inline schemas.
2. `integration_tests/mock/<lang>_client_tests/` — queries, mutations, subscriptions, cache, error capture, uploads, against canned adapters.
3. `integration_tests/real/<lang>_client_tests_real/` — same areas plus default values and subscription reconnect, against the Spring server.
4. `integration_tests/persisted_queries/` — mock and real suites.
5. `server_integration_tests/clients/<lang>_client/` — the client against every generated server target.
6. CI jobs for each suite.

Behaviour that MUST be covered by tests in every language:

- scalar, list, nested list, enum, input and custom scalar round trips; nullable vs non-null
- unknown enum value decodes to the fallback, encoding it fails (or the documented limitation)
- interface and union decoding, unknown `__typename` fails
- required, optional and defaulted arguments; hoisted field args
- GraphQL errors raise; `captureErrors` returns them
- cache hit, miss, expiry, tag invalidation, mutation invalidation, `staleIfOffline`, cache key stability across calls
- subscription lifecycle: ack, next, complete, error, cancel, reconnect with resubscribe
- multipart upload map and progress
- APQ: hash-only, not-found retry, not-supported fallback, GET fallback
- reserved-word field names and aliases
