# Kotlin Client Integration Tests — Plan (queries only)

## Goal

Add `integration_tests/kotlin_client_tests/` that mirrors the Java and Dart suites.
Scope for this iteration: **query operations only** (no mutations, subscriptions, or uploads).

---

## Structure

```
integration_tests/kotlin_client_tests/
├── Makefile                           # generate → test → ci targets
├── config.json                        # glink config (kotlin, references dart schema)
├── lib/
│   └── generate.dart                  # entry point: calls generateKotlinClientClasses
└── client-app/
    ├── settings.gradle.kts
    ├── build.gradle.kts               # Kotlin 1.9+, coroutines, kotlinx.serialization, JUnit 5
    └── src/
        ├── main/kotlin/dev/graphlink/test/generated/  # ← glink writes here
        └── test/kotlin/dev/graphlink/test/
            ├── MockAdapter.kt         # GraphLinkClientAdapter backed by a Map
            ├── MockWebSocketAdapter.kt
            ├── Fixtures.kt            # shared fixture maps + newClient() factory
            ├── EnumsTest.kt           # enum deserialization, enum as query arg, round-trip
            ├── ScalarsTest.kt         # String/Int/Float/Boolean field types
            ├── NullabilityTest.kt     # nullable fields, nested nulls
            ├── ListsTest.kt           # List<T>, nullable list items, empty lists
            ├── NestedTypesTest.kt     # nested type deserialization (address, posts)
            └── QueriesTest.kt         # getUser, listUsers, listUsersByStatus, fetchUserAndPost
```

---

## Config (`config.json`)

```json
{
  "schemaPaths": ["../dart_client_tests/schema/*.gql"],
  "mode": "client",
  "typeMappings": {
    "ID":      "String",
    "String":  "String",
    "Float":   "Double",
    "Int":     "Int",
    "Boolean": "Boolean"
  },
  "outputDir": "client-app/src/main/kotlin/dev/graphlink/test/generated",
  "clientConfig": {
    "kotlin": {
      "packageName":                "dev.graphlink.test.generated",
      "generateAllFieldsFragments": true,
      "autoGenerateQueries":        true,
      "nullableFieldsRequired":     false,
      "inputAsDataClass":           true,
      "typeAsDataClass":            true,
      "wsAdapter":                  "none",
      "captureErrors":              false
    }
  }
}
```

Using the shared `dart_client_tests/schema/*.gql` — same schema as Java and TypeScript tests.
`wsAdapter: none` keeps infrastructure minimal (queries-only scope).

---

## Makefile

```makefile
CLIENT_DIR    = client-app
GENERATED_DIR = client-app/src/main/kotlin/dev/graphlink/test/generated

.PHONY: generate test clean ci

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	dart pub get
	dart run lib/generate.dart

test:
	cd $(CLIENT_DIR) && ./gradlew test

ci: generate test
```

---

## Gradle (`build.gradle.kts`)

Dependencies needed:
- `org.jetbrains.kotlin:kotlin-stdlib`
- `org.jetbrains.kotlinx:kotlinx-coroutines-core` — `runBlocking` in tests
- `org.jetbrains.kotlinx:kotlinx-serialization-json` — generated codec
- `junit:junit-jupiter` or `org.junit.jupiter:junit-jupiter`
- `org.jetbrains.kotlin:kotlin-test-junit5`

Key plugin: `kotlinx-serialization` is **not needed** — the generated codec uses raw
`Map<String, Any?>` parsing, not `@Serializable` annotations.

```kotlin
plugins {
    kotlin("jvm") version "2.0.0"
    application
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.1")
    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}

tasks.test {
    useJUnitPlatform()
}
```

---

## Infrastructure files

### `MockAdapter.kt`

Implements the generated `GraphLinkClientAdapter` (`fun interface` with
`suspend fun execute(payload: String): String` — **single parameter, no `operationName`**).

Operation name is extracted from the decoded payload map (`decoded["operationName"]`).
Uses `KotlinxSerializationGraphLinkJsonCodec` (the generated codec) for both encoding
fixture maps and decoding incoming payloads.

```kotlin
class MockAdapter : GraphLinkClientAdapter {
    private val codec = KotlinxSerializationGraphLinkJsonCodec()
    private val responses = mutableMapOf<String, String>()
    private val calls = mutableListOf<GraphLinkCall>()

    fun registerData(operationName: String, data: Map<String, Any?>) {
        responses[operationName] = codec.encode(mapOf("data" to data))
    }

    fun registerErrors(operationName: String, errors: List<Map<String, Any?>>) {
        responses[operationName] = codec.encode(mapOf("data" to null, "errors" to errors))
    }

    fun getLastCall(): GraphLinkCall? = calls.lastOrNull()
    fun getCallCount(): Int = calls.size
    fun reset() { calls.clear(); responses.clear() }

    override suspend fun execute(payload: String): String {
        val decoded = codec.decode(payload)
        val op = decoded["operationName"] as? String
        @Suppress("UNCHECKED_CAST")
        val variables = (decoded["variables"] as? Map<String, Any?>) ?: emptyMap()
        calls += GraphLinkCall(op, variables, payload)
        return responses[op] ?: error("MockAdapter: no response for \"$op\". Registered: ${responses.keys}")
    }
}

data class GraphLinkCall(
    val operationName: String?,
    val variables: Map<String, Any?>,
    val rawPayload: String,
)
```

### `MockWebSocketAdapter.kt`

`wsAdapter: none` means no default OkHttp adapter is generated, but the
`GraphLinkWebSocketAdapter` interface and constructor parameter still exist.
Provide a minimal no-op stub so `GraphLinkClient` can be constructed in tests.

```kotlin
class MockWebSocketAdapter : GraphLinkWebSocketAdapter {
    override fun connect(url: String) = Unit
    override fun send(message: String) = Unit
    override fun disconnect() = Unit
    // implement any other interface methods as no-ops
}
```

The exact method signatures depend on what the generated interface declares — adjust
once generation is confirmed.

### `Fixtures.kt`

```kotlin
object Fixtures {

    fun newClient(adapter: MockAdapter): GraphLinkClient {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        return GraphLinkClient(adapter, codec, codec)
    }

    val kAddressJson = mapOf(
        "street" to "123 Main St",
        "city"   to "Springfield",
        "country" to "US",
        "zip"    to "12345",
    )

    val kUserAliceJson = mapOf(
        "id"             to "user-1",
        "name"           to "Alice Smith",
        "email"          to "alice@test.com",
        "status"         to "ACTIVE",
        "priority"       to "HIGH",
        "address"        to kAddressJson,
        "billingAddress" to null,
        "tags"           to listOf("admin", "beta"),
        "scores"         to listOf(10, 20, 30),
        "posts"          to null,
    )

    val kUserBobJson = mapOf(
        "id"             to "user-2",
        "name"           to "Bob Jones",
        "email"          to "bob@test.com",
        "status"         to "INACTIVE",
        "priority"       to null,
        "address"        to kAddressNoZipJson,
        "billingAddress" to kBillingAddressJson,
        "tags"           to emptyList<String>(),
        "scores"         to null,
        "posts"          to null,
    )

    val kPostJson = mapOf(
        "id"       to "post-1",
        "title"    to "Hello World",
        "content"  to "Lorem ipsum",
        "author"   to kUserAliceJson,
        "coAuthor" to null,
        "tags"     to listOf("kotlin", "graphql"),
    )
}
```

---

## Test files (queries scope)

All tests use `runBlocking { }` to drive suspend funs. JUnit 5 with Jupiter.
Pattern: `@BeforeEach` sets up `adapter` and `client`; each `@Nested` class registers
one operation and exercises it from multiple angles.

### `EnumsTest.kt`

Covers enum deserialization from responses and enum serialization as query args.

```
EnumDeserialization
  ✓ status_deserializesToUserStatus_ACTIVE         (getUser → Alice → status == ACTIVE)
  ✓ status_deserializesToUserStatus_INACTIVE       (getUser → Bob → status == INACTIVE)
  ✓ priority_deserializesToPriority_HIGH           (getUser → Alice → priority == HIGH)
  ✓ priority_isNull_whenAbsent                     (getUser → Bob → priority == null)

EnumAsQueryArgument
  ✓ enumArg_isSentAsStringInVariables              (listUsersByStatus(ACTIVE) → variables["status"] == "ACTIVE")
  ✓ operationName_isListUsersByStatus
  ✓ response_containsDeserializedUsers

EnumRoundTrip
  ✓ userStatus_ACTIVE_roundTrips                   (UserStatus.ACTIVE.toJson() == "ACTIVE")
  ✓ userStatus_INACTIVE_roundTrips
  ✓ userStatus_SUSPENDED_roundTrips
  ✓ priority_LOW / HIGH / CRITICAL roundTrips
  ✓ fromJson_null_returnsNull
```

### `ScalarsTest.kt`

Covers basic scalar field deserialization (String, Int, Float, Boolean).

```
StringFields
  ✓ id_isString
  ✓ name_isString
  ✓ email_isString

IntFields   (scores field List<Int>, or a query with Int arg)
  ✓ score_isInt

BooleanFields
  ✓ isActive_isBoolean    (if schema has a boolean field)
```

### `NullabilityTest.kt`

```
NullableTopLevelField
  ✓ priority_isNull_whenNotInResponse
  ✓ billingAddress_isNull_whenNotInResponse

NullableNestedField
  ✓ address_zip_isNull_whenAbsent  (Bob address has no zip)

NullableList
  ✓ posts_isNull_whenNotInResponse
  ✓ scores_isNull_forBob
```

### `ListsTest.kt`

```
NonNullableList
  ✓ tags_areDeserializedAsList       (Alice: ["admin", "beta"])
  ✓ tags_count_isTwo
  ✓ tags_first_isAdmin

EmptyList
  ✓ tags_areEmpty_forBob             (Bob: [])

NullableElementList
  ✓ scores_areDeserializedAsList     (Alice: [10, 20, 30])
  ✓ scores_count_isThree
```

### `NestedTypesTest.kt`

```
NestedAddress
  ✓ address_isNotNull
  ✓ address_street_isCorrect
  ✓ address_city_isCorrect
  ✓ address_zip_isCorrect
  ✓ billingAddress_isNull_forAlice
  ✓ billingAddress_isNotNull_forBob

NestedAuthorInPost  (via fetchUserAndPost)
  ✓ post_author_isNotNull
  ✓ post_author_id_isCorrect
  ✓ post_author_name_isCorrect
```

### `QueriesTest.kt`

End-to-end per-operation tests: correct operation name sent, variables serialized,
response deserialized, single adapter call.

```
GetUser
  ✓ response_isNotNull
  ✓ user_isNotNull
  ✓ user_id_isCorrect
  ✓ user_name_isCorrect
  ✓ operationName_isGetUser
  ✓ variables_containsId

ListUsers
  ✓ response_isNotNull
  ✓ users_isNotNull
  ✓ users_count_isTwo
  ✓ users_first_hasCorrectId
  ✓ operationName_isListUsers
  ✓ noVariables_sent                 (variables map is empty or absent)

ListUsersByStatus
  ✓ response_isNotNull
  ✓ users_areFiltered
  ✓ operationName_isListUsersByStatus
  ✓ status_variable_isString         (ACTIVE → "ACTIVE")

FetchUserAndPost (multi-resolver)
  ✓ response_isNotNull
  ✓ user_isNotNull
  ✓ user_id_isCorrect
  ✓ post_isNotNull
  ✓ post_title_isCorrect
  ✓ singleAdapterCall_forBothResolvers
```

---

## Root Makefile update

Add kotlin target to `integration_tests/Makefile`:

```makefile
kotlin:
	make -C kotlin_client_tests ci

all: dart typescript java kotlin
```

---

## Open questions / decisions needed

1. ~~`wsAdapter: none` constructor shape~~ — **Resolved**: param stays, no default adapter
   is generated. `MockWebSocketAdapter.kt` must be written manually.

2. ~~MockAdapter JSON encode/decode~~ — **Resolved**: use `KotlinxSerializationGraphLinkJsonCodec`.

3. ~~`execute` signature~~ — **Resolved**: single param `execute(payload: String)`.
   Operation name is read from `decoded["operationName"]` inside the mock.

4. **Gradle wrapper** — Add `gradlew` + `gradle/wrapper/` committed to the repo, or rely
   on a system Gradle install? Committed wrapper is safer for CI.

---

## Implementation order

1. Scaffold `kotlin_client_tests/` directory tree (Makefile, config.json, lib/generate.dart,
   build.gradle.kts, settings.gradle.kts, gradlew wrapper).
2. Run `make generate` → confirm Kotlin files are produced in `client-app/src/main/kotlin/`.
3. Inspect generated `GraphLinkClient` constructor and `GraphLinkClientAdapter` interface.
4. Write `MockAdapter.kt`, `Fixtures.kt`.
5. Write `EnumsTest.kt` and get it green first.
6. Add remaining test files one by one.
7. Wire into root `Makefile`.
