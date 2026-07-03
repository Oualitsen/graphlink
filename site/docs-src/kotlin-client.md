---
title: Kotlin Client — GraphLink Docs
description: Use the generated GraphLink Kotlin client in Android, Spring Boot, or any JVM/KMP project. Coroutine-based queries, mutations, and subscriptions with kotlinx.serialization. Data classes, enums (throwing fromJson as of v5.0.0), and unions fully supported.
---

# Kotlin Client

A fully typed GraphQL client generated from your schema — idiomatic Kotlin with coroutines,
data classes, and `kotlinx.serialization`.

## Configuration

Set `"mode": "client"` and add a `"kotlin"` key under `clientConfig`:

=== "JSON"

    ```json title="glink.json"
    {
      "schemaPaths": ["schema/*.graphql"],
      "mode": "client",
      "typeMappings": {
        "ID":      "String",
        "String":  "String",
        "Float":   "Double",
        "Int":     "Int",
        "Boolean": "Boolean"
      },
      "outputDir": "src/main/kotlin/com/example/generated",
      "clientConfig": {
        "kotlin": {
          "packageName": "com.example.generated",
          "generateAllFieldsFragments": true,
          "autoGenerateQueries": true,
          "typeAsDataClass": true,
          "inputAsDataClass": true,
          "wsAdapter": "okhttp"
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml"
    schemaPaths:
      - schema/*.graphql
    mode: client
    typeMappings:
      ID: String
      String: String
      Float: Double
      Int: Int
      Boolean: Boolean
    outputDir: src/main/kotlin/com/example/generated
    clientConfig:
      kotlin:
        packageName: com.example.generated
        generateAllFieldsFragments: true
        autoGenerateQueries: true
        typeAsDataClass: true
        inputAsDataClass: true
        wsAdapter: okhttp
    ```

## Generated output

For a schema with `User`, `Post`, `CreateUserInput`, and a `UserStatus` enum, GraphLink generates:

```
src/main/kotlin/com/example/generated/
  client/
    GraphLinkClient.kt                      ← main client (queries / mutations / subscriptions)
    GraphLinkQueries.kt
    GraphLinkMutations.kt
    GraphLinkSubscriptions.kt
    GraphLinkWebSocketAdapter.kt            ← WebSocket adapter interface
    GraphLinkMultipartAdapter.kt            ← file-upload adapter interface
    KotlinxSerializationGraphLinkJsonCodec.kt ← default JSON codec
    GraphLinkCacheStore.kt                  ← cache store interface
    InMemoryGraphLinkCacheStore.kt          ← in-memory cache implementation
    GraphLinkCacheEntry.kt
    GraphLinkTagEntry.kt
    GraphLinkPartialQuery.kt
    GraphLinkException.kt
    GLUpload.kt                             ← file upload type
    ...
  types/
    User.kt
    Post.kt
    CreateUserResponse.kt
    ...
  inputs/
    CreateUserInput.kt
    UpdateUserInput.kt
  enums/
    UserStatus.kt
  interfaces/
    GraphLinkClientAdapter.kt
    GraphLinkJsonEncoder.kt
    GraphLinkJsonDecoder.kt
    SearchResult.kt                         ← generated union/interface
```

## Data classes

Types and inputs are generated as `data class` by default (controlled by `typeAsDataClass` /
`inputAsDataClass`). Each class includes `toJson()` and a companion `fromJson()`:

```kotlin
// generated
data class User(
    val id: String,
    val name: String,
    val email: String,
    val status: UserStatus,
    val address: Address,
    val billingAddress: Address? = null,
    val tags: List<String>? = null,
    val scores: List<Int>? = null,
)

data class CreateUserInput(
    val name: String,
    val email: String,
    val status: UserStatus,
    val address: AddressInput,
    val billingAddress: AddressInput? = null,
    val tags: List<String>? = null,
)
```

Nullable fields have a `= null` default, so you only pass the fields you need.

## Enums

```kotlin
// generated
enum class UserStatus {
    ACTIVE, INACTIVE, SUSPENDED;

    companion object {
        fun fromJson(value: String): UserStatus = when (value) {
            "ACTIVE" -> ACTIVE
            "INACTIVE" -> INACTIVE
            "SUSPENDED" -> SUSPENDED
            else -> throw IllegalArgumentException("Unknown UserStatus: $value")
        }
    }

    fun toJson(): String = when (this) {
        ACTIVE -> "ACTIVE"
        INACTIVE -> "INACTIVE"
        SUSPENDED -> "SUSPENDED"
    }
}
```

!!! danger "Breaking change in v5.0.0"
    `fromJson` used to be `fun fromJson(value: String?): T?`, returning `null` for an unrecognized wire value. As of v5.0.0 the signature is `fun fromJson(value: String): T` — an unrecognized value now throws `IllegalArgumentException` instead of silently returning `null`. `toJson`/`fromJson` also always use an explicit wire-name mapping now (rather than `.name`/`valueOf`), since [identifier normalization](configuration.md#identifier-normalization) can make the generated enum constant name diverge from the wire value even without a keyword collision. `toJson`/`fromJson` generation is mandatory on every generated type/input/enum/interface as of v5.0.0 — there is no config flag to suppress it.

## Queries

All query, mutation, and subscription methods are `suspend` functions — call them from a
coroutine or `runTest` in tests:

```kotlin
import com.example.generated.client.GraphLinkClient
import kotlinx.coroutines.runBlocking

val user = runBlocking {
    client.queries.getUser("user-42").getUser
}
println("${user.name} — ${user.status}")
```

Compound queries that resolve multiple fields in a single network call return a typed
response with one property per top-level resolver:

```kotlin
val result = client.queries.fetchUserAndPost("user-1", "post-1")
val user = result.user     // User
val post = result.post     // Post
```

One HTTP call — two fully typed results.

## Mutations

Input classes are plain data classes — construct them directly, no builder boilerplate:

```kotlin
val input = CreateUserInput(
    name    = "Alice Smith",
    email   = "alice@example.com",
    status  = UserStatus.ACTIVE,
    address = AddressInput("123 Main St", "Springfield", "US", "12345"),
)

val response = client.mutations.createUser(input)
println(response.createUser.id)   // "user-1"
```

Nullable input fields simply have defaults — omit them when you don't need them:

```kotlin
val patch = UpdateUserInput(status = UserStatus.INACTIVE)  // only sets status
client.mutations.updateUser("user-1", patch)
```

## Subscriptions

Subscriptions return a `Flow` backed by a WebSocket connection. Collect it in a coroutine:

```kotlin
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

val job = scope.launch {
    client.subscriptions.userCreated().collect { event ->
        println("New user: ${event.userCreated.name}")
    }
}

// cancel when done
job.cancel()
```

Events are deserialized into the same typed response classes used by queries.

## Projected types

When a query selects only a subset of a type's fields, GraphLink generates a dedicated
projected class instead of reusing the full type. This ensures the Kotlin compiler catches
field misuse at compile time:

```kotlin
// schema query that selects only id, name, status
val summary = client.queries.fetchUserSummary("user-1").getUser
// summary is User_IdNameStatus — only .id, .name, .status are available
println(summary.status)  // UserStatus.ACTIVE
```

## Union and interface types

Union members are dispatched via `__typename`. Each member type implements the generated
interface or sealed hierarchy:

```kotlin
val results: List<SearchResult> = client.queries.runSearch("alice").search

for (result in results) {
    when (result) {
        is UserResult -> println("User: ${result.name}")
        is PostResult -> println("Post: ${result.title}")
    }
}
```

## Wiring the client

### Dependencies

```kotlin title="build.gradle.kts"
dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")   // only if wsAdapter = "okhttp"
}

plugins {
    kotlin("plugin.serialization") version "2.0.0"
}
```

### HTTP adapter

Implement the single-method `GraphLinkClientAdapter` interface with your HTTP client of
choice. The interface is a Kotlin `fun interface`, so a lambda works too:

```kotlin
import com.example.generated.interfaces.GraphLinkClientAdapter
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class OkHttpGraphLinkAdapter(
    private val url: String,
    private val httpClient: OkHttpClient = OkHttpClient(),
    private val headers: Map<String, String> = emptyMap(),
) : GraphLinkClientAdapter {

    private val json = "application/json; charset=utf-8".toMediaType()

    override suspend fun execute(payload: String): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(url)
            .post(payload.toRequestBody(json))
            .apply { headers.forEach { (k, v) -> addHeader(k, v) } }
            .build()

        httpClient.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "HTTP ${response.code}" }
            response.body!!.string()
        }
    }
}
```

### WebSocket adapter (OkHttp)

When `wsAdapter: "okhttp"` is set, GraphLink generates a default
`DefaultGraphLinkWebSocketAdapter` that uses OkHttp. Pass your server URL and optional
headers:

```kotlin
import com.example.generated.client.DefaultGraphLinkWebSocketAdapter

val wsAdapter = DefaultGraphLinkWebSocketAdapter(
    url     = "wss://api.example.com/graphql",
    headers = mapOf("Authorization" to "Bearer $token"),
)
```

### Assembling the client

```kotlin
import com.example.generated.client.GraphLinkClient
import com.example.generated.client.KotlinxSerializationGraphLinkJsonCodec

val codec   = KotlinxSerializationGraphLinkJsonCodec()
val adapter = OkHttpGraphLinkAdapter("https://api.example.com/graphql",
    headers = mapOf("Authorization" to "Bearer $token"))
val wsAdapter = DefaultGraphLinkWebSocketAdapter("wss://api.example.com/graphql",
    headers = mapOf("Authorization" to "Bearer $token"))

val client = GraphLinkClient(
    adapter          = adapter,
    wsAdapter        = wsAdapter,
    multipartAdapter = NoOpMultipartAdapter(),  // or a real upload adapter
    encoder          = codec,
    decoder          = codec,
)

// Use it
val user = runBlocking { client.queries.getUser("42").getUser }
```

## Caching

Cache behaviour is declared in the schema, not in code:

```graphql
type Query {
  getUser(id: ID!): User! @glCache(ttl: "5m", tags: ["users"])
}
type Mutation {
  updateUser(id: ID!, input: UpdateUserInput!): User! @glCacheInvalidate(tags: ["users"])
}
```

The generated client handles caching transparently — the second call to `getUser` with the
same arguments is served from the in-memory cache; `updateUser` evicts it:

```kotlin
val first  = client.queries.getUser("1")  // hits the network
val second = client.queries.getUser("1")  // served from cache — no HTTP call

client.mutations.updateUser("1", UpdateUserInput(status = UserStatus.INACTIVE))

val third  = client.queries.getUser("1")  // cache evicted — hits the network again
```

Bring your own cache store by implementing `GraphLinkCacheStore` and passing it to the
`GraphLinkClient` constructor.

## Inline error handling (`@glCaptureErrors`)

Enable per-operation inline errors with the directive or globally via config:

```graphql
type Query {
  findUser(id: ID!): User @glCaptureErrors
}
```

```kotlin
// returns FindUserFullResponse with nullable data + nullable errors
val result = client.queries.findUser("user-99")
if (result.errors != null) {
    result.errors.forEach { println(it.message) }
} else {
    println(result.data?.findUser?.name)
}
```

Enable globally in config with `"captureErrors": true` under `clientConfig.kotlin`.

## Configuration reference

| Option | Type | Default | Description |
|---|---|---|---|
| `packageName` | `string` | — | **Required.** Kotlin package name for all generated files. |
| `generateAllFieldsFragments` | `boolean` | `true` | Generate `_all_fields_*` fragments for every type. |
| `autoGenerateQueries` | `boolean` | `true` | Auto-generate query strings for all operations. |
| `typeAsDataClass` | `boolean` | `true` | Emit output types as `data class` instead of `open class`. |
| `inputAsDataClass` | `boolean` | `true` | Emit input types as `data class` instead of `open class`. |
| `nullableFieldsRequired` | `boolean` | `false` | When `true`, nullable constructor parameters have no default. |
| `immutableTypeFields` | `boolean` | `true` | Generate `val` fields (immutable) instead of `var`. |
| `operationNameAsParameter` | `boolean` | `false` | Append the operation name as a `?operationName=` query parameter in the request URL. |
| `captureErrors` | `boolean` | `false` | Return `FullResponse` (data + errors) for all operations instead of throwing. |
| `wsAdapter` | `"okhttp"` \| `"none"` | `"okhttp"` | WebSocket adapter to generate. `"okhttp"` emits `DefaultGraphLinkWebSocketAdapter`; `"none"` emits only the interface. |
| `defaultAlias` | `string?` | `null` | Default alias prefix for auto-generated query fields. |
