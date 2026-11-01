# Kotlin Client — Pure Core, Optional JVM Helpers

## Overview

Today the generated Kotlin client only compiles on the JVM and Android. Some of that is deliberate (OkHttp adapters),
but a lot of it is incidental: `java.util.*`, `synchronized`, `UUID`, `System.currentTimeMillis()` and `java.io.InputStream`
leak into code that has nothing to do with HTTP.

Goal: split the generated Kotlin client into

- a **pure core** that uses only the common Kotlin stdlib, `kotlinx.coroutines` and `kotlinx.serialization`
  (both are multiplatform), and
- **optional JVM helpers**, OkHttp being the main one. They are generated on request and the core never depends on them.

This does **not** promise Kotlin Multiplatform builds. It removes the reasons the core could not compile on JS/Native/Wasm and
makes the boundary explicit and testable. A real multiplatform target stays a separate decision (see Non-Goals).

SHA-256 for persisted queries is already pure Kotlin (`kotlinSha256` in `kotlin_client_constants.dart`, no `java.*`), so the
persisted-queries work does not add to the list below.

---

## Goals

- Core files contain no `java.*`, `javax.*`, `okhttp3.*`, `System.*`, `synchronized`, `Thread`, `Math.*`.
- OkHttp becomes an optional helper, like `httpAdapter: none` on Dart. Users who bring their own HTTP stack generate nothing OkHttp-related.
- Generated code stays dependency-light: the core needs `kotlinx.coroutines` and `kotlinx.serialization` only.
- Existing JVM users keep working, or get a documented, config-gated migration.

## Non-Goals

- Shipping a Kotlin Multiplatform Gradle setup, `expect/actual`, or Ktor adapters (separate plan if wanted).
- Replacing OkHttp as the default JVM adapter.
- Changing what the generated client does at runtime on the JVM.

---

## Current State (inventory)

Source: `lib/src/serializers/client_serializers/kotlin/kotlin_client_constants.dart` and `kotlin_client_serializer.dart`.

| Area | JVM-only API today | Core or helper? | Pure replacement |
|---|---|---|---|
| Cache key | `java.util.TreeMap(variables)` | core | `variables.entries.sortedBy { it.key }` before encoding |
| Cache key hash | `java.lang.Long.toUnsignedString`, `toByteArray(Charsets.UTF_8)` | core | `hash.toULong().toString()`, `encodeToByteArray()` |
| Cache expiry | `System.currentTimeMillis()` | core | injectable clock, see Design |
| In-memory cache store | `ConcurrentHashMap` | core | lock-guarded `HashMap`, see Open Questions (store interface is not `suspend`) |
| Tag locks | `ConcurrentHashMap<String, ReentrantLock>`, `getOrPut { ReentrantLock() }` (in `kotlin_client_serializer.dart`) | core | striped `Mutex` array indexed by `tag.hashCode()`, no map needed |
| Subscription handler | `synchronized`, `@Volatile`, `UUID.randomUUID()` | core | `Mutex`, `kotlin.concurrent.Volatile`, random hex id from `kotlin.random.Random` (same approach as the Dart handler) |
| Uploads | `GLUpload(stream: java.io.InputStream)` | core | byte source abstraction, see Design |
| HTTP adapter | OkHttp (`DefaultGraphLinkClientAdapter`) | **helper** | already isolated behind `GraphLinkClientAdapter` |
| Multipart adapter | OkHttp | **helper** | same |
| WebSocket adapter | OkHttp, `Executors`, `AtomicInteger`, `Math.random()`, `@Volatile` | **helper** | stays JVM, moved fully into the helper |
| JSON codec | kotlinx.serialization | core | already pure |
| SHA-256 | none (pure) | core | done |

Already fine: coroutines (`suspend`, `Flow`, `callbackFlow`), `kotlinx.serialization`, `GraphLinkException`, generated types.

---

## Design

### 1. Core / helper split

Core files (always generated): client, resolver base, queries/mutations/subscriptions, types/inputs/enums, JSON codec interfaces and
kotlinx codec, cache store interface and in-memory store, partial query, `GraphLinkClientAdapter` and `GraphLinkWebSocketAdapter`
interfaces, subscription handler, `GraphLinkSha256`.

Helper files (generated only on request): `DefaultGraphLinkClientAdapter`, `GraphLinkMultipartAdapter` default impl,
`DefaultGraphLinkWebSocketAdapter`, plus small JVM conveniences (e.g. `InputStream.asGLUpload(...)`).

### 2. Config

Mirror the Dart precedent (`httpAdapter: none`) and the existing `wsAdapter`:

| Key | Values | Default | Meaning |
|---|---|---|---|
| `httpAdapter` | `okhttp`, `none` | `okhttp` | Generate the OkHttp HTTP and multipart adapters |
| `wsAdapter` | `okhttp`, `none` | `okhttp` | unchanged |

Defaults keep today's output, so nothing breaks. `none` gives a core that has no OkHttp references at all.

### 3. Clock

`fun interface GraphLinkClock { fun nowMillis(): Long }` in the core. The in-memory store and the cache entry take one.
The JVM helper provides `SystemGraphLinkClock` backed by `System.currentTimeMillis()`; the generated client constructor defaults to it
when helpers are generated. With `httpAdapter: none` and no helper, the clock is a required constructor argument.
Alternative: `kotlin.time` APIs. Check their stability for the minimum Kotlin version we support before choosing.

### 4. Locking

Tag locks become a fixed array of `kotlinx.coroutines.sync.Mutex` selected by `tag.hashCode()`, which removes the concurrent map.
The subscription handler's `synchronized` blocks become `Mutex.withLock`. Both are suspending, which fits the already-`suspend` API.

### 5. Uploads

`GLUpload` must not expose `java.io.InputStream`. Proposed: an interface the core owns, e.g. a source that can be read as bytes
(`suspend fun readBytes(): ByteArray`) plus `mimeType`, `length`, `filename`. The JVM helper adds an `InputStream` constructor
extension, so JVM call sites change only by a function name. The exact abstraction (whole-array vs chunked, progress reporting)
is an open question below.

---

## Rollout

1. **Guard first.** Add a test over the generated core files asserting no forbidden imports/identifiers (`java.`, `javax.`, `okhttp3`,
   `System.`, `synchronized`, `Thread`, `Math.`). It starts red and tracks progress as each row of the inventory is fixed.
2. **Mechanical swaps** that change no behavior: cache-key `TreeMap` and hash, `UUID`, `Volatile`.
3. **Clock** and the in-memory store.
4. **Locking** (tag locks, subscription handler).
5. **Config + file split**: `httpAdapter`, move OkHttp classes into the helper group, update the generator so `none` skips them.
6. **Uploads**: new byte-source abstraction and the JVM extension.
7. Docs: Kotlin client page, config reference, changelog (behavior-change notes where defaults differ), llms sources.

Each step keeps `integration_tests/mock/kotlin_client_tests` and `real/kotlin_client_tests_real` green.

---

## Testing

- Purity guard test (rollout step 1) in `test/kotlin/`, inline schema, asserting on the generated core file contents.
- Existing Kotlin mock and real suites unchanged and green after every step.
- A generation test with `httpAdapter: none` asserting no `okhttp3` appears anywhere in the output.
- Optional, later: compile the core files against a non-JVM Kotlin target (JS or Native) in CI to prove the claim, instead of only
  scanning for forbidden names. Heavy, so not required for the first PRs.

---

## Risks

- **Breaking API changes** where public types change: `GLUpload`, and the cache store interface if it becomes `suspend`.
  Gate them behind config or ship them in a documented major/minor with migration notes.
- **Behavior drift** when replacing `synchronized`/`ReentrantLock` with suspending mutexes. Reentrancy differs. The cache and
  subscription paths need a careful read and the existing cache and reconnect tests as a safety net.
- **Unverified claims.** The stability status of some stdlib APIs (`kotlin.time`, `kotlin.concurrent.Volatile`, common atomics, `kotlin.uuid`)
  changes between Kotlin versions. Verify each against the minimum Kotlin version we target before relying on it. The plan avoids
  `kotlin.uuid` and atomics on purpose.

---

## Open Questions

1. **Cache store interface.** `get/set/invalidate/invalidateAll` are plain functions today, and the common stdlib has no
   non-suspending lock. Options: make the interface `suspend` (clean, but breaks custom stores), or depend on `kotlinx.atomicfu`
   (new dependency). Leaning: `suspend`, since coroutines are already a core dependency. This one decides the in-memory store design.
2. **Clock default** when no helpers are generated: required argument, or `kotlin.time`?
3. **Upload abstraction**: whole `ByteArray` vs chunked source, and how upload progress callbacks map onto it.
4. **File layout**: keep core and helpers in one package/dir (simplest), or emit helpers into a separate directory so a
   multiplatform build can put them in `jvmMain` without moving files by hand?
5. **Minimum Kotlin version** we promise for the core.
6. **Scope of "pure"**: only generated code, or also the Spring server side (`kotlinSpring`)? Server targets are JVM by nature, so this
   plan assumes client only.
