# Kotlin Client Integration Tests — Plan

## Goal

Add a full integration test suite under `integration_tests/kotlin_client_tests/` that
mirrors the Java suite. Covers queries, mutations, cache, subscriptions, uploads, enums,
scalars, nullability, lists, nested types, and error capture.

---

## Directory layout

```
integration_tests/kotlin_client_tests/
├── Makefile
├── config.json                        # already in place
├── pubspec.yaml                       # already in place (dep on local graphlink)
├── lib/
│   └── generate.dart                  # already in place
└── client-app/
    ├── settings.gradle.kts
    ├── build.gradle.kts               # Kotlin 2.0, coroutines, serialization, JUnit 5
    ├── gradlew / gradle/wrapper/
    └── src/
        ├── main/kotlin/dev/graphlink/test/generated/  # glink writes here
        └── test/kotlin/dev/graphlink/test/
            ├── GraphLinkCall.kt           # data class for recorded calls
            ├── MockAdapter.kt             # GraphLinkClientAdapter (suspend)
            ├── MockWebSocketAdapter.kt    # no-op stub
            ├── MockMultipartAdapter.kt    # records upload calls
            ├── Fixtures.kt                # shared JSON maps + newClient()
            ├── MutationsTest.kt
            ├── QueriesTest.kt
            ├── CacheTest.kt
            ├── SubscriptionsTest.kt
            ├── UploadTest.kt
            ├── EnumsTest.kt
            ├── NullabilityTest.kt
            ├── ScalarsTest.kt
            ├── ListsTest.kt
            ├── NestedTypesTest.kt
            ├── CycleTest.kt
            └── ErrorCaptureTest.kt
```

---

## Implementation steps

### Step 1 — `build.gradle.kts`: add test dependencies  ✅
Add `kotlin("test")`, `junit-jupiter`, `kotlinx-coroutines-test`.
Enable `kotlinx.serialization` plugin (needed by generated codec).
Configure `tasks.test { useJUnitPlatform() }`.

```kotlin
plugins {
    kotlin("jvm") version "2.0.0"
    kotlin("plugin.serialization") version "2.0.0"
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}

tasks.test {
    useJUnitPlatform()
}
```

### Step 2 — `MockAdapter.kt` + `GraphLinkCall.kt`  ✅

`GraphLinkClientAdapter` is a `fun interface` with `suspend fun execute(payload: String)`.
Operation name is read from `decoded["operationName"]` in the payload.
Uses `KotlinxSerializationGraphLinkJsonCodec` for JSON round-trips.

```kotlin
data class GraphLinkCall(
    val operationName: String?,
    val variables: Map<String, Any?>,
    val rawPayload: String,
)

class MockAdapter : GraphLinkClientAdapter {
    var simulateFailure = false
    private val codec = KotlinxSerializationGraphLinkJsonCodec()
    private val responses = mutableMapOf<String, String>()
    private val _calls = mutableListOf<GraphLinkCall>()

    val calls: List<GraphLinkCall> get() = _calls
    fun getLastCall(): GraphLinkCall? = _calls.lastOrNull()
    fun getCallCount(): Int = _calls.size

    fun register(operationName: String, jsonResponse: String) { responses[operationName] = jsonResponse }
    fun registerData(operationName: String, data: Map<String, Any?>) {
        register(operationName, codec.encode(mapOf("data" to data)))
    }
    fun registerDataAndErrors(operationName: String, data: Map<String, Any?>, errors: List<Map<String, Any?>>) {
        register(operationName, codec.encode(mapOf("data" to data, "errors" to errors)))
    }
    fun registerErrors(operationName: String, errors: List<Map<String, Any?>>) {
        register(operationName, codec.encode(mapOf("data" to null, "errors" to errors)))
    }
    fun reset() { _calls.clear(); responses.clear(); simulateFailure = false }

    override suspend fun execute(payload: String): String {
        if (simulateFailure) error("Simulated network failure")
        val decoded = codec.decode(payload)
        val op = decoded["operationName"] as? String
        @Suppress("UNCHECKED_CAST")
        val variables = (decoded["variables"] as? Map<String, Any?>) ?: emptyMap()
        _calls += GraphLinkCall(op, variables, payload)
        return responses[op] ?: error(
            "MockAdapter: no response for \"$op\". Registered: ${responses.keys}\nPayload: $payload"
        )
    }
}
```

### Step 3 — `MockWebSocketAdapter.kt`

Implement all 5 methods of `GraphLinkWebSocketAdapter` as no-ops.
`connect` calls `onConnect()` immediately (so subscriptions don't hang).

### Step 4 — `MockMultipartAdapter.kt`

Implement `GraphLinkMultipartAdapter.executeMultipart(...)` — records the call and returns
a registered JSON response (same register/assert pattern as `MockAdapter`).

### Step 5 — `Fixtures.kt`

Port all fixture maps from Java `Fixtures.java`. Key changes vs Java:
- Use Kotlin `mapOf` / `listOf` — but null values require `buildMap` or explicit `to null` pairs
- `newClient()` wires `KotlinxSerializationGraphLinkJsonCodec` as encoder + decoder
- `newClientWithUpload()` adds `MockMultipartAdapter`

Generated `GraphLinkClient` constructor signature (from generated code):
```kotlin
GraphLinkClient(adapter, wsAdapter, multipartAdapter, encoder, decoder, store?)
```

### Step 6 — Test files

All tests use `runTest { }` from `kotlinx-coroutines-test`. JUnit 5 `@Nested` classes,
same structure as Java.

| File | Coverage |
|---|---|
| `MutationsTest.kt` | createUser, deleteUser, updateUser, transferPost, resetAll |
| `QueriesTest.kt` | getUser, listUsers, listUsersByStatus, getPost, fetchUserAndPost |
| `CacheTest.kt` | cache hit, miss, invalidation, staleIfOffline |
| `SubscriptionsTest.kt` | userCreated, userStatusChanged events |
| `UploadTest.kt` | uploadOneFile, uploadFileList |
| `EnumsTest.kt` | deserialization, as query arg, round-trip |
| `NullabilityTest.kt` | nullable top-level and nested fields |
| `ScalarsTest.kt` | String / Int / Float / Boolean all-scalars |
| `ListsTest.kt` | non-null list, empty list, nullable items |
| `NestedTypesTest.kt` | address, post with author |
| `CycleTest.kt` | User→Post→User cycle breaks at null |
| `ErrorCaptureTest.kt` | GraphQL errors throw `GraphLinkException` |

### Step 7 — `Makefile` + `pubspec.yaml`

Create `Makefile` matching Java pattern (`generate`, `test`, `ci` targets).
Confirm `pubspec.yaml` points at `path: ../..`.

### Step 8 — Root `Makefile` update

Add `kotlin` target and include in `all`:
```makefile
kotlin:
    make -C kotlin_client_tests ci
```

---

## Key differences vs Java

| Concern | Java | Kotlin |
|---|---|---|
| `execute()` | sync `String execute(String)` | `suspend fun execute(payload: String): String` |
| JSON codec | Jackson `ObjectMapper` | `KotlinxSerializationGraphLinkJsonCodec` |
| Test runner | `mvn test` | `./gradlew test` |
| Test coroutines | `—` | `runTest { }` from `coroutines-test` |
| Input/type objects | builder pattern | `data class` copy / named constructors |
| Null maps | `LinkedHashMap` (allows null values) | `buildMap { }` or explicit `mapOf(k to null)` |
