# Kotlin Client — Implementation Tasks

Breakdown of [kotlin-client.md](kotlin-client.md) into sequential, independently-reviewable tasks.
Each task builds on the previous one. Complete and test each before starting the next.

---

## Task 1 — Config

**Goal:** Register `KotlinClientConfig` so the generator can be dispatched from a `glink.json`.

**Files to modify:**
- `lib/src/config.dart`
  - Add `enum KotlinWsAdapter { okhttp, none }`
  - Add `class KotlinClientConfig extends ClientLanguageConfig` with all fields from the plan
  - Update `ClientLanguageConfig.fromJson()` to recognise `json['kotlin']`
- `lib/src/main.dart`
  - Import + export `KotlinClientConfig`
  - Add `KotlinClientConfig` branch in dispatch (stub that throws `UnimplementedError` for now)
  - Update help text

**Done when:** `dart run lib/src/main.dart -c kotlin-config.json` fails with `UnimplementedError`
(not a parse/config error).

---

## Task 2 — Code-gen utils + imports

**Goal:** Provide the low-level string-building primitives the Kotlin serializers will use.

**Files to create:**
- `lib/src/kotlin_code_gen_utils.dart` — implements `CodeGenUtilsBase` + Kotlin-only helpers:
  - `dataClass(name, params, body)` / `openClass(name, params, body)`
  - `companionObject(body)`
  - `suspendFun(name, params, returnType, body)` / `fun(name, params, returnType, body)`
  - `whenExpression(subject, branches)` (replaces `switchStatement`)
  - `safeCall(variable, method, nullable)` — uses `?.` not null-check
  - `safeLocalVar(name)` — same `__gl_name__` convention as Java
  - `val(name, type, value)` / `var(name, type, value)` field declarations
- `lib/src/serializers/kotlin_imports.dart` — string constants for every import the
  generated Kotlin files will need (mirrors `java_imports.dart`)

**Done when:** Unit-level Dart tests (inline or in `test/`) exercise each helper and
produce syntactically correct Kotlin strings.

---

## Task 3 — Types / Inputs / Enums serializer

**Goal:** Generate standalone Kotlin `.kt` files for every schema type, input, and enum.

**Files to create:**
- `lib/src/serializers/kotlin_serializer.dart` — extends `GLSerializer`
  - Enum → `enum class` with `companion object { fromJson }` + `toJson()`
  - Input → `data class` or `open class` (respects `inputAsDataClass`) with `toJson()` +
    `companion object { fromJson }`
  - Type → same split (respects `typeAsDataClass`)
  - Interface → Kotlin `interface` with `companion object { fromJson }` using `__typename`
  - `@glMapsTo` → `toXxx()` / `fromXxx()` mapping methods

**Done when:** `test/kotlin/basic/kotlin_basic_test.dart` passes for enum, input
(`data class` and `open class`), type, and interface output.

---

## Task 4 — Client operation serializer + context

**Goal:** Generate `suspend fun` query/mutation and `Flow<T>` subscription methods.

**Files to create:**
- `lib/src/serializers/client_serializers/kotlin_client_context.dart` — shared context
  object (safe variable names, config accessors, helpers used by both operation and
  client serializers)
- `lib/src/serializers/client_serializers/kotlin_client_operation_serializer.dart` —
  generates one method per operation:
  - Query — partial-query / cache logic, mirrors Java implementation
  - Mutation — `suspend fun`, throws `GraphLinkException` on errors
  - Subscription — returns `Flow<T>` via `handler.handle(payload).map { ... }`

**Done when:** `test/kotlin/client/kotlin_client_test.dart` passes for
query, mutation, and subscription method generation.

---

## Task 5 — Client serializer + constants

**Goal:** Assemble all `GLClassModel` instances for the full set of client support files.

**Files to create:**
- `lib/src/serializers/client_serializers/kotlin_client_constants.dart` — static Kotlin
  source strings for every boilerplate file listed in the plan's file-structure section:
  `GraphLinkPayload`, `GraphLinkError`, `GraphLinkException`, `GraphLinkCacheStore`,
  `InMemoryGraphLinkCacheStore`, `GraphLinkCacheEntry`, `GraphLinkTagEntry`,
  `GraphLinkClientAdapter`, `GraphLinkJsonEncoder/Decoder`,
  `KotlinxSerializationGraphLinkJsonCodec` (with `toJsonElement` / `toAnyMap`),
  `DefaultGraphLinkClientAdapter` (OkHttp), WebSocket adapter files,
  upload files (`GLUpload`, `UploadProgressCallback`, `GraphLinkMultipartAdapter`)
- `lib/src/serializers/client_serializers/kotlin_client_serializer.dart` — assembles
  `GLClassModel` instances for `GraphLinkClient`, `GraphLinkResolverBase`,
  `GraphLinkQueries/Mutations/Subscriptions`; decides which constant files to include
  based on config flags (`wsAdapter`, `hasUploadMutations`, `hasSubscriptions`)

**Done when:** The serializer produces the correct set of file models without errors
for a schema that has queries, mutations, subscriptions, and upload fields.

---

## Task 6 — Generator + wiring

**Goal:** Write all output files to disk and replace the Task 1 `UnimplementedError` stub.

**Files to create:**
- `lib/src/generators/kotlin_client_generator.dart` — orchestrates file writing:
  - Calls `KotlinSerializer` for enums / inputs / types / interfaces
  - Calls `KotlinClientSerializer` for client files
  - Uses `writeToFile` + `cleanUpObsoleteFiles` (from `io_utils.dart`)
  - Mirrors `java_client_generator.dart` structure

**Files to modify:**
- `lib/src/main.dart` — replace the `UnimplementedError` stub with the real generator call

**Done when:** Running `dart run lib/src/main.dart -c kotlin-config.json` against a
sample schema produces valid `.kt` files in the configured `outputDir`.

---

## Task 7 — Tests

**Goal:** Full test coverage for the Kotlin target, following the `test/java/` pattern.

**Files to create:**
- `test/kotlin/basic/kotlin_basic_test.dart`
  - Enum output
  - Input: `data class` and `open class` variants
  - Type: `data class` and `open class` variants
  - Interface with `fromJson` / `__typename` dispatch
- `test/kotlin/client/kotlin_client_test.dart`
  - Query method (with and without cache)
  - Mutation method
  - Subscription method (`Flow<T>`)
  - `captureErrors = true` variant
  - `operationNameAsParameter = true` variant
- `test/kotlin/maps_to/kotlin_maps_to_test.dart`
  - `toXxx()` and `fromXxx()` mapping methods
  - List fields with `.map { }`

**Done when:** `dart test test/kotlin/` runs green.

---

## Dependency order

```
Task 1 (config)
  └── Task 2 (utils + imports)
        └── Task 3 (serializer: types/inputs/enums)
              └── Task 4 (operation serializer)
                    └── Task 5 (client serializer + constants)
                          └── Task 6 (generator + wiring)
                                └── Task 7 (tests)
```
