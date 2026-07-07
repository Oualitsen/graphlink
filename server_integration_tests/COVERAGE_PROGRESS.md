# server_integration_tests — Coverage Progress & Plan

Status report for the effort to broaden `server_integration_tests` coverage, with
special focus on **keyword-safe identifiers** (`gl_grammar_keyword_extension.dart`),
**field-argument hoisting** (`gl_grammar_hoist_args_extension.dart`), **initial /
default values**, and **list-nesting × nullability × kind**.

---

## 1. The goal (full target matrix)

`server_integration_tests` validates **generated servers** driven by a
GraphLink-generated **client harness**. The complete matrix we are building toward:

**Backends (generated servers under test):**

| # | Backend | Dir | Status |
|---|---|---|---|
| 1 | Java Spring **MVC** (blocking) | `java/java_server` | **active — this round** |
| 2 | Java Spring **reactive** (WebFlux) | `java/java_server_reactive` | pending |
| 3 | Kotlin Spring **non-suspended** (blocking) | `kotlin/kotlin_server_blocking` | pending |
| 4 | Kotlin Spring **suspended** (coroutines) | `kotlin/kotlin_server_suspend` | pending |
| 5 | **TypeScript** Apollo/Express | `typescript/typescript_server` | pending |

**Clients (harnesses that drive the servers):**

| Client | Status |
|---|---|
| Dart | **active — this round** (`dart_client/`) |
| Java | pending (no harness yet) |
| TypeScript | pending (no harness yet) |
| Kotlin | pending (no harness yet) |

The schema in `schema/*.gql` is **shared** by every target. The Dart harness globs
`schema/*.gql`; each server has its own config. The same generated client + test
suite is pointed at whichever server is running (selected by `PORT`), so a test
added for one backend runs against all of them once they implement the schema.

**This round scoped to: Java MVC server + Dart client only** (agreed explicitly).
Other backends/clients are deferred and are currently expected to be red (see §6).

---

## 2. What has been done

### 2.1 Schema reorganization
- `schema/base.gql` → **`schema/core.gql`** (git-mv, header updated). Still holds the
  single `type Query/Mutation/Subscription`; feature files use `extend type …`.
- **Java config** (`java/java_server/config.json`) switched to a glob
  `["../../schema/*.gql"]` so it picks up every feature file (matches the Dart glob).

### 2.2 New per-concern schema files (`schema/`)
| File | Exercises |
|---|---|
| `keywords.gql` | reserved field names (both / Dart-only / Java-only), reserved type/enum-value/op/arg names, leading-underscore type & op, `class`+`class_` collision, reserved input fields |
| `hoist_args.gql` | many-required → `CatalogFieldArgs`, all-optional/defaulted → omittable `FeedFieldArgs`, nested depth → `StoreFieldArgs`, input-name collision → `CatalogFieldArgs1`, param-name collision → `fieldArgs1` |
| `defaults.gql` | scalar/enum/list/empty-list/null defaults, nested-object arg default, argument-level defaults |
| `nesting.gql` | list depth 1/2/3 × nullability × kind (type `Box`, interface `Shape`, enum `Color`), grouped on one `NestingService` via `@glServiceName` |

### 2.3 Bugs found and fixed (each with a regression test)

**Bug 1 — leading-underscore / scalar-returning root op produced an un-sanitized service class name.**
`type Query { _status: String! }` generated `_statusService` / `_statusServiceController`.
`_getServiceName` built the name from the raw wire token with only `firstUp` (which
leaves `_` untouched), and services/controllers are skipped by all three
declaration-name sanitization passes.
- Fix: `lib/src/parser_extensions/gl_grammar_service_extension.dart` — new
  `_sanitizeClassNameBase` (strip leading `_`, PascalCase) → `StatusService`.
- Test: `test/server/services/service_name_underscore_test.dart`.

**Bug 2 — service interface vs controller method-name mismatch (uncompilable).**
Interface declared `String status();` but the controller called `statusService.status_()`.
`NamingConvention.java.field('_status')` **strips** the underscore (`status`) while the
keyword rule **moves it to the end** (`status_`); the service field is normalized (it is
the `Query`-type field instance) but the controller field is a fresh copy that
`normalizeIdentifiers()` skipped (it only normalized controller *arguments*, not field
names).
- Fix: `lib/src/parser_extensions/gl_grammar_normalization_extension.dart` — added
  `c.applyFieldNaming(convention)` in the controllers loop.
- Test: `test/server/services/service_controller_name_match_test.dart`.

**Bug 3 — Dart field named after a `dart:core` type does not compile.**
`int: Int!` generated `final int int;`, which shadows the `int` **type** across the whole
class, breaking every `int` annotation and `as int` cast. `int`/`double`/`num`/`bool`
are not reserved words, so the keyword pass ignored them, and they survive
lowerCamelCase normalization unchanged.
- Fix: `lib/src/model/reserved_words.dart` — added `num, int, double, bool` to
  `dartReservedWords` (→ `int_`, wire name unchanged).
- Test: `test/dart/dart_builtin_type_field_test.dart`.

All three unit tests pass; `test/server/` is green (8/8).

### 2.4 Java MVC server implementation (`java/java_server/src/main/java/.../impl/`)
New `@Service` beans (mock responses, Data.java-style; args synthesized so hoisted
values are observable):
- `ReservedFieldsServiceImpl`, `CollideServiceImpl`, `StatusServiceImpl`
- `HoistServiceImpl` (Catalog/Feed/Store/Shelf/SearchResult root + mapping methods), `Mock.java`
- `DefaultsServiceImpl` (Config/Range/Greet), `NestingServiceImpl` (9 methods)
- Filled in `ArticleServiceImpl.getProjectedArticle` and
  `ArticleSchemaMappingsServiceImpl.articleAuthorList`.

**`./gradlew build -x test` → BUILD SUCCESSFUL.** All generated code + impls compile,
including the torture cases: `type class` → `Class` (shadows `java.lang.Class`, resolves
via same-package), reserved-word fields/args/enums, `Collide` (`class_2`/`class2`),
`Secret_`, nested `List<List<List<…>>>` for type/interface/enum, and every hoist mapping.

### 2.5 Dart client tests (`dart_client/test/`)
New behavioral suites, all `dart analyze`-clean against the generated client:
`keywords_test.dart`, `hoist_args_test.dart`, `defaults_test.dart`, `nesting_test.dart`.
Existing `queries_test` / `mutations_test` / `subscriptions_test` updated to pass the
now-required `fieldArgs` (getArticle/listArticles legitimately hoist
`Author.latestArticles(limit: Int!)` through the `Article → author` chain — expected, not a bug).

---

## 3. Status matrix (this round)

| Concern | Schema | Java MVC server impl + compile | Dart client test (analyze) | Behavioral run |
|---|---|---|---|---|
| Keywords | ✅ | ✅ | ✅ | ⏳ |
| Hoist args | ✅ | ✅ | ✅ | ⏳ |
| Defaults | ✅ | ✅ | ✅ | ⏳ |
| Nesting | ✅ | ✅ | ✅ | ⏳ |

⏳ = written & compiles, **not yet executed end-to-end**.

---

## 4. What is left — immediate (Java MVC + Dart)

1. **Run `make java` end-to-end** (build → start server → run Dart suite) and get
   behavioral pass/fail. Not yet executed.
2. Verify runtime-only behaviors the compiler can't:
   - Interface type resolution for `nesting.gql` `Shape` (Circle/Square via inferred
     `__typename`) at depths 1/2/3.
   - Default-value application: client omits a field → server returns the schema default
     (`resolveConfig`, `resolveRange`, `greet`).
   - `class` → `java.lang.Class` shadow behaves at runtime (Jackson (de)serialization).
   - `Collide` (`class`/`class_`) values stay distinct across the wire.

---

## 5. What is left — the full matrix (future rounds)

### 5.1 Other backends
Each needs the new schema wired in + impls written, then `make <target>` green:
- **Java reactive** (`java/java_server_reactive`) — same impls, `Mono`/`Flux` return types.
- **Kotlin blocking** and **Kotlin suspend** (`kotlin/…`) — Kotlin impls (`data class`,
  `suspend fun` for the suspend variant).
- **TypeScript** (`typescript/typescript_server`) — resolver impls.

⚠ **Their configs still list `base.gql` + `mapping.gql` explicitly** (now renamed to
`core.gql`), so they will fail generation until updated. See §6.

### 5.2 Other clients (Java / TypeScript / Kotlin harnesses)
Only the **Dart** harness exists here. To validate *all four clients*, each language
needs its own harness project under `server_integration_tests/` (mirroring the Dart
harness: generate a client from `schema/*.gql`, run an equivalent behavioral suite
against the running server). This is the largest remaining chunk.

### 5.3 Coverage gaps still open
- `autoQueryArgumentLimit` pruning (needs >200 args) — better as a unit test than integration.
- Enum value with a **leading underscore** (`_draft` → `DRAFT_`) — the one keyword
  sub-rule not yet exercised by `keywords.gql`.

---

## 6. Known state / sharp edges

- **Kotlin & TS targets are currently red by design.** The shared-schema reorg
  (`base.gql` → `core.gql`) + Java-only scope means their explicit-path configs are stale
  and they lack impls for the new schemas. Agreed trade-off ("Java only for now"). Fix
  when each is brought online: switch their configs to `schema/*.gql` and add impls.
- **`type class` → Java `Class`** shadows `java.lang.Class`. Compiles (same-package
  precedence) but is a JDK-name collision worth a generator decision later (suffix
  JDK/`java.lang` names?).
- Reserved-word divergence between targets is intentional coverage: `is`/`in`/`with`
  sanitized in Dart only; `int`/`synchronized`/`native` in Java only; wire names stable.

---

## 7. Suggested next steps (ordered)

1. `make java` end-to-end; fix any behavioral failures (Java MVC + Dart). **← we are here**
2. Add the enum leading-underscore case to `keywords.gql` (cheap, closes a keyword gap).
3. Bring up **Java reactive** (reuse impls, wrap returns).
4. Bring up **Kotlin** (blocking then suspend) — update configs, write Kotlin impls.
5. Bring up **TypeScript** server — update config, write resolvers.
6. Stand up **Java / TS / Kotlin client harnesses** so all four clients are validated.
