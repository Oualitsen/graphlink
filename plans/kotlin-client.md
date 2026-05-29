# Kotlin Client Generation

## Context

GraphLink already generates fully-typed clients for Dart, Java, and TypeScript.
This plan adds Kotlin as a fourth client target.

Kotlin is close to Java in structure but the idiomatic output is fundamentally different:
- `data class` / `open class` instead of POJOs with getters, setters, and builders
- Native null safety (`String?`) — no boxed types, no `@Nullable`
- `suspend fun` for async operations (coroutines), `Flow<T>` for subscriptions
- OkHttp for the default HTTP / WebSocket adapter
- `kotlinx.serialization` for the codec

---

## Configuration

Config key: `clientConfig.kotlin` (same level as `clientConfig.java`).

```json
{
  "mode": "client",
  "outputDir": "src/main/kotlin",
  "clientConfig": {
    "kotlin": {
      "packageName": "com.example.graphlink",
      "autoGenerateQueries": true,
      "inputAsDataClass": true,
      "typeAsDataClass": true,
      "wsAdapter": "okhttp"
    }
  }
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `packageName` | string | required | Kotlin package name prefix |
| `generateAllFieldsFragments` | bool | `true` | Generate `_all_fields` fragments |
| `autoGenerateQueries` | bool | `true` | Auto-generate queries from schema |
| `operationNameAsParameter` | bool | `false` | Pass operation name as adapter parameter |
| `nullableFieldsRequired` | bool | `false` | Nullable fields required in constructors |
| `captureErrors` | bool | `false` | Return full response including errors |
| `inputAsDataClass` | bool | `true` | Generate inputs as `data class` (see below) |
| `typeAsDataClass` | bool | `true` | Generate types as `data class` (see below) |
| `wsAdapter` | string | `okhttp` | `"okhttp"` or `"none"` |

### `inputAsDataClass` / `typeAsDataClass`

Mirrors `JavaClientConfig.inputAsRecord` / `typeAsRecord`. Controls whether generated classes are `data class` or `open class`.

| | `true` (default) | `false` |
|---|---|---|
| Class keyword | `data class` | `open class` |
| Field modifier | `val` | `var` |
| equals/hashCode | auto-generated | explicit override |
| CGLIB-proxyable | ❌ (final) | ✅ |
| JPA-compatible | needs plugin | ✅ |
| Recommended for | Kotlin client | Kotlin Spring Boot server (future) |

When `false`, fields are `var` (mutable) and `equals`/`hashCode` are generated explicitly —
the same pattern as Java's `equalsHascodeCode`. The class is `open` so Spring's CGLIB
proxy can subclass it without the `kotlin-spring` compiler plugin.

---

## Type Mappings

### Scalars

| GraphQL | Kotlin |
|---|---|
| `String` | `String` |
| `Int` | `Int` |
| `Float` | `Double` |
| `Boolean` | `Boolean` |
| `ID` | `String` |
| `Long` | `Long` |
| custom scalar | configurable via `typeMappings` |

### Nullability

`String!` → `String`
`String` → `String?`
`[String!]!` → `List<String>`
`[String!]` → `List<String>?`

---

## Generated constructs

### Enum

```graphql
enum Gender { male female }
```

```kotlin
enum class Gender {
    male, female;

    companion object {
        fun fromJson(value: String?): Gender? = value?.let { valueOf(it) }
    }

    fun toJson(): String = name
}
```

---

### Input type (`inputAsDataClass = true`)

```graphql
input CreateUserInput {
  name: String!
  email: String!
  role: UserRole
}
```

```kotlin
data class CreateUserInput(
    val name: String,
    val email: String,
    val role: UserRole? = null,
) {
    fun toJson(): Map<String, Any?> = mapOf(
        "name" to name,
        "email" to email,
        "role" to role?.toJson(),
    )

    companion object {
        fun fromJson(map: Map<String, Any?>): CreateUserInput = CreateUserInput(
            name = map["name"] as String,
            email = map["email"] as String,
            role = (map["role"] as? String)?.let { UserRole.fromJson(it) },
        )
    }
}
```

### Input type (`inputAsDataClass = false`)

```kotlin
open class CreateUserInput(
    var name: String,
    var email: String,
    var role: UserRole? = null,
) {
    fun toJson(): Map<String, Any?> = mapOf(
        "name" to name,
        "email" to email,
        "role" to role?.toJson(),
    )

    override fun equals(other: Any?): Boolean {
        if (other !is CreateUserInput) return false
        return name == other.name && email == other.email && role == other.role
    }

    override fun hashCode(): Int = Objects.hash(name, email, role)

    companion object {
        fun fromJson(map: Map<String, Any?>): CreateUserInput = CreateUserInput(
            name = map["name"] as String,
            email = map["email"] as String,
            role = (map["role"] as? String)?.let { UserRole.fromJson(it) },
        )
    }
}
```

---

### GraphQL `type` → Kotlin class (same `data class` / `open class` split as inputs)

```graphql
type User {
  id: ID!
  name: String!
  email: String?
}
```

```kotlin
data class User(
    val id: String,
    val name: String,
    val email: String?,
) {
    fun toJson(): Map<String, Any?> = mapOf("id" to id, "name" to name, "email" to email)

    companion object {
        fun fromJson(map: Map<String, Any?>): User = User(
            id = map["id"] as String,
            name = map["name"] as String,
            email = map["email"] as? String,
        )
    }
}
```

---

### GraphQL `interface` → Kotlin `interface`

```graphql
interface Node { id: ID! }
type User implements Node { id: ID! name: String! }
```

```kotlin
interface Node {
    val id: String

    companion object {
        fun fromJson(map: Map<String, Any?>): Node = when (map["__typename"] as String) {
            "User" -> User.fromJson(map)
            else -> throw IllegalArgumentException("Unknown type: ${map["__typename"]}")
        }
    }
}
```

Implementing types declare `override val id: String` via their constructor parameter.

---

### `@glMapsTo` mapping methods (Kotlin)

Same `toXxx()` / `fromXxx()` pattern as Java and Dart. Generated on the input class:

```kotlin
fun toUser(): User = User(
    id = id,
    name = name,
)

companion object {
    fun fromUser(user: User): CreateUserInput = CreateUserInput(
        name = user.name,
    )
}
```

List fields use `.map { }` with null-safe chaining where needed. The logic mirrors
`KotlinSerializer._toMappingExpr` / `_fromMappingExpr` (analogous to `JavaSerializer`).

---

## Client operation methods

### Query (cache-aware)

```kotlin
suspend fun getUser(id: String): User {
    val operationName = "GetUser"
    val variables = mapOf("id" to id)
    // partial query / cache logic (mirrors Java implementation)
    val payload = buildPayload(remaining, operationName, "")
    val responseText = glCallAdapter(payload)
    return parseToObjectAndCache(responseText, responseMap,
        { GetUserFullResponse.fromJson(it) }, remaining, false).data!!
}
```

### Mutation

```kotlin
suspend fun createUser(input: CreateUserInput): User {
    val operationName = "CreateUser"
    val variables = mapOf("input" to input.toJson())
    val payload = GraphLinkPayload(query = "...", operationName = operationName, variables = variables)
    val response = glCallAdapter(payload)
    val result = CreateUserFullResponse.fromJson(decoder.decode(response))
    if (result.errors != null) throw GraphLinkException(result.errors!!)
    return result.data!!
}
```

### Subscription

```kotlin
fun watchUser(id: String): Flow<UserEvent> {
    val variables = mapOf("id" to id)
    val payload = GraphLinkPayload(query = "...", operationName = "WatchUser", variables = variables)
    return handler.handle(payload).map { UserEvent.fromJson(it) }
}
```

---

## Generated file structure

```
outputDir/
  enums/          *.kt  (one file per enum)
  inputs/         *.kt  (one file per input)
  types/          *.kt  (one file per type / projected type)
  interfaces/     *.kt  (one file per interface)
  client/
    GraphLinkClient.kt
    GraphLinkResolverBase.kt
    GraphLinkQueries.kt           (if hasQueries)
    GraphLinkMutations.kt         (if hasMutations)
    GraphLinkSubscriptions.kt     (if hasSubscriptions)
    GraphLinkClientAdapter.kt     (interface)
    GraphLinkJsonEncoder.kt       (interface)
    GraphLinkJsonDecoder.kt       (interface)
    KotlinxSerializationGraphLinkJsonCodec.kt
    GraphLinkPayload.kt
    GraphLinkFullResponse.kt
    GraphLinkError.kt
    GraphLinkPartialQuery.kt
    GraphLinkCacheStore.kt
    InMemoryGraphLinkCacheStore.kt
    GraphLinkCacheEntry.kt
    GraphLinkTagEntry.kt
    GraphLinkException.kt
    DefaultGraphLinkClientAdapter.kt   (OkHttp, if wsAdapter != none)
    [if hasUploadMutations:]
      GLUpload.kt
      UploadProgressCallback.kt
      GraphLinkMultipartAdapter.kt
    [if hasSubscriptions:]
      GraphLinkWebSocketAdapter.kt
      DefaultGraphLinkWebSocketAdapter.kt
      GraphLinkSubscriptionHandler.kt
      GraphlinkWsMessageTypes.kt
      GraphLinkSubscriptionListener.kt
```

Each file starts with `package <packageName>.<subdir>` and imports only what it uses.

---

## Codec design

The codec interfaces (`GraphLinkJsonEncoder` / `GraphLinkJsonDecoder`) use `Map<String, Any?>` as the intermediate representation — the same contract as the Java target. The generated codec:

```kotlin
class KotlinxSerializationGraphLinkJsonCodec : GraphLinkJsonEncoder, GraphLinkJsonDecoder {
    private val json = Json { ignoreUnknownKeys = true }

    override fun encode(payload: Map<String, Any?>): String =
        json.encodeToString(payload.toJsonElement())

    override fun decode(data: String): Map<String, Any?> =
        json.parseToJsonElement(data).jsonObject.toAnyMap()
}
```

Where `toJsonElement()` and `toAnyMap()` are recursive extension functions that convert
between `Map<String, Any?>` and `JsonElement` — generated as package-level functions in the
codec file.

Data classes do **not** need `@Serializable` — `fromJson`/`toJson` use the `Map<String, Any?>`
approach rather than annotation-driven serialization.

---

## New source files

| File | Role |
|---|---|
| `lib/src/kotlin_code_gen_utils.dart` | Kotlin code generation primitives (mirrors `java_code_gen_utils.dart`) |
| `lib/src/serializers/kotlin_imports.dart` | Kotlin import string constants (mirrors `java_imports.dart`) |
| `lib/src/serializers/kotlin_serializer.dart` | Types / inputs / enums serializer, extends `GLSerializer` |
| `lib/src/serializers/client_serializers/kotlin_client_context.dart` | Shared context + safe variable names |
| `lib/src/serializers/client_serializers/kotlin_client_operation_serializer.dart` | Generates `suspend fun` operation methods |
| `lib/src/serializers/client_serializers/kotlin_client_serializer.dart` | Assembles `GLClassModel` instances for all client files |
| `lib/src/serializers/client_serializers/kotlin_client_constants.dart` | Static Kotlin code strings (cache, adapters, codec) |
| `lib/src/generators/kotlin_client_generator.dart` | Orchestrates file writing, mirrors `java_client_generator.dart` |

## Modified source files

| File | Change |
|---|---|
| `lib/src/config.dart` | Add `KotlinWsAdapter` enum, `KotlinClientConfig` class, update `ClientLanguageConfig.fromJson()` |
| `lib/src/main.dart` | Add import, export, dispatch for `KotlinClientConfig`, update help text |

---

## Reused utilities (no changes)

- `lib/src/serializers/gl_serializer.dart` — base class
- `lib/src/serializers/gl_client_serializer.dart` — base client class
- `lib/src/serializers/gl_graphql_serializer.dart` — GQL query string generation
- `lib/src/io_utils.dart` — `writeToFile`, `cleanUpObsoleteFiles`
- `lib/src/model/gl_input_mapping.dart` — `ToMappingPlan`, `FromMappingPlan`
- `lib/src/capture_errors_utils.dart` — `isCaptureErrors`, `clientExceptionName`
- `lib/src/gl_grammar_cache_extension.dart` — cache tag/TTL logic
- `lib/src/gl_grammar_upload_extension.dart` — upload detection
- `lib/src/code_gen_utils.dart` — `CodeGenUtilsBase` interface

---

## Tests

Add `test/kotlin/` following the same pattern as `test/java/`:

- `test/kotlin/basic/kotlin_basic_test.dart` — enum, input (`data class` and `open class`), type, interface serialization
- `test/kotlin/client/kotlin_client_test.dart` — query/mutation/subscription method generation
- `test/kotlin/maps_to/kotlin_maps_to_test.dart` — `@glMapsTo` mapping method generation

Run: `dart test test/kotlin/`
