# server_integration_tests audit: GraphQL coverage and open server bugs

Date: 2026-11-16. Generator state: `main` plus the uncommitted working tree of that day.

## What was missing

The client x server matrix only checks what the 8 client harnesses call, and the fault suite only checks status codes.
Before this change, nothing checked these for any server:

- Root fields never called by any client: `getArticleTypes`, `bulkCreate`, `articleDeleted`, `getProjectedArticle`,
  `getArticleWithCount`, `getArticleInfo`, `getMessageReadList`, `shapes2`, `media2`; the field `Article.authorList`.
- `bulkCreate` (list of lists input + `@glValidate`) returned a constant `0` in every server, so it tested nothing.
- Server-side defaults: clients may fill defaults themselves, so whether the server applies them was never observed.
- Batch loading with several parents (every client test fetches one author), the same mapping field with different
  arguments under aliases, null propagation from a failing mapping, explicit `null` vs. omitted argument.
- The emitted schema itself (field names, arguments, defaults, union vs. interface, no client-only types).
- Subscriptions: finite stream + `complete`, argument filtering, two subscriptions on one socket, `complete` from the
  client stopping only that subscription, several subscribers, query/mutation over the socket.

## What was added

`server_graphql/` (stdlib Python, same pattern as `server_faults/` and `server_rest/`):

- `cases.json`: 86 HTTP cases + 8 WebSocket cases. Each one sends a request and compares the exact `data`.
- `run_graphql.py <server> <port> [filter]`: matchers `$set`, `$contains`, `$absent`, `$all`, `$oneOf`, `$len`,
  `$squash`, `$any`; multi-step cases with `capture` / `{{name}}`; WebSocket cases with `setup`, `trigger`,
  `stopBeforeTrigger`.
- `known_defects.json`: the bugs below, per server. A known defect that starts passing fails the run.
- Makefile: `ci-graphql-<server>`, `make graphql`, and the suite is part of `ci-http-<server>`, so CI runs it
  (`.github/workflows/ci.yml`, job using `make ci-http-<server>`) with no workflow change.

Test server changes (hand-written code, not generated):

- `bulkCreate` in all five servers now returns the number of inputs it received, and its guard rejects the title
  `"invalid"`.
- `java_server` `updateArticle` dropped `type`, `webSite` and `published` (rebuilt the article with 3 fields).
- `java_server` and `java_server_reactive` `resolveRange` threw an NPE for `input: null`.

Result, all five servers, `make ci-http-<server>`: fault, REST and GraphQL suites pass apart from the known defects.

| Server | GraphQL suite |
|---|---|
| typescript_server | 89 ok, 5 known |
| java_server | 90 ok, 4 known |
| java_server_reactive | 90 ok, 4 known |
| kotlin_server_blocking | 91 ok, 3 known |
| kotlin_server_suspend | 91 ok, 3 known |

## Bugs (not fixed)

### 1. Express: the field typed as the `mapTo` source is never resolved (high) - FIXED

`type ArticleWithCount @glSkipOnServer(batch: false, mapTo: "Article") { article: Article! count: Int! }`: the service
returns an `Article`, `count` gets a resolver, `article` gets none, so it is always null and every
`getArticleWithCount { article { … } }` fails with "Cannot return null for non-nullable field". Same for
`MessageRead.message` (batch). Spring serves both correctly.

- Where: `express_apollo_server_serializer.dart`, the resolver map for `mapTo` types (`build-resolvers.ts` lines with
  `ArticleWithCount: { count: … }`).
- Fix: for each field of a `mapTo` type whose type is the source type, emit `field: (parent) => parent`.
- Cases: `mapping_map_to_wrapper_with_mapped_field`, `mapping_map_to_batch_list`.
- Fixed: `_mapToPassThroughFields` in `express_apollo_server_serializer.dart` emits `field: (parent) => parent`. The TS test impl looked the parent up by identity, which only worked because the case never got that far (the parent is a `toJson` copy, as on Java, see 6); it now matches by id.

### 2. Express + GraphLink GET clients: queries over GET are refused (not a bug)

Apollo's CSRF prevention answers a GET without a preflight header with 400, so a client with `persistedQueriesUseGet` cannot use GET against an Express server. Decision: the generated GET adapters do not send `apollo-require-preflight` (a custom header on a cross-origin GET forces a browser preflight and defeats cacheable GETs for every server). It is documented in `site/docs-src/persisted-queries.md` and `express-apollo.md`; developers add the header through the headers provider or configure `csrfPrevention.requestHeaders`.

- Case `core_get_request_is_answered_or_refused` accepts 200, 400 or 405.

### 3. Spring: a subscription sent over HTTP POST returns the serialized `Flux` (medium) - FIXED

`POST /graphql {"query": "subscription { articleDeleted }"}` answers **200** with
`{"data": {"upstreamPublisher": {"scanAvailable": true, "prefetch": -1}}}` on all four Spring servers. Apollo answers
with an error. A client gets a meaningless 200 and internal Reactor state leaks.

- Spring GraphQL behaviour, but fixable in generated code: a `WebGraphQlInterceptor` that rejects subscription
  operations on the HTTP transport (same family as the open `@ControllerAdvice` decision in `HARDENING.md`).
- Case: `core_subscription_over_http_rejected`.
- Fixed: schemas with subscriptions get `GraphLinkSubscriptionTransportConfig` (Java and Kotlin), a `WebGraphQlInterceptor` that answers an error for a subscription that is neither on a WebSocket nor asking for `text/event-stream`.

### 4. All servers: `= null` input defaults are dropped from the emitted schema (accepted)

`input ConfigInput { note: String = null }` is emitted as `note: String` (TS `typeDefs.ts`, Spring `schema.graphqls`).
The IR stores an explicit `null` default the same way as no default (`field.initialValue == null`), so
`gl_graphql_serializer.dart:272` cannot emit it. Runtime behaviour is the same (the field is null either way);
introspection differs from the source schema.

- Fix: keep "has a default" separate from the default value in the IR (a `GLDefaultValue` wrapper, as arguments already
  use at line 172).
- Decision: accepted. Generated types make an omitted field and a `null` default the same, so only the introspection text differs. `schema_input_defaults` now expects `defaultValue: null` for `note` and keeps checking every other default.

### 5. All servers: the internal `@glIntercept` directive is in the public schema (low) - FIXED

Every emitted schema declares `directive @glIntercept(tag: String) …`, so introspection shows it. The TS SDL also
carries `type Query @glIntercept(tag: "auth")`: the type-level directive of `extend type Query @glIntercept(…) { … }`
(in `schema_rest/rest.gql`) lands on the whole `Query` type. Runtime scoping is correct on every server
(`intercept_is_opt_in` passes), so this is cosmetic plus a small information leak (tag names).

- Fix: strip `@glIntercept` usages and its declaration from the emitted schema, as for `@glSkipOnServer`.
- Fixed: `glIntercept` is in `_skippedDirectives` of `gl_graphql_serializer.dart`, and its declaration is no longer emitted. Case: `schema_no_generator_directives`.

### 6. Mapping parents are copies without `equals`/`hashCode` (medium) - FIXED

Generated mapping controllers receive the parent as a `Map` and call `Article.fromJson(map)`, so the service gets a new
instance. Generated Java types have no `equals`/`hashCode`, so user code that looks the parent up in its own data
(`indexOf`, `contains`, `Map`/`Set` keys) silently misses: `articleWithCountCount` returns `0` instead of `1`.
Kotlin works (data classes compare by value), TS works (same object).

- Fix (either): generate `equals`/`hashCode` for Java server types, or document that parents are copies.
- Case: `mapping_map_to_wrapper_with_mapped_field` on the two Java servers.
- Fixed on every server: a controller keeps the real object next to its map under `__glSource__` (`GraphLinkSource` in Java and Kotlin, `source.ts` in Express) for the types that are parents of a mapping, and the mapping gets that instance back. Applies to types in `GLParser.sourceTypeNames`. The TypeScript test impl is back to `indexOf` and passes.

### 7. Generated Java is not Java 8 compatible

See `JAVA8_COMPAT.md` in this directory (`for (var …)` in every Java client, `final var` in Spring REST controllers,
Java 9–11 APIs in the REST and persisted-queries runtimes). New check: `make java8-check`.

## Observations (no case)

- `typescript_upload_server`: `csrfPrevention: false` whenever the schema has uploads
  (`express_apollo_server_serializer.dart:882`) turns CSRF protection off for the **whole** server, not only multipart
  requests. Worth a decision: keep it on and accept multipart with a preflight header instead.
- `typescript_upload_server` still has no fault cases (already noted in `HARDENING.md`).
- graphql-java's good-faith introspection allows one `__type` per request; the schema cases are split into steps for that.

## Gaps left open

- Client side of the newly covered operations: no client harness calls `getArticleTypes`, `bulkCreate`,
  `articleDeleted`, the four mapping queries, `shapes2`, `media2` or `authorList`. The server side is now covered by
  `server_graphql/`; client decoding of those shapes in the 8 harnesses is not. Adding them means about 8 tests x 8
  languages.
- Data isolation: suites share one server start and the fault suite creates an article, so read cases use `$contains`
  / `$absent` instead of exact lists. A reset endpoint in the test servers would allow exact assertions.
