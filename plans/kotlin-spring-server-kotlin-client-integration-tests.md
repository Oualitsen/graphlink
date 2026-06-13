# Kotlin Spring Server + Kotlin Client Integration Tests

## Goal

Integration-test the generated Kotlin Spring GraphQL server
(`KotlinSpringServerSerializer` / `KotlinSpringControllerSerializer`) — which currently has
**zero integration test coverage** (no `config.json` anywhere uses `kotlinSpring`) — by
generating **two** real Kotlin Spring Boot backends from the same schema:

- `kotlin_server_blocking/` — `blockingServices: true` (suspend controllers wrap blocking
  service calls in `withContext(Dispatchers.IO + SecurityCoroutineContext()) { ... }`)
- `kotlin_server_suspend/` — `blockingServices: false` (coroutine-native suspend services,
  no wrapping)

Both backed by handwritten stub services returning fixed fixture data, and both exercised
by the **same** generated Kotlin client test suite (run twice, once per server/port). File
upload is out of scope for now.

## Status

**DONE.** All tasks below are complete. Both `kotlin_server_blocking` (port 9994,
`blockingServices: true`) and `kotlin_server_suspend` (port 9995, `blockingServices: false`)
generate, build, and run a 13-test Kotlin client suite (queries, mutations, subscriptions,
batch mapping, non-batch mapping) successfully. Wired into `make kotlin` (top-level
`server_integration_tests/Makefile`) and CI (`integration-tests-kotlin-server` job).

Bugs found and fixed in the generator during this work:
- `kotlin_serializer.dart` `serializeImportToken()` was missing `services`/`controllers`
  branches present in Java's equivalent — caused `Unresolved reference` errors for service
  interfaces in generated controllers.
- `kotlin_client_serializer.dart` emitted `val tags = listOf()` with no cache tags, which
  fails to compile in Kotlin (`listOf()` needs an explicit type argument or context) — fixed
  to `listOf<String>()`.
- `kotlin_server_blocking`'s Gradle build needed `spring-data-commons` at runtime
  (`KotlinReflectionUtils`, required by Spring GraphQL to invoke `suspend fun` controller
  methods via reflection) — not obvious from compile-time errors alone.

Prior context:
- `KotlinSpringServerSerializer` (134 lines) and `KotlinSpringControllerSerializer`
  (329 lines, extends `JvmSpringControllerSerializerBase`) were implemented but had
  **zero integration test coverage** before this plan — this was their first real exercise.
- `KotlinSpringServerConfig` (in `config.dart`) already has the `blockingServices: bool`
  flag (default `true`) controlling the codegen difference above.
- Kotlin client generator is proven (see `integration_tests/kotlin_client_tests_real/`,
  which runs a generated Kotlin client against the Java `spring_server`).
- `server_integration_tests/typescript/` (TS server + Dart client suite) was the structural
  template followed for this plan.

## Design (agreed)

- New folder: `server_integration_tests/kotlin/`
  - `schema/schema.gql` — reuse the Author/Article schema **verbatim** from
    `server_integration_tests/typescript/schema/schema.gql` (queries, mutations,
    subscriptions, batch mapping `Author.articles`, non-batch mapping `Article.author`).
  - `kotlin_server_blocking/`
    - `config.json` (mode: server, `kotlinSpring`, `blockingServices: true`), generating
      into `src/main/kotlin/dev/graphlink/test/generated/`
    - Handwritten stub `*ServiceImpl.kt` (committed, out of codegen scope) returning fixed
      fixture data — same fixtures as the TS suite's stub services where applicable
    - Gradle Kotlin Spring Boot app (build.gradle.kts, gradlew, application.yml), modeled
      on `integration_tests/spring_server` but Kotlin + coroutines
    - GraphQL port **9994**, actuator port **9992** (next free pair after
      9990–9991/9996–9999 used by existing suites)
    - `Makefile`: `generate`, `start-server` (background, actuator shutdown like
      `spring_server`), `stop-server`
  - `kotlin_server_suspend/`
    - Same schema, `config.json` with `blockingServices: false`
    - Separate handwritten stub services — coroutine-native `suspend fun` signatures
      (interface signatures may differ slightly from the blocking variant; confirm during
      implementation)
    - GraphQL port **9995**, actuator port **9993**
    - Same `Makefile` shape
  - `kotlin_client/`
    - `config.json` (mode: client, `kotlin`) generated against the same schema
    - Gradle Kotlin test suite, port read from a system property / env var (default to
      9994) so the **same compiled test suite** can run against either server by passing
      `-DserverPort=9994` or `-DserverPort=9995`
    - `Makefile`: `generate`, `test` (accepts a port param)
  - Top-level `server_integration_tests/kotlin/Makefile`: `generate`, `start-servers`,
    `stop-servers`, `test` (runs client suite twice — once per server), `ci`

- Wire into `server_integration_tests/Makefile` (new `kotlin` target) and
  `.github/workflows/ci.yml` (new `integration-tests-kotlin-server` job, mirroring
  `integration-tests-typescript-server`).

## Shared schema coverage

Same as the TS plan (reused file):

- Queries: nullable + non-nullable single object, list.
- Mutations: create/update/delete, object return + scalar return.
- Subscriptions: plain + with argument.
- Batch mapping: `Author.articles` (`@glSkipOnServer(batch: true)`, `@BatchMapping`).
- Non-batch schema mapping: `Article.author` (`@glSkipOnServer(batch: false)`,
  `@SchemaMapping`).
- No `Upload` scalar / upload mutations.
- No field-with-arguments mapping (`relatedArticles`) — same as the TS suite's final
  scope; carries forward the open question below.

## Risk areas / expected fixes

This is the first real compile-and-run of the Kotlin Spring generator, so expect to find
and fix bugs rather than just scaffold tests:

- **Generation correctness**: compile the generated `src/main/kotlin/.../generated/`
  output for both `blockingServices` values and fix any `KotlinSpringServerSerializer` /
  `KotlinSpringControllerSerializer` / `kotlin_imports.dart` bugs that surface
  (missing imports, wrong nullability, wrong coroutine wrapping, etc.). Per repo
  conventions, fixes go in the serializer / `gl_grammar_*_extension.dart` as appropriate
  — never hand-edit generated output.
- **Subscriptions**: Spring GraphQL subscription mappings return `Flux<T>`
  (`kotlin_spring_controller_serializer.dart` emits `fun` not `suspend fun` for
  subscriptions, line ~288). Confirm this works under both `blockingServices` configs and
  with coroutine-native stub services (likely via `Flow.asFlux()` or similar in the stub).
- **Service interface signatures**: confirm what `blockingServices: true` vs `false`
  actually generates for service method signatures (suspend vs blocking) so the two stub
  implementations are written correctly — inspect generated output before writing stubs,
  don't assume.
- **Gradle scaffold**: no existing Kotlin Spring Boot Gradle template in
  `server_integration_tests/`; build one (build.gradle.kts with Spring Boot + GraphQL +
  coroutines + actuator, gradlew wrapper, application.yml with actuator shutdown enabled
  and port config) — model on `integration_tests/spring_server`'s structure but Kotlin.

## Open questions / follow-ups (not blocking this plan)

- Carried over from the TS plan: `jvm_spring_server_serializer_base.dart`
  `_validateFieldArguments()` throws on field arguments without
  `@glSkipOnServer(batch: false)`, and disallows `batch: true` + arguments entirely. This
  applies to Kotlin Spring too (shared base class). Still an open follow-up, not part of
  this plan's scope.
- Whether to eventually add a `relatedArticles(limit: Int!)`-style field-with-arguments
  case to the shared schema (would exercise `@SchemaMapping` + `@Argument` for Kotlin) —
  deferred, matches TS suite's final scope.

## Task list

- [x] Copy `schema/schema.gql` from `server_integration_tests/typescript/schema/schema.gql`
      into `server_integration_tests/kotlin/schema/`
- [x] Scaffold `kotlin_server_blocking/` (config.json with `blockingServices: true`,
      Gradle Kotlin Spring Boot project, port 9994 / actuator 9992)
- [x] Run generation; fix `KotlinSpringServerSerializer` /
      `KotlinSpringControllerSerializer` / import-resolution bugs until it compiles and
      runs
- [x] Write handwritten stub `*ServiceImpl.kt` for the blocking variant, matching
      generated interface signatures
- [x] Scaffold `kotlin_server_suspend/` (`blockingServices: false`, port 9995 / actuator
      9993), fix any additional generator bugs specific to the suspend path
- [x] Write handwritten stub `*ServiceImpl.kt` for the suspend variant
- [x] Scaffold `kotlin_client/` (config.json mode: client/kotlin, port-parameterized test
      suite)
- [x] Write Kotlin client tests: queries, mutations, subscriptions, batch mapping,
      non-batch mapping
- [x] Top-level `server_integration_tests/kotlin/Makefile` (generate / build / start-server /
      stop-server / test / ci)
- [x] Wire into `server_integration_tests/Makefile` (new `kotlin` target) and
      `.github/workflows/ci.yml` (new `integration-tests-kotlin-server` job)
- [x] Run full suite end-to-end against both servers
