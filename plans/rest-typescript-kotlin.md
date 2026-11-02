# Plan: REST operations for the TypeScript and Kotlin clients

Hand-off written before a context compact. The person who asked is **unavailable**: decide ambiguities yourself, following Dart and the
specs, and record each decision under "Decisions" below. Do not ask questions.

## Rules for this work
- Order: **TypeScript fully done and verified first**, then Kotlin. TypeScript must stand alone if Kotlin does not finish.
- Never run `~/bin/pr.sh`, never commit, never run the full suite (`fvm dart test` with no path). Targeted dirs only, output redirected to a log.
- Generated code through `*CodeGenUtils` builders (`TypeScriptCodeGenUtils`, `KotlinCodeGenUtils`); static runtime templates may live in
  `*_client_constants.dart` (the user decided that is fine). Zero runtime dependencies in generated code beyond what the target already uses.
- TDD for IR changes (there should be none: the IR is language independent). Generator unit tests in `test/rest/`, mock tests under
  `integration_tests/mock/<lang>_rest_tests`, real-server tests against the existing Python server.
- Print generator errors when scripting (an earlier run hid a failing generation behind `>/dev/null` and used stale output).
- Keep docs/CHANGELOG/ARCHITECTURE.md/CLAUDE.md/`site/docs-src/rest-client.md` ("Dart client only" notes) up to date.

## Source of truth
- `rest-client-specs.md` (full behaviour), `client-specs.md` (what any client does), the Dart implementation as the reference:
  `serializers/client_serializers/dart/dart_rest_operation_serializer.dart`, `dart_client_constants.dart` (`dartRestFile`,
  `dartRestResolver`, `dartRestHttpAdapter`, `dartRestDioAdapter`), `dart_client_serializer.dart` (`_restOperations`, `_hasRest`,
  `generateRest*File`, client wiring), `serializers/dart/dart_serializer.dart` (`_discriminatedFromJsonBody`, `_requiredFieldChecks`),
  `config.dart` (`restHttpAdapter`, `queryListStyle`, `formNesting`), `generators/dart_client_generator.dart`.
- IR (do not change): `GLParser.restOperations` (never in `queries`), `GLRestOperation`/`GLRestArgument`, `restDiscriminators`,
  `restReachableTypeNames`; REST return types are already registered in `projectedTypes`.
- Wire semantics already proven by the Python server `integration_tests/real/rest_server/server.py` and the schema
  `integration_tests/real/schema_rest/rest.graphql` (about 90 operations). Reuse both unchanged; add operations only if a gap appears.
- Dart real-server tests to port: `integration_tests/real/dart_rest_client_tests_real/test/*_test.dart` (133 tests, http adapter;
  the Dio package reruns them with COMMA lists and BRACKET nesting on port 9996).

## What each target needs (mirror Dart)
1. Runtime types: `RestRequest`, `RestResponse` (status, headers, byte stream, `bytes()/text()/json()`), `RestError` (status, headers, body),
   body kinds (json, form, multipart, raw), parts, `Download` + progress, the single adapter function type, helpers that flatten values into
   query/form entries (`restEntries`, spread, headers, parts, navigate by `responsePath`) with `queryListStyle` COMMA and `formNesting` BRACKET.
2. Mixin/helper on the existing operation classes: `restCall`, `restVoid`, `restText`, `restTextOrNull`, `restJson` (allowEmpty), `restDownload`,
   `restCached` (key = same fnv1a as `GraphLinkPartialQuery.computeCacheKey`, decode BEFORE storing, store only non-null, stale only on
   transport failure, never on `RestError`).
3. Per-operation methods in the existing Queries/Mutations classes (same names, no transport visible), optional/default/required arguments,
   progress callbacks for uploads/downloads, invalidation after 2xx.
4. Client wiring: REST adapter parameter (required only when the schema has REST ops); schema with only REST ops needs no GraphQL adapter;
   `withHttp`-style factory builds default adapters from `restBaseUrl`; `restHttpAdapter: none` makes the factory take a `restAdapter`.
5. Default adapters for the target's existing HTTP libraries (TS: fetch, and axios if the TS target offers it; Kotlin: OkHttp).
6. Decoding: interface/union discriminator (`__typename` first, then discriminator, error names parent and value), named error for a missing
   non-null field (`Type.field is missing or null in the response`, only for `restReachableTypeNames`).
7. Config keys in the language's client config (`restHttpAdapter`, `queryListStyle`, `formNesting`), `config.dart`.

## Testing plan per target
- Unit: `test/rest/rest_<lang>_client_test.dart` (string asserts on generated output, like `rest_dart_client_test.dart`).
- Mock: `integration_tests/mock/<lang>_rest_tests` (copy the idea of `dart_rest_tests`), wired into `integration_tests/Makefile` and `ci.yml`.
- Real: new package `integration_tests/real/<lang>_rest_client_tests_real` using the Python server, own port (used ports: 9988, 9990-9992,
  9995-9999; use **9993 for TypeScript and 9994 for Kotlin**), Makefile with a readiness poll (`curl -sf .../health` loop, never a fixed sleep),
  `ci.yml` job that sets up python3. Port ALL the Dart real tests; keep expectations identical so parity bugs show up.
- Dart real-test names/areas: query_params, headers, json_body, form, multipart, raw_upload, responses (status, empty bodies, value kinds,
  polymorphism), download, crud_flow, cache, transport (base URL prefix, concurrency), edge_cases (gzip, redirect, big response,
  invalid JSON, html error), plus the GraphQL `getCount` mixed-client check (server answers `POST /graphql`).

## Known Dart behaviours that tests depend on (keep them identical)
- Query/form lists repeat the key (COMMA joins); objects spread by default for query/header, FLAT for form/part; lists of objects and matrices
  are indexed (`a.0.b` / `a[0][b]`); empty list sends nothing; null omitted; defaults sent.
- Unknown-length upload is chunked; multipart with progress buffers; Dio/axios-style adapters must count raw upload bytes themselves.
- `204`/empty body: nullable -> null, non-null -> format/decode error; non-2xx always `RestError`; nullable TEXT on empty body -> null.
- `staleIfOffline` serves the expired entry on a transport failure only. A failed decode must not be cached.
- Content-Type: json/form set only when a body is sent; multipart never set (adapter adds boundary); raw uses the upload mime type or the
  operation's `contentType`; `Accept` default JSON, `*/*` for downloads, `text/plain` for TEXT.

## Decisions (append as you go)
- TS: REST ops live in the Queries/Mutations classes, which extend `GraphLinkRestResolver` (extends `GraphLinkResolverBase`) when they have REST ops; `restAdapter` is set by the client after construction (like Dart).
- TS client ctor: `(adapter, [getAdapter], [wsAdapter], restAdapter, [multipartAdapter], [store])`; REST-only schema omits `adapter` and passes `glNoGraphQL__`. No `withHttp`; users compose `createRestFetchAdapter(baseUrl)`.
- TS errors for decode failures are plain `Error`; Floats print as JS numbers (`3`, not `3.0`).
- TS multipart is hand-built bytes (full control of filename/content types); progress buffers. axios adapter buffers requests/responses (documented); sets `Content-Type: false` on body-less requests.
- axios variant runs in the same package via `REST_VARIANT=axios` + vitest aliases, generated from `axios/config.json`, port 9989.
- Kotlin: classes with REST ops extend `GraphLinkRestResolver` (extends `GraphLinkResolverBase`); JSON values of any shape go through the map codec by wrapping/unwrapping `{"v": ...}` (`restJson`, `restEncodeJson`). `GLUpload.length = -1` means unknown (chunked). Multipart buffers file parts.
- Kotlin config: `restHttpAdapter` reuses `KotlinWsAdapter` (okhttp|none), defaulting to `wsAdapter`. `GraphLinkPartialQuery.computeCacheKey` made public. Client primary ctor gets `restAdapter`; factories take `restBaseUrl` (or `restAdapter` when `none`). REST-only schemas drop the GraphQL adapter (`GraphLinkNoGraphQL`) - unit-tested on strings only, not compiled.
- Kotlin real tests: 61 JUnit tests (combined methods covering all Dart areas), port 9994; mock: 8 tests.
- Fixed stale `test/upload/upload_validation_test.dart` expectations (messages changed by directive validation).

## Status
- [x] TypeScript: done (22 unit, 24 mock, 132 real x fetch+axios)
- [x] Kotlin: done (16 unit, 8 mock, 61 real)
