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
    with `@glMapsTo(type: "GraphqlType")` to declare that it maps to an existing Java/Dart
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

## 4.4.1 - 2026-04-19
  ### Fixes
  - Fixed deserialization of query responses when the return type is an interface or union



## 4.5.0 - 2026-04-19
  ### New features
  - **TypeScript client code generation** — new `clientConfig.typescript` block in `config.json`
  - Generates typed client for queries, mutations, and subscriptions
  - HTTP adapter: `fetch` (default, works in Angular, React, Svelte, Vue) or `axios` (Node/Bun environments)
  - Optional RxJS observables mode (`observables: true`) as an alternative to promises
  - Generates a default WebSocket adapter for subscriptions (`generateDefaultWsAdapter: true`)
  - Nullable input fields are optional by default (`optionalNullableInputFields: true`)
  - Supports `generateAllFieldsFragments`, `autoGenerateQueries`, `operationNameAsParameter`, `immutableTypeFields`

  ### Improvements
  - Generated Dart files: version number now embedded in the file header comment
  - Generated GraphQL files: version number now embedded in the file header comment
  - `dart:math` import in generated Dart client only emitted when subscriptions are present

## 4.5.1 - 2026-04-21
  ### Fixes
  - Fixed `@glMapsTo` / `@glMapField`: `toXxx()` and `fromXxx()` now respect `@glSkipOnClient` / `@glSkipOnServer` — fields invisible to the target mode are no longer emitted as parameters or assignments, preventing compilation errors in generated code
  - Fixed `@glMapsTo` / `@glMapField` in Java: primitive `boolean` fields now correctly use `isXxx()` getters instead of `getXxx()` in both `toXxx()` and `fromXxx()` methods

## 4.5.2 - 2026-04-22
  ### Fixes
  - Fixed `@glMapsTo`: nested input fields whose type has no `@glMapsTo` directive are now correctly treated as required parameters instead of being silently auto-mapped
  - Fixed `@glMapsTo`: fields with different GraphQL tokens that serialize to the same target type (e.g. `String!` and `ID!`) are now correctly treated as compatible and auto-mapped
  - Fixed `@glMapsTo` in Java: `java.util.List` is now imported when `requiredParams` or `defaultParams` contain list types

## 4.5.3 - 2026-04-23
  ### Fixes
  - Fixed Dart/Java: interface getter declarations now correctly force nullable field types in server mode
  - Fixed Dart `@glMapsTo` `fromXxx()`: scalar non-list fields where the type field is nullable but the input field is non-null are now emitted as required parameters instead of being silently auto-mapped
  - Fixed Dart `@glMapsTo` `fromXxx()`: list fields whose nested `fromXxx()` requires extra parameters are now escalated to required parameters instead of generating an invalid inline `.map()` call
  - Fixed Dart `@glMapsTo` `fromXxx()`: nullable target type now emits a null-safety guard (`!= null ? … : null`) instead of an unconditional call
  - Fixed Dart client: `http_parser` import is now only emitted when upload mutations are present
  - Fixed Java: type field constructors, getters, and getter declarations now correctly force nullable types in server mode

## 4.5.4 - 2026-05-03

- Fix missing space between fields in dynamically built queries (Dart, Java, TypeScript clients)

## 4.6.1 - 2026-05-15
  ### Fixes
  - Fixed `@glMapsTo` Java: boxed `Boolean` fields now correctly use `getXxx()` accessors instead of `isXxx()` in generated `toXxx()` and `fromXxx()` methods

## 4.6.0 - 2026-05-14

### New features
- **Operation name in URL** — when `operationNameAsParameter: true` is set, the operation name is now appended as a query parameter in the HTTP request URL
- **YAML config support** — the config file can now be `.json`, `.yaml`, or `.yml`. All existing JSON configs continue to work unchanged.
- **Default config discovery** — the `-c` flag is now optional. When omitted, `glink` searches for `glink.json`, `glink.yaml`, or `glink.yml` starting from the current directory and walking up to the filesystem root.

### Fixes & improvements
- Fixed Dart client: subscription connection creation
- Fixed interface: duplicate `__typename` handling in switch statements
- Fixed interface: `@glSkipOnClient` correctly applied to interface implementors on the client
- Fixed `@glMapsTo` client mode: mapping methods and imports are now suppressed when the target type is not among the projected (generated) types, preventing broken type references in the client output
- Fixed `@glMapsTo` Dart & Java: nested non-list mapped input fields whose `fromXxx()` requires extra parameters are now correctly promoted to required parameters instead of generating an invalid auto-call
- Fixed `@glMapsTo` Java: `fromXxx()` primitive `boolean` target fields now correctly use `isXxx()` getters instead of `getXxx()`
- `toXxx()` and `fromXxx()` are no longer generated when the source or target instance would be entirely unused — an input whose mapped fields are all required parameters with nothing derivable from the target no longer emits a misleading method body

### Internal
- `MappingPlan` split into `ToMappingPlan` (forward direction) and `FromMappingPlan` (reverse direction) — all field-categorization logic is now fully encapsulated in the model; serializers are pure emitters with no resolution logic of their own


## 4.7.0 - 2026-05-25

### Breaking changes

- **`@glCache` `ttl` type changed from `Int` to `String`** — the `ttl` argument now accepts a human-readable duration string instead of a bare integer.

  **Migration:** replace every bare integer TTL with a quoted duration string:

  ```graphql
  # Before
  getVehicle(id: ID!): Vehicle! @glCache(ttl: 120, tags: ["vehicles"])

  # After
  getVehicle(id: ID!): Vehicle! @glCache(ttl: "2m", tags: ["vehicles"])
  ```

  Supported formats: `"<n>s"` (seconds), `"<n>m"` (minutes), `"<n>h"` (hours), `"<n>d"` (days), or a bare integer string `"300"` (treated as seconds). The generator emits a clear error if a bare unquoted integer is found.

  Update the directive declaration in your schema file to match:

  ```graphql
  # Before
  directive @glCache(ttl: Int!, ...) on ...

  # After
  directive @glCache(ttl: String!, ...) on ...
  ```

### New features

- **`@glCaptureErrors` directive** — opt a query or mutation into inline error handling. The generated method returns `{OperationName}FullResponse` with a nullable `data` field and a nullable `errors: List<GraphLinkError>` field instead of throwing on GraphQL errors. Supported in Dart, Java, and TypeScript.

  ```graphql
  type Query {
    getUser(id: ID!): User! @glCaptureErrors
  }
  ```

  Enable globally for all queries and mutations via config:

  ```json
  "clientConfig": { "dart": { "captureErrors": true } }
  ```

  Error responses are never written to the cache. Non-annotated operations are unaffected.

- **Flutter UI widget generation** — new `flutter` config block generates Flutter widgets for GraphQL types and inputs. Configurable options:
  - `generateTypes` (default `true`) — generate display widgets for output types
  - `generateInputs` (default `false`) — generate form widgets for input types
  - `typesToSkip` / `inputsToSkip` — exclude specific types from generation
  - `defaultGap` (default `16`) — spacing between field rows
  - `booleanWidget` — `switchWidget` (default), `checkbox`, or `tristate`
  - `nullableBooleanWidget` — `checkbox` (default) or `tristate`
  - `listWidget` — `chips` (default) or `checkboxes`
  - `defaultLabelPosition` — `floatingLabel` (default), `beside`, or `above`
  - `defaultFormLayout` — `column` (default) or `twoColumn`
  - `defaultRequiredIndicator` — `asterisk` (default), `none`, `requiredText`, or `optionalText`
  - `defaultStepperOrientation` — `vertical` (default) or `horizontal`
  - `defaultTypeLayout` / `defaultGroupLayout` — `labeledRow` (default), `listTile`, `listTileReversed`, or `expandable`
  - `defaultDatePattern`, `defaultDateFirstYear`, `defaultDateLastYear`, `defaultDateMode` (`dialog` or `inline`)
  - `defaultDebounceDuration` (default `300` ms) — debounce delay for text input fields

- **Barrel file generation** — Dart and TypeScript generators now emit a single barrel/index file that re-exports all generated enums, inputs, types, and interfaces. A single import is enough to access the entire generated layer.

- **`@glExpand` directive** — controls inline expansion depth for cyclic types in `_all_fields` fragment generation. When a cycle is detected, the generator inlines the cyclic type's fields up to `depth` levels instead of emitting an invalid recursive fragment spread. Default depth is `1`. Use `depth: 0` to omit the cyclic field entirely.

  ```graphql
  type Employee @glExpand(depth: 2) {
    id: ID!
    name: String!
    manager: Employee
  }
  ```

- **Exhaustive projection reuse** — when a query projects all fields of a type completely (recursively), the generator now reuses the base type name instead of generating a new projected type name. This reduces the number of generated classes and makes generated code easier to navigate.

- **`generateAllFieldsFragments` and `autoGenerateQueries` default to `true`** — these options no longer need to be explicitly set in `config.json`; they are enabled by default.

- **Incremental file writes** — the generator now hashes each output file's content before writing. Files whose content has not changed are skipped, making repeated generation and watch mode significantly faster on large schemas.

### Fixes

- Fixed Flutter input form widget generation (state management, date fields, companion handling)
- Fixed missing import for enum list labels in generated Flutter display widgets
- Improved parse error messages now include line and column numbers

### Documentation

- Site migrated to MkDocs — all documentation pages rebuilt with improved navigation and search
- New **AI Agents** documentation page covering GraphLink's LLM-friendly design
- Configuration, client, and server docs updated throughout

---
## 4.7.1 - 2026-05-26

### Fixes

- Fixed crash when a type's common interface is a projected interface
---

## 4.8.0 - 2026-06-09

### New features

- **Kotlin client code generation** — new `clientConfig.kotlin` block in `config.json`
  - Generates typed client for queries, mutations, and subscriptions
  - Data classes for types and inputs (configurable via `typeAsDataClass` / `inputAsDataClass`)
  - `toJson` / `fromJson` serialization using `kotlinx.serialization`
  - WebSocket adapter: `okhttp` (default) or `none`
  - Enums, interfaces, and union types fully supported
  - `@glMapsTo` / `@glMapField` mapping methods generated

- **JSpecify null-safety annotations for Java** — new `jspecify: true` option in `clientConfig.java` and `clientConfig.server`
  - Adds `@NonNull` / `@Nullable` from `org.jspecify.annotations` to all generated type, input, and interface fields
  - Respects `@glSkipOnClient` / `@glSkipOnServer` and server-mode forced nullability rules
  - Imports are only emitted when the option is enabled

- **Flutter display widget improvements**
  - Serializer split into focused sub-files: `flutter_types_layout_serializer.dart`, `flutter_types_companion_serializer.dart`, `flutter_types_value_renderer.dart`, `flutter_types_constants.dart`
  - New `labelStyle` config option (`bold` / `muted`) for companion label classes
  - Generated `{Type}Widget` now includes an **agent guide header** comment block listing every field, its Dart type, and how it is rendered — makes generated widgets easier to navigate with AI tools
  - New layout helpers: `toTableRow`, `toDataRow`, `toDataColumns`, `labeledTableRows`, `listTileItems`, `expandableItems`

- **Flutter input form enhancements**
  - Async validation state per field (`_<field>Validating`, `_<field>AsyncError`, `_<field>AsyncTimer`) with debounce support
  - Field keys (`GlobalKey<FormFieldState>`) generated for every validatable field — enables `_scrollToFirstError`
  - `isDirty` getter, `scrollToFirstError`, `updateErrorsNotifier`, and `scrollToField` helpers emitted automatically
  - `setSubmitting` propagated to nested sub-input forms (stepper child forms disabled together)
  - Optional `focusNodes` parameter when text fields are present
  - New `${Input}FieldIcons` companion class — pass a `Widget?` per text or dropdown field to render as `prefixIcon` in its `InputDecoration`
  - `TextFieldOptions` gains `prefixIcon` and `suffixIcon` fields — lower-priority icon slot overridden by `FieldIcons` at the field level; password-toggle always wins the suffix
  - New `{field}Avatar` callbacks on `${Input}Widgets` — `Widget? Function(T)?` per enum field and `Widget? Function(bool)?` per bool field; rendered as `ChoiceChip.avatar` in chip/radio rows

### Fixes

- Fixed barrel file to include generated client files (Dart and TypeScript)

## 5.0.0

### Breaking changes

- **Server generation is strict by default (`@glStrict` behavior, always on)** — every server-generated type and interface now enforces real schema nullability on its fields (getters/constructors/setters), instead of the previous always-nullable server model. Every type and interface also gains a generated `GL<Type>Projection` interface (all fields nullable) to represent partially-fetched data.

  **Migration:** if you relied on server-generated types being fully nullable, annotate them with the new `@glServerLenient` directive to restore the old per-type behavior. For a resolver that only fetches part of a type based on the GraphQL selection set, annotate the operation/relation field with `@glReturnsProjection` so it returns `GL<Type>Projection` instead of the strict concrete type.

- **Generated identifiers are always normalized to the target language's casing convention** — field names, argument names, enum values, and type/input/interface/union/enum names are now unconditionally rewritten to canonical casing (e.g. lowerCamelCase fields for Dart/Java/Kotlin/TypeScript, SCREAMING_SNAKE enum values for Java/Kotlin, PascalCase enum values for TypeScript, PascalCase type names everywhere). This is not opt-in.

  **Migration:** if your schema's GraphQL names aren't already in canonical casing (e.g. `snake_case` fields, lowercase type names), regenerating will rename the corresponding generated fields/classes/methods. Review the diff after upgrading and update any application code that references generated identifiers directly.

- **Generated server controllers now return `Map`/`List<Map>` instead of typed objects** — Java Spring, Kotlin Spring, and Express/Apollo controllers serialize responses via `toJson()` at the controller boundary; service interfaces are unchanged. Any code depending on the old typed controller return type needs to be updated after regenerating.

- **Java Spring controllers bind input arguments as `Map<String, Object>`** — controller methods no longer receive Spring-bound typed input objects directly; they receive a raw map and convert it via the input's generated `fromJson`. This keeps keyword-renamed and normalized input fields correct on the wire, but any custom Jackson/Spring binding configuration relying on the previous direct-typed binding will need to be revisited.

- **Kotlin generated enum `fromJson` no longer returns null for unknown values** — signature changed from `fun fromJson(value: String?): T?` to `fun fromJson(value: String): T`; an unrecognized wire value now throws `IllegalArgumentException` instead of returning null.

- **Field-level arguments are no longer silently dropped** — arguments on nested (non-root) fields (e.g. `lastArticles(limit: Int!)`) are now detected wherever the field is selected (explicit query, fragment, or auto-generated all-fields projection) and turned into operation variables / method parameters. Regenerated client methods for existing operations that select such fields gain new parameters. To keep generated method signatures from exploding on schemas with many field-level arguments, these propagated arguments are automatically grouped into a single synthesized `<Operation>FieldArgs` input object rather than appended as a flat parameter list — see `autoGenerateQueriesArgumentLimit` below for schemas where even that isn't enough.

- **Cyclic types are always forced nullable, not just under `@glExpand`** — fields participating in a dependency cycle between types are now unconditionally nullable in generated types (default-on SCC-based cycle detection), rather than only when explicitly bounded by `@glExpand(depth: …)`. Code that force-unwraps such fields (`!` in Dart/Kotlin, non-null assumptions in Java/TS) may need updating after regeneration.

- **Auto-generated query variable names changed** — auto-generated operation variable names are now `$<fieldName><ArgName>` instead of bare `$<argName>`, to avoid collisions across fields and fragments (with further type-suffix disambiguation when the same field+arg name resolves to different types across the schema). This changes the wire-level `.graphql` query strings emitted for auto-generated operations; regenerated output will differ even though behavior is equivalent.

- **`toJson`/`fromJson` generation is now mandatory** — every language serializer (Dart, Java, Kotlin, TypeScript) previously accepted a `generateJsonMethods` flag that could suppress serialization methods on types, inputs, and interfaces. That flag has been removed: `toJson`/`fromJson` are now always generated, on both client and server, since identifier normalization and reserved-keyword renaming mean a field's generated identifier can differ from its wire name — code that reads/writes generated objects without going through `toJson`/`fromJson` can no longer assume the two match.

- **`generateTypes` / `generateInputs` removed from `serverConfig.spring` and `serverConfig.kotlinSpring`** — types, inputs, interfaces, and enums are now always generated for both the Java and Kotlin Spring server targets. `generateControllers` and `generateRepositories` remain and are now correctly honored by the Java target as well (previously only the Kotlin target respected them; Java silently generated controllers and repositories regardless of these settings). **Migration:** remove `generateTypes`/`generateInputs` from your `serverConfig.spring`/`serverConfig.kotlinSpring` config — they are now ignored if left in place — and double check `generateControllers`/`generateRepositories` reflect what you actually want, since Java now enforces them.

### New features

- **Kotlin Spring Boot server generation** — new `serverConfig.kotlinSpring` block generates Kotlin data-class types/inputs/enums, services, controllers, and repositories, mirroring the existing Java Spring server target. `typeAsDataClass`/`inputAsDataClass` control data-class vs. open-class generation; `blockingServices` (default `true`) wraps service calls in `withContext(Dispatchers.IO)`, or set to `false` for a coroutine-native service layer.

- **Reactive Java client generation** — new `asyncStyle` option in `clientConfig.java`: `blocking` (default, unchanged), `reactor`, `rxjava3`, or `mutiny`. Reactive styles wrap query/mutation results in the library's deferred-single type (`Mono`/`Single`/`Uni`) and subscriptions in the deferred-many type (`Flux`/`Observable`/`Multi`). `reactiveHttpClient` selects the default adapter's transport: `jdk` (`HttpClient.sendAsync`, works with every reactive style, no extra dependency) or `webclient` (Spring WebClient, Reactor only). File upload support was also added for the Java client in this pass.

- **`unknownScalarType` config option** — fallback target-language type for any custom GraphQL scalar not covered by `typeMappings` or `@glExternal`. Without it, an unmapped `scalar UserId` is emitted verbatim as `UserId`; set it to e.g. `"String"` (Dart), `"string"` (TypeScript), or `"Object"` (Java) to map all such scalars uniformly.

  ```json
  "typeMappings": { "ID": "String" },
  "unknownScalarType": "String"
  ```

- **Reserved-keyword-safe generated identifiers** — a GraphQL field, argument, enum value, or input field named after a target-language keyword (e.g. `default`, `return`, `object`) now gets a sanitized generated identifier (`default_`, with numeric suffixing on further collisions) while the wire/GraphQL name is preserved; applied consistently across fields, arguments, enum values, resolver parameters, `@glMapsTo` mappings, and Spring controller/service signatures for Dart, Java, Kotlin, and TypeScript. Fields whose GraphQL name starts with a leading underscore also get a safe generated name where the target language disallows or discourages it.

- **`@glExpand` cyclic-projection nullability, decoupled from opt-in usage** — see the corresponding entry under Breaking changes; SCC-based cycle detection now runs by default instead of only inside explicit `@glExpand(depth: …)` annotations.

- **Bodyless type/interface/input definitions** — a type/interface/input can now be declared with no body (`type Query { }`) as long as a later `extend` block supplies its fields, with a validation error if it's never extended. Useful for schemas split across multiple files where the root type is declared in one file and extended in others.

- **Client-side default values** — GraphQL `= value` defaults on input fields and query/mutation arguments are now emitted as real defaults/params in generated Dart, Java, Kotlin, and TypeScript code (previously parsed but silently dropped). Dart constructors become `const` where possible. The generated `.graphqls` schema output now also preserves the `= value`.

- **`@deprecated` directive support in generated code** — fields and enum values marked `@deprecated(reason: "...")` now emit the target language's native deprecation annotation (`@Deprecated` in Dart/Java/Kotlin, `@deprecated` JSDoc in TypeScript) with the reason carried through.

- **`autoGenerateQueriesFor` config option** — restrict auto-generated queries/mutations/subscriptions to an explicit allow-list per operation type, instead of auto-generating one for every root field:

  ```json
  "clientConfig": {
    "dart": {
      "autoGenerateQueriesFor": {
        "queries": ["getUser", "listOrders"],
        "mutations": ["createOrder"]
      }
    }
  }
  ```

- **`maxFragmentBodySize` config option** (default `8192`) — auto-generated `_all_fields` fragments whose serialized body exceeds this size (and any auto-generated operations depending on them) are skipped with a warning instead of emitting an oversized fragment; hand-written operations are unaffected. Set to `null` to disable the cap. Targets very large schemas (e.g. Shopify, GitHub, GitLab) where fragment bodies can reach tens of kilobytes.

- **`autoGenerateQueriesArgumentLimit` config option** (default `200`) — caps the number of propagated field arguments an auto-generated operation may accumulate before it's skipped with a warning; works alongside the automatic `<Operation>FieldArgs` grouping (see Breaking changes) as a last-resort safety valve for schemas with pathological argument counts.

- **TypeScript `toJson`/`fromJson` generation** — TypeScript types, inputs, enums, and interfaces now get generated `toJson`/`fromJson` functions bridging wire names and normalized code names (mirroring the existing Dart/Java/Kotlin behavior), and the TypeScript client decodes responses through generated `fromJson` instead of raw type casts. TypeScript interfaces implementing a union also emit a `readonly __typename: 'TypeName'` discriminant field plus a union-level `toJson()` that switches on `__typename`, completing proper discriminated-union (de)serialization.

- **Only-used fragments are emitted** — generated clients now include only the fragments actually referenced (directly or transitively) by at least one query, mutation, or subscription, shrinking generated fragment maps on large schemas.

- **Slimmer generated client code for non-cached queries** — operations with no `@glCache`-tagged fields now go through a simplified, smaller code path instead of the full partial-caching machinery, reducing generated client size; shared resolver helpers were also factored out across Dart/Java/Kotlin/TypeScript client serializers to cut duplicated boilerplate.

- **Multi-arch Docker release images** — the published `glink` Docker image is now built and released for multiple architectures.

### Fixes & improvements

- Fixed several field-level-argument propagation and cache-scoping bugs: dropped field args in partial/divided-query variable declarations, and incorrect per-query-element variable scoping.
- Fixed the default WebSocket subprotocol negotiation on the Dart/Java/Kotlin adapters and the TypeScript server/client (now consistently `graphql-transport-ws`); the TS adapter also reconnects on socket error, not just close.
- Fixed a parser crash on description strings attached to a directive/field argument.
- GraphQL spec-compliance fixes in the lexer/parser: optional leading `|`/`&` in directive-location, union-member, and `implements` lists; `extend` without a `{ }` body; `"""` inside block strings no longer prematurely terminates the string.
- Fixed a stack overflow in cyclic-fragment expansion for long non-cyclic dependency chains, and an out-of-memory issue in the large-schema fragment pipeline.
- Fixed `fromJson` dispatch when an interface extends another interface — sub-interfaces are no longer emitted as bogus concrete `case` branches.
- Fixed exponential-time field-argument-variable propagation over shared fragment graphs via memoization (large measured speedup on synthetic large-schema benchmarks); added a fast path for exhaustive projection registration on interfaces/unions.
- Fixed auto-generated response wrapper type names (`<Field>Response`) colliding with a user-declared type of the same name — falls back deterministically to `<Field><Operation>` and then a numeric suffix only on collision.
- Fixed a collision between a query and a mutation sharing the same field name.
- Fixed union "common fields" validation incorrectly accepting/rejecting fields with mismatched types across union members.
- Fixed Java interface list fields to use covariant wildcards (`List<? extends T>`) only where a server implementor actually narrows the element type, and only in server mode — client-generated list fields stay unwildcarded for ergonomic caller-side types.
- Fixed multiline and otherwise special-character `@deprecated(reason: "...")` strings producing invalid generated syntax.
- Fixed a null-default leak when merging field arguments.
- Fixed a duplicate TypeScript enum value emitted for deprecated enum members.
- Fixed a TypeScript self-import in generated import dependency resolution.
- Fixed unescaped quotes in generated Java query strings.
- Fixed an unqualified enum member reference in generated Dart/Kotlin `fromJson`.
- Fixed several identifier-normalization/keyword-safe-naming ordering bugs affecting auto-generated query codenames, and `hasQueries`/type-emission bookkeeping around fragments skipped by `maxFragmentBodySize`.
- Fixed Kotlin/Java `toJson`/`fromJson` for enums to always use explicit wire-name mapping instead of `.name`/`valueOf`, since normalization can make code names diverge from wire names even without a keyword collision.
- Fixed a TypeScript default-argument bug where a non-null-typed argument with a default value could be `undefined` at runtime and bypass the default via unguarded nullish coalescing.
- Fixed the generated Dart barrel file emitting duplicate export lines.
- Fixed a missing space between `implements ...` and the opening brace in generated Java interfaces.

