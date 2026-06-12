# GraphLink — Architecture Reference for AI Agents

> Read this before touching any code. It maps every layer of the pipeline,
> every key file, and every extension point so you can orient quickly.

---

## What this tool does

`glink` reads `.graphql` schema files and emits fully-typed client/server code
for Dart/Flutter, Java, Kotlin, TypeScript, and Spring Boot.
Generated files have **zero runtime dependency** on GraphLink.

---

## Pipeline (data flow)

```
CLI args + config file
        │
        ▼
  GeneratorConfig          ← config.dart
        │
        ▼
  createGrammar()          ← grammar_factory.dart
  + buildExtraGql()
        │
        ▼
  GLParser (populated)     ← model/new_parser/gl_parser.dart
        │  parsed by gl_grammar_io.dart
        │  enriched by gl_grammar_*_extension.dart (lazy getters)
        │
        ▼
  Generator per target     ← generators/*.dart
        │  decides WHICH files to emit, WHICH serializers to call
        │
        ▼
  Serializers              ← serializers/**/*.dart
        │  pure string builders — no schema-derivation logic here
        │
        ▼
  writeToFile / barrel     ← io_utils.dart, barrel_file_handler.dart
```

---

## Entry points

| File | Role |
|---|---|
| `lib/src/main.dart` | CLI: parses args, loads config, calls generators |
| `lib/src/grammar_factory.dart` | `createGrammar(config)` → `GLParser`; `buildExtraGql()` |
| `lib/src/gl_grammar_io.dart` | `parseFiles(parser, files)` — reads `.graphql` → `GLLogicalFile` |
| `lib/src/config.dart` | All config types (`GeneratorConfig`, `DartClientConfig`, …) |
| `lib/src/io_utils.dart` | `writeToFile()`, `cleanUpObsoleteFiles()` |

---

## Central IR — `GLParser`

**File:** `lib/src/model/new_parser/gl_parser.dart`

This is the single object that flows through the entire pipeline.
After `parseFiles()` it holds the complete parsed schema.
Extension files hang computed getters off it (see Extensions section).

Key collections:

| Property | Type | What it holds |
|---|---|---|
| `types` | `Map<String, GlTypeDefinition>` | GraphQL `type` blocks |
| `inputs` | `Map<String, GlInputDefinition>` | GraphQL `input` blocks |
| `enums` | `Map<String, GlEnumDefinition>` | GraphQL `enum` blocks |
| `interfaces` | `Map<String, GlInterfaceDefinition>` | GraphQL `interface` blocks |
| `unions` | `Map<String, GlUnionDefinition>` | GraphQL `union` blocks |
| `scalars` | `Map<String, GlScalarDefinition>` | Custom scalars |
| `queries` | `GlQueries` | All operations (query/mutation/subscription) |
| `fragments` | `Map<String, GlFragmentDefinition>` | Named fragments |
| `services` | `List<GLService>` | Server service definitions |
| `controllers` | `List<GLController>` | Server controller definitions |
| `schema` | `GLSchema?` | The root `schema { }` block |
| `projectedTypes` | computed | Types filtered for client projection |
| `directiveDefinitions` | `Map<String, GLDirectiveDefinition>` | All known directives |

---

## Model types (IR)

All under `lib/src/model/`.

| File | Key Class | Represents |
|---|---|---|
| `gl_type_definition.dart` | `GlTypeDefinition` | GraphQL `type` |
| `gl_input_definition.dart` | `GlInputDefinition` | GraphQL `input` |
| `gl_field.dart` | `GlField` | Field on a type or input |
| `gl_type.dart` | `GLType`, `GLListType` | Type expressions (nullable, list) |
| `gl_queries.dart` | `GLQueryDefinition`, `GLQueryType` | Operations |
| `gl_query_element.dart` | `GLQueryElement` | Field selections in an operation |
| `gl_enum_definition.dart` | `GLEnumDefinition`, `GLEnumValue` | Enum |
| `gl_fragment.dart` | `GLFragmentDefinition`, `GLProjection` | Fragments & projections |
| `gl_union.dart` | `GLUnionDefinition` | Union type |
| `gl_directive.dart` | `GLDirectiveValue`, `GLDirectiveDefinition` | Directive instances |
| `gl_interface_definition.dart` | `GLInterfaceDefinition` | Interface type |
| `gl_schema.dart` | `GLSchema` | Root `schema { }` block |
| `gl_scalar_definition.dart` | `GlScalarDefinition` | Custom scalar |
| `gl_input_mapping.dart` | `GLInputMapping` | `@glMapsTo` / `@glMapField` |
| `token_info.dart` | `TokenInfo` | Source location (line/col/file) |
| `built_in_dirctive_definitions.dart` | — | Registers all built-in directives |

---

## Extension files (schema enrichment)

These hang **lazy computed getters** off `GLParser` (or `GlSchema`).
**All derivation logic must live here** — never in generators or serializers.

| File | What it adds |
|---|---|
| `gl_grammar_extension.dart` | Core utilities: decorator extraction, skip-on-server, common getters |
| `gl_grammar_cache_extension.dart` | `@glCache` / `@glCacheInvalidate` directives |
| `gl_grammar_annotation_extension.dart` | Annotation (`@`-prefixed) handling |
| `gl_grammar_fragment_extension.dart` | Fragment dependency graph, typed fragments |
| `gl_grammar_maps_to_extension.dart` | `@glMapsTo` / `@glMapField` input mapping |
| `gl_grammar_projection_extension.dart` | Derives "projected types" — minimal types from query selection sets/fragments (not a directive) |
| `gl_grammar_service_extension.dart` | Service/repository definitions for server mode |
| `gl_grammar_upload_extension.dart` | File upload mutation detection |
| `gl_validation_extension.dart` | `validateSemantics()` — schema validation rules |

---

## Generators

Under `lib/src/generators/`. Each generator:
- receives `(GLParser, outputPath, GeneratorConfig, DateTime)`
- returns `Future<Set<String>>` of written file paths
- decides *which* files to emit
- calls serializers for string content
- never does schema derivation

| File | Target |
|---|---|
| `dart_client_generator.dart` | Dart/Flutter client |
| `java_client_generator.dart` | Java client |
| `kotlin_client_generator.dart` | Kotlin client |
| `typescript_client_generator.dart` | TypeScript client |
| `server_generator.dart` | Spring Boot or Express server (dispatches on config) |
| `barrel_file_handler.dart` | Barrel/index file generation (abstract base) |

---

## Serializers

Under `lib/src/serializers/`. All extend `GLSerializer` (`gl_serializer.dart`).
Each serializer **only builds strings** — no schema queries.

### Base

| File | Class | Role |
|---|---|---|
| `gl_serializer.dart` | `GLSerializer` | Abstract base — `typeMap`, `serializeType()`, `serializeField()`, `serializeEnumDefinition()`, `serializeInputDefinition()`, `serializeTypeDefinition()` |
| `code_generation_mode.dart` | `CodeGenerationMode` | Enum: `client` / `server` |
| `gl_graphql_serializer.dart` | `GLGraphqlSerializer` | Emits GraphQL syntax (query strings) |
| `gl_client_serializer.dart` | — | Shared client serializer base |

### Language type/input/enum serializers

| File | Class | Default type map |
|---|---|---|
| `dart_serializer.dart` | `DartSerializer` | ID→String, Float→double, Int→int, Boolean→bool |
| `java_serializer.dart` | `JavaSerializer` | ID→String, Float→Double, Int→Integer, Boolean→Boolean |
| `kotlin_serializer.dart` | `KotlinSerializer` | ID→String, Float→Double, Int→Int, Boolean→Boolean |
| `typescript_serializer.dart` | `TypeScriptSerializer` | ID→string, Int/Float→number, Boolean→boolean |

### Client operation serializers

Under `serializers/client_serializers/`:

| File | Class | Generates |
|---|---|---|
| `dart_client_serializer.dart` | `DartClientSerializer` | Dart adapter, queries, mutations, subscriptions |
| `java_client_serializer.dart` | `JavaClientSerializer` | Java adapter, OkHttp, WebSocket |
| `kotlin_client_serializer.dart` | `KotlinClientSerializer` | Kotlin coroutines adapter, OkHttp, WebSocket |
| `typescript_client_serializer.dart` | `TypeScriptClientSerializer` | TypeScript fetch adapter, observables |
| `java_client_operation_serializer.dart` | `JavaClientOperationSerializer` | Per-operation Java classes |
| `kotlin_client_operation_serializer.dart` | `KotlinClientOperationSerializer` | Per-operation Kotlin classes |
| `*_client_constants.dart` | — | Static GraphQL constant strings per language |
| `*_client_context.dart` | — | Generation context tracker per language |

### Server serializers

| File | Class | Generates |
|---|---|---|
| `server_serializer.dart` | `ServerSerializer` | Abstract base for server generation |
| `server_serializer_utils.dart` | — | Shared server utilities |
| `spring_server_serializer.dart` | `SpringServerSerializer` | Spring Boot services + interfaces |
| `spring_controller_serializer.dart` | `SpringControllerSerializer` | Spring REST controllers |
| `express_apollo_server_serializer.dart` | `ExpressApolloServerSerializer` | Express/Apollo resolvers |

### Flutter serializers

| Directory/File | Generates |
|---|---|
| `flutter_types_serializer.dart` | Flutter display widgets for types |
| `flutter_types/flutter_types_layout_serializer.dart` | Layout widgets (rows, columns, expandable) |
| `flutter_types/flutter_types_value_renderer.dart` | Value rendering per type |
| `flutter_inputs/flutter_inputs_serializer.dart` | `InputFormWidget` entry point |
| `flutter_inputs/flutter_inputs_field_serializer.dart` | Per-field input widgets |
| `flutter_inputs/flutter_inputs_state_serializer.dart` | Form state management |
| `flutter_inputs/flutter_inputs_companion_serializer.dart` | Companion/state classes |
| `flutter_inputs/flutter_inputs_date_serializer.dart` | Date picker widgets |

---

## Config types

All in `lib/src/config.dart`. Parsed from `glink.json` / `glink.yaml`.

```
GeneratorConfig
├── DartClientConfig      (.dart)
├── JavaClientConfig      (.java)
├── KotlinClientConfig    (.kt)
├── TypeScriptClientConfig (.ts)
├── SpringServerConfig    (Spring Boot)
├── ExpressApolloServerConfig (Express)
└── FlutterConfig         (Flutter widgets + forms)
```

Enums for adapter/codec selection:
- `DartHttpAdapter`, `TypeScriptHttpAdapter`, `JavaWsAdapter`, `KotlinWsAdapter`, `JavaJsonCodec`

---

## Lexer / Parser internals

Under `lib/src/model/new_parser/` and `lib/src/tree/`.
Normally you don't need to touch these unless changing grammar.

| File | Class | Role |
|---|---|---|
| `gl_lexer.dart` | `GLLexer` | Tokenizes `.graphql` text |
| `gl_lexer_token.dart` | `GLLexerToken` | A single token with type/value/offset |
| `gl_token_type.dart` | `GLTokenType` | Enum of all token types |
| `gl_parser.dart` | `GLParser` | Parses token stream → IR (also the central IR object) |
| `tree/tree.dart` | — | AST utilities |

---

## Utility files

| File | Purpose |
|---|---|
| `extensions.dart` | String/List extension methods used across generators |
| `utils.dart` | File path helpers, naming conventions, type resolution |
| `dart_code_gen_utils.dart` | Dart-specific helpers (imports, nullable syntax) |
| `java_code_gen_utils.dart` | Java-specific helpers (imports, generics) |
| `kotlin_code_gen_utils.dart` | Kotlin-specific helpers |
| `typescript_code_gen_utils.dart` | TypeScript-specific helpers |
| `capture_errors_utils.dart` | `@glCaptureErrors` directive handling |
| `cache_store_dart.dart` | Dart cache storage codegen |
| `cache_store_java.dart` | Java cache storage codegen |
| `annotation_serializer.dart` | Java annotation (`@`-prefix) emission |
| `java_imports.dart` | Java import resolution |
| `kotlin_imports.dart` | Kotlin import resolution |
| `exceptions/parse_exception.dart` | `ParseException(message, TokenInfo)` |

---

## How to add a new directive

1. **Register** — add to `model/built_in_dirctive_definitions.dart`
2. **Expose** — add a lazy getter to the relevant `gl_grammar_*_extension.dart`
3. **Generate** — call the getter in the relevant generator
4. **Emit** — write the string logic in the relevant serializer
5. **Test** — add `test/<feature>/` with a `.graphql` + Dart test asserting output

## How to add a new target language

1. `generators/<lang>_client_generator.dart` — orchestration
2. `serializers/<lang>_serializer.dart` — types/inputs/enums
3. `serializers/client_serializers/<lang>_client_serializer.dart` — operations
4. `config.dart` — new config class + wire into `GeneratorConfig`
5. `main.dart` — dispatch to new generator
6. `examples/<lang>/` — end-to-end example

---

## Tests

```bash
dart test                              # all tests
dart test test/cache/                  # single suite
dart test test/cache/cache_test.dart   # single file
```

Each directory under `test/` is self-contained: one `.graphql` schema + one Dart
test file. No shared fixtures — each test builds its own `GLParser`.

Notable suites: `new_parser/`, `queries_mutations/`, `cache/`, `maps_to/`,
`upload/`, `fragments/`, `server/`, `java/`, `dart/`, `validation/`

---

## End-to-end integration tests (top-level, outside `test/`)

Two separate top-level directories, easy to confuse — they test **opposite ends** of the
pipeline:

| Directory | What's hand-written (trusted) | What's generated (under test) | Validates |
|---|---|---|---|
| `integration_tests/` | Spring Boot server (`spring_server/`, `spring_upload_server/`) | Clients for Dart/Java/TS/Kotlin (`*_client_tests*/`) | **Generated CLIENT** code against a real server |
| `server_integration_tests/` | A generated client (driver/harness, currently Dart under `typescript/dart_client/`) | A **generated server target** (currently Apollo/Express under `typescript/typescript_server/`, `typescript_upload_server/`) | **Generated SERVER** code for that target against a real client |

In `integration_tests/`, the `_real` suites (`dart_client_tests_real/`, etc.) run the
generated client against the actual running Spring Boot JAR — this is where most
cross-language parity bugs (fragment argument propagation, query variable scoping, etc.)
have been caught.

`server_integration_tests/` is organized **per generated server target** — `typescript/`
currently covers the Apollo/Express server, with a generated Dart client used purely as
a harness to drive requests. As more server targets are generated (e.g. a future
generated Spring Boot output, Go, etc.), each gets its own sibling directory here
following the same pattern: generated server under test + a generated client as harness.

```bash
cd integration_tests && make all-real        # generated clients vs hand-written Spring server
cd server_integration_tests && make ci        # generated server(s) vs generated client harness
```

---

## Build commands

```bash
dart pub get
dart run lib/src/main.dart -c path/to/config.json   # run (dev)
dart compile exe lib/src/main.dart -o glink          # compile
make deploy                                          # compile + install to ~/bin
make site-dev                                        # MkDocs live preview
```

---

## Hard rules for AI agents

- **Never edit** files under `generated/` directories — they are outputs.
- **Never put derivation logic** in generators or serializers — it goes in `gl_grammar_*_extension.dart`.
- **Never put string-building logic** in extension files or generators — it goes in serializers.
- **Never add runtime dependencies** to `pubspec.yaml` — generated code must be dependency-free.
- **Do not run** `dart compile exe` or `make generate-examples` unless explicitly asked.
- Config keys live in `config.dart` `fromJson` constructors — add new ones there.
- Built-in directive names are the single source of truth in `model/built_in_dirctive_definitions.dart`.
