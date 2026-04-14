## 1.0.0+1 - 2023-08-14

- Initial Release.

## 1.1.0 - 2023-09-19

- All generated data classes have `explicitToJson: true`

## 1.1.1 - 2023-10-19

- Updates readme file

## 2.0.0 - 2024-06-03

 - Adds `_all_fields` to target all fields (without class name)
 - Detects cycles in depencies when generating `all fields fragements`
 - You can use the package as a dev depency instead of a dependecy
 - Generates more meaningful class names when a all fields projection is used in queries/mutations.

 ## 2.0.1 - 2024-06-04
  - Fixes `_all_fields` to target all fields (without class name)

 ## 2.0.2 - 2024-06-04
  - Fixes generated code when `_all_fields` is used.

 ## 2.0.3 - 2024-06-11
  - Optimizes code generation.
  - Generates code much faster.

 ## 2.1.0 - 2025-05-14
  - Generate constructor without `required` for nullable arguments
    ### Note:
    if you need to keep generating required nullable fields you need to pass `nullableFieldsRequired: true` on your build.yaml

## 2.1.1 - 2025-05-14
    - Updates project dependcy versions
## 2.1.2 - 2025-05-14
    - Adds project links on generated files
## 2.1.3 - 2025-05-14
    - Fixes transitive frament reference
## 2.2.0 - 2025-05-15
    - Generates declares queries mutations and subscriptions without declaration
      You need to pass `autoGenerateQueries: true` on your build.yaml to enable this option
      You can also pass `autoGenerateQueriesDefaultAlias` as an alias to be used for queries, mutations and subscriptions.

## 3.0.0 - 2025-05-21
    - Generates code for unions
    - Generates == and hashcode method using either:
        1. @gqEqualsHashcode(fields: ["field1", "field2"])
        2. on build.yaml
        identityFields: ["field1", "field2"]
    Note: In case of Unions and Interfaces, the Retrofit Graphql generates empty interfaces instead of base classes.
## 3.0.1 - 2025-05-21
    - Fixed some minor bugs

## 3.1.0 - 2025-05-21
    - Generates all implemented interfaces

## 4.0.0 - 2026-03-12
  ### Java / Spring Boot code generation
  - Generates Java types, inputs, enums with `toJson`/`fromJson` methods
  - Generates Java client serializer
  - Generates Spring for GraphQL controllers and service interfaces
  - Generates repository interfaces (`@glRepository`)
  - Generates null checks on inputs and types
  - Generates Java records support
  - Generates annotations on controllers
  - Validates backend inputs (`@glValidateInput`)
  - Injects data-fetching on mappings
  - Generates schema mappings (identity, refactored)

  ### Dart code generation
  - Generates `toJson`/`fromJson` without `json_serializable` dependency
  - Generates Flutter UI views (optional, `noUi: true` to disable)
  - Projected interfaces support
  - Fixes response generation for single-element queries

  ### New directives
  - `@glDecorators` — attach decorators to generated classes
  - `@glSkipOnServer` / `@glSkipOnClient` — skip fields/types per target
  - `@glArray` — serialize GraphQL lists as arrays (Java)
  - `@glInternal` — skip internal objects from processing
  - `@glExternal` — mark external types
  - `extend` keyword support
  - `repeatable` keyword support for directives
  - Directives can now apply to fields

  ### CLI & tooling
  - CLI configuration support
  - Watch-files mode
  - Wildcard filename support
  - Handle multiple input files
  - Jenkins CI file added

  ### Other improvements & fixes
  - Removes `isScalar` from `GqType`
  - Schema generation support
  - Annotation serialization on controllers
  - Interface directive inheritance
  - `all_fields` projection skips `@glSkipOnClient` fields
  - Wildcard maps/lists instead of `List<Object>` / `Map<Object, Object>`
  - Java primitives auto-boxed when nullable
  - Multiple subscription fixes
  - Various import and serialization bug fixes

## 4.1.0 - 2026-03-12
  - Project renamed to **GraphLink** (package: `graphlink`, CLI: `glink`)
  - Migrating from `retrofit_graphql`: update your `pubspec.yaml` and `build.yaml` references from `retrofit_graphql` to `graphlink`



## 4.2.0 - 2026-03-22
  ### Client-side caching (Dart & Java)
  - New `@glCache(ttl, tags, staleIfOffline)` directive — cache any query or field with a TTL and optional tag groups
  - New `@glCacheInvalidate(tags, all)` directive — invalidate tagged cache entries on mutations
  - Partial query caching: compound queries are split per field; only the uncached fields hit the network
  - `staleIfOffline: true` returns expired cache entries when the network is unavailable instead of throwing
  - Java: generates `ResolverBase`, `GraphLinkCacheEntry`, `GraphLinkTagEntry`, `GraphLinkPartialQuery` helper classes
  - Java: generates thread-safe cache helpers using `ReentrantLock` per tag
  - Java integration tests mirroring the Dart cache integration test suite

  ### Configuration
  - New `config.json` CLI-based configuration (alternative to `build.yaml`) — use with `dart run lib/generate.dart`
  - `clientConfig.java` block for Java-specific options (`packageName`, `immutableInputFields`, `immutableTypeFields`, etc.)

## 4.3.0 - 2026-03-31
  ### New features
  - New built-in GraphQL parser — replaces `petit_parser` dependency (removed)
  - Default type adapters for Dart client serializer
  - Default type adapters for Java client serializer
  - Enum initial/default values support
  - Spring Boot: schema mapping methods now support arguments

  ### Fixes & improvements
  - Code generation is now ~4x faster
  - Fixed FNV1a hash JS compatibility in Dart cache store
  - Internal unique-name refactor for more consistent generated class names
  - Updated Java server example


## 4.3.1 - 2026-04-04
  ### Fixes & improvements
  Fixes a bug immutableInputFields and immutableTypeFields for spring boot code generation.

## 4.4.0 - 2026-04-14
  ### New features
  - **Injectable HTTP client** — `DefaultGraphLinkWebSocketAdapter` now accepts an
    `HttpClient` (Java 11) or `OkHttpClient` (OkHttp) as a constructor argument,
    allowing you to bring your own pre-configured client (proxy, SSL, timeouts, etc.).
    The no-arg and headers-only constructors still work unchanged.

  - **`DefaultGraphLinkWebSocketAdapter` reconnects by default** — the Dart adapter's
    `reconnect` flag now defaults to `true`. Previously it defaulted to `false`,
    requiring an explicit opt-in to enable automatic reconnection after a disconnect.

  - **Safe generated variable names** — internal local variables emitted inside
    generated client methods are now prefixed/suffixed (`__gl_name__`) to avoid
    accidental collisions with user-defined argument names (e.g. a query argument
    named `query` or `response` no longer shadows the internal variable).

  - **MVC security context propagation** — new `useSpringSecurity: true` option in
    `config.json` (`clientConfig.java`). When enabled (MVC mode only), the generated
    controllers capture the `SecurityContext` before entering a `CompletableFuture`
    lambda and restore it on the worker thread, so Spring Security's authentication
    is available inside async service calls. Has no effect in reactive mode.

  - **Forward mappings** — when a type uses `@glSkipOnServer(mapTo: "ServerType")`,
    fields that exist verbatim on the server type (same name and structural type) are now
    auto-forwarded in the generated controller without creating a service method.
    Only fields absent from the server type, or explicitly annotated with `@glSkipOnServer`,
    still get a full `@SchemaMapping` + service delegation.

  - **Reactive Spring server** — new `reactive: true` option in `config.json` enables
    Spring WebFlux-style controller generation. Controllers return `Mono`/`Flux` types
    and file upload fields use `FilePart` instead of `MultipartFile`.

  - **File upload support** — GraphQL multipart upload spec is now supported across all
    three targets. Dart clients (http and Dio) receive a `GLUpload` type with a stream,
    length, filename and mime type. Java clients get the equivalent `GLUpload` class.
    Spring Boot controllers accept `MultipartFile` (MVC) or `FilePart` (reactive).

  - **Input mappings (`@glMapsTo` / `@glMapField`)** — annotate a GraphQL input type
    with `@glMapsTo(type: "JavaType")` to declare that it maps to an existing Java/Dart
    class. Use `@glMapField(to: "fieldName")` on individual fields to rename them during
    mapping. GraphLink validates all target types and field names at generation time and
    emits a mapping constructor/method on the generated input class.

  ### Fixes & improvements
  - Validation code calls wrapped in `CompletableFuture`
  - `@glSkipOnClient` / `@glSkipOnServer` applied to validations
  - Completable future support in Spring controllers
  - Optimized Spring service imports
  - Fixed Java input `toJson` call on client
  - Removed `@glArray` support
  - Fixed default Dart WebSocket adapter
  - Refactored GL mapping