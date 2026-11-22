# GraphLink — Agent Codebase Guide

GraphLink is a Dart CLI (`glink`) that reads `.graphql` schema files and generates
fully-typed client and server code. Clients: Dart/Flutter, Java, Kotlin, Swift, Python, Go, TypeScript.
Servers: Spring Boot (Java/Kotlin), Express, NestJS, FastAPI and Django (Ariadne).
Generated files have **zero runtime dependency** on GraphLink.

---

## Rule you must NEVER break: generate code through `CodeGenUtils`

When generating code, **always use `CodeGenUtilsBase` (`lib/src/code_gen_utils.dart`) and
its subclasses** whenever a method exists for the construct you are emitting. The
subclasses are `DartCodeGenUtils`, `JavaCodeGenUtils`, `KotlinCodeGenUtils`,
`SwiftCodeGenUtils`, `PythonCodeGenUtils`, `GoCodeGenUtils` and `TypeScriptCodeGenUtils` (`lib/src/<lang>_code_gen_utils.dart`).

- If a builder exists for it (`ifStatement`, `inlineIfStatement`, `block`, `createMethod`,
  `createClass`, `tryCatchFinally`, `switchStatement`, `forEachLoop`, `forLoop`,
  `ternaryOp`, `callExpression`, `constDecl`, `functionLiteral`, `listArg`, …), you MUST use it. Never
  write the same construct as a hand-built string, e.g. `'if (x) { ... }'`,
  `'try { ... } catch (_) { ... }'` or a triple-quoted class/method.
- Check the language's `*CodeGenUtils` for an existing method **before** writing any
  generated control-flow, method, or class text.
- Check this every time you add or change generated code, including small one-line `if`
  guards and edits to existing serializers. "It was already a string" is not a reason to
  add another one.
- Only when no method exists for the shape may you compose the pieces by hand, as
  described under "Code-gen string building" below.

---

## Rule: decisions live in the IR, serializers only render

Everything that can be *decided* (which decorator/annotation applies, on what, with which
arguments, which import it needs, whether a member is skipped or nullable) is computed on the
IR (`parser_extensions/` getters, or a directive added to the element) and unit-tested there
with an inline schema. A serializer only turns an already-decided value into text with the
language's `*CodeGenUtils`.

- **Annotations and decorators.** User-declared `@glAnnotation` / `@glDecorators` flow through
  `GLGrammarAnnotationExtension` (`handleAnnotations` / `convertAnnotationsToDecorators`).
  The IR never emits syntax: each language passes a `String Function(GLDirectiveValue)` that
  renders one annotation in its own syntax (Java/Kotlin/Dart today). The serializer then reads
  the result with `serializeDecorators`. A new target or backend MUST wire this up, even if it
  ignores `@glAnnotation` at first, and MUST NOT hand-build user decorators.
- **Framework decorators** (`@Query`, `@ResolveField`, `@binding.field(...)`, `@router.get(...)`)
  are not user data, but *which one* and *its arguments* are decided on the IR (a getter that
  returns a small value, e.g. a resolver kind plus wire name). The serializer only renders it
  and passes it to `createMethod(decorators: ...)`. No string gluing like `'$decorator\n$method'`.
- **Test first.** A new rule gets an IR test (no generated string) before any serializer test.
- Resolver bindings live in `gl_grammar_resolver_binding_extension.dart` (`GLResolverBinding`:
  kind + wire name); NestJS and Ariadne (FastAPI, Django) render it. User annotations are
  rendered by `typescript_annotation_serializer.dart` and `python_annotation_serializer.dart`
  (`glImport` is a verbatim import line there). Express has no decorators.

---

## Repository layout

```
lib/src/
  main.dart                        # CLI entry: arg parsing, config loading, dispatch
  config.dart                      # GeneratorConfig + all per-target config types
  grammar_factory.dart             # createGrammar(config) → GLParser; buildExtraGql()
  gl_grammar_io.dart               # Reads .graphql files → GLLogicalFile structures
  code_gen_utils.dart, <lang>_code_gen_utils.dart  # CodeGenUtils builders (see rule above)
  io_utils.dart                    # writeToFile(), cleanUpObsoleteFiles()
  parser_extensions/               # Computed getters on GLParser — ALL derivation logic lives here
    gl_grammar_extension.dart      # Core: decorators, skip-on-server, common getters
    gl_grammar_{annotation,cache,fragment,projection,service,upload}_extension.dart
    gl_grammar_maps_to_extension.dart, gl_grammar_mapped_to_type_extension.dart  # @glMapsTo / @glMapField
    gl_grammar_rest{,_arguments,_validation,_response,_discriminator,_nullable,_server}_extension.dart  # @glRest*
    gl_grammar_openapi_extension.dart  # buildOpenApiDocument(): every IR → OpenAPI mapping rule
    gl_grammar_resolver_binding_extension.dart  # GLResolverBinding: which resolver decorator a root/type field gets
    gl_grammar_{scalar_codec,strict,throwing_decode,source,intercept,defaults,hoist_args}_extension.dart
    gl_grammar_{keyword,member_conflict,normalization,recursion,directive_validation}_extension.dart
    gl_validation_extension.dart   # validateSemantics(): schema validation rules
  model/                           # Intermediate representation (see Key model types)
  generators/                      # One entry-point generator per target
  serializers/                     # Code-writing logic (see Serializer map)
  tree/                            # AST / token tree used by lexer+parser
  exceptions/                      # ParseException(message, TokenInfo)

test/                              # One subdirectory per scenario (schema + test file)
plans/                             # Design docs for past/future features (read-only)
examples/                          # End-to-end example projects per language
site/                              # graphlink.dev website (MkDocs + custom landing page)
```

---

## Generation pipeline

```
.graphql files
    │
    ▼
grammar_factory.createGrammar(config)           → GLParser instance
    │
    ▼
gl_grammar_io.parseFiles(parser, logicalFiles)  → populates parser.types, .queries …
    │
    ▼
Extension methods run lazily (parser_extensions/gl_grammar_*_extension.dart)
  — compute derived data as Dart getters on GLParser
    │
    ▼
Generator (one per client target, server, openapi)
  — iterates GLParser, calls serializers
    │
    ▼
Serializers → emit String code → write output files
```

`GLParser` (`model/new_parser/gl_parser.dart`) is the central IR that flows through the
entire pipeline. Extensions on it add computed getters (cached queries, upload fields,
mapped inputs, etc.) so generators never duplicate derivation logic.

---

## Key model types

| Type | File | What it represents |
|---|---|---|
| `GLParser` | `model/new_parser/gl_parser.dart` | Central object holding the entire parsed schema (types, inputs, queries, fragments, enums, unions, …) — this is what generators receive |
| `GLSchema` | `model/gl_schema.dart` | Model for the GraphQL `schema { query: … }` declaration block — maps operation types to their root type names |
| `GlTypeDefinition` | `model/gl_type_definition.dart` | GraphQL `type` |
| `GlInputDefinition` | `model/gl_input_definition.dart` | GraphQL `input` |
| `GlField` | `model/gl_field.dart` | Field on a type or input |
| `GlQueries` | `model/gl_queries.dart` | All queries, mutations, subscriptions |
| `GlDirective` | `model/gl_directive.dart` | Directive instance on a field/type |
| `GLRestOperation` | `model/gl_rest_operation.dart` | Resolved `@glRest` operation (see `rest-client-specs.md`); lives in `GLParser.restOperations`, not in `queries` |
| `GlFragment` | `model/gl_fragment.dart` | GraphQL fragment |
| `GlUnion` | `model/gl_union.dart` | Union type |
| `GlEnumDefinition` | `model/gl_enum_definition.dart` | Enum definition |
| `GeneratorConfig` | `config.dart` | Parsed `glink.json` / `glink.yaml` |

---

## Generator map

| File | Responsibility |
|---|---|
| `generators/dart_client_generator.dart` | Dart/Flutter client output |
| `generators/java_client_generator.dart` | Java client output (blocking and reactive flavors) |
| `generators/kotlin_client_generator.dart` | Kotlin client output |
| `generators/swift_client_generator.dart` | Swift client output |
| `generators/typescript_client_generator.dart` | TypeScript client output |
| `generators/python_client_generator.dart` | Python client output (a package with `__init__.py` barrel) |
| `generators/go_client_generator.dart` | Go client output (one flat package, no barrel) |
| `generators/server_generator.dart` | Server output: Spring (Java/Kotlin), Express, NestJS, FastAPI, Django (dispatches on config) |
| `generators/openapi_generator.dart` | OpenAPI spec + docs page for REST operations (`openapi` config section); servers serve it |
| `generators/barrel_file_handler.dart` | Barrel/index file generation |

Each generator owns the decision of *which* files to emit and *which* serializers to
call. It does not contain string-building logic — that lives in serializers.

---

## Serializer map

```
serializers/
  gl_type_naming.dart              # Root of the base chain: typeMap, resolveCodeName()
  gl_import_rendering.dart         # extends GLTypeNaming: import lines
  gl_serializer.dart               # extends GLImportRendering: abstract base for types/inputs/enums
  gl_mapping_serializer.dart       # @glMapsTo contract (toMethod); <lang>/<lang>_mapping_serializer.dart implement it
  json_expressions.dart            # shared toJsonExpr/fromJsonExpr logic
  openapi_serializer.dart          # GLOpenApiDocument → OpenAPI 3.1 JSON (openapi_constants.dart: Swagger UI page)
  spring_openapi_controller_serializer.dart  # Spring GraphLinkOpenApiController (Java/Kotlin)
  gl_client_serializer.dart        # Shared client serializer base
  gl_graphql_serializer.dart       # Query string generation (shared)
  annotation_serializer.dart       # Annotation helpers (shared by Dart/Java/JVM)
  code_generation_mode.dart        # Enum: client vs server mode
  server_serializer.dart           # Abstract server serializer base
  server_serializer_utils.dart     # Shared server utilities
  jvm_spring_server_serializer_base.dart      # Shared Java/Kotlin Spring server base
  jvm_spring_controller_serializer_base.dart  # Shared Java/Kotlin Spring controller base
  jvm_spring_rest_controller_serializer_base.dart  # Shared Java/Kotlin Spring REST controller planning (`@glRest*` on the server)
  dart/
    dart_serializer.dart           # Dart types, inputs, enums
    dart_mapping_serializer.dart
    flutter_api.dart               # Flutter SDK/design-library switches
    flutter_types_serializer.dart  # Flutter widget types
    flutter_types/                 # layout, value renderer, companion, constants
    flutter_inputs/
      flutter_inputs_serializer.dart          # Flutter InputFormWidget generation
      flutter_inputs_companion_serializer.dart
      flutter_inputs_field_serializer.dart
      flutter_inputs_date_serializer.dart
      flutter_inputs_number_serializer.dart  # (+ flutter_inputs_number_constants.dart)
      flutter_inputs_state_serializer.dart    # State class assembly + build()/validate()
      flutter_inputs_widget_serializer.dart   # The InputFormWidget (Form) class
      flutter_inputs_rows_serializer.dart     # _visibleRows, per-field row methods, build context
      flutter_inputs_read_serializer.dart     # read()/tryRead()/buildResult
      flutter_inputs_reset_serializer.dart    # reset() and isDirty
      flutter_inputs_change_serializer.dart   # onFieldChanged, onChange scheduling, async validation
      flutter_inputs_stepper_serializer.dart  # Stepper steps and controls
      flutter_inputs_layout_helpers_serializer.dart  # label/field/decoration helpers
      flutter_inputs_error_summary_serializer.dart   # Error summary widget, scroll-to-error
      flutter_inputs_draft_serializer.dart    # Draft persistence (persistDrafts): snapshot/restore/save
      flutter_inputs_radio_binding.dart       # RadioListTile vs RadioGroup per SDK version
      flutter_inputs_shared_serializer.dart
      flutter_inputs_type_helpers.dart
  java/
    java_serializer.dart           # Java types, inputs, enums
    java_imports.dart              # Java import resolution
    java_interface_serializer.dart # interface bodies, covariant list getters, __typename fromJson (javaSerializer.interfaces)
    java_accessor_serializer.dart  # constructors, builders, getters/setters (javaSerializer.accessors)
    java_mapping_serializer.dart
    java_spring_server_serializer.dart      # Spring Boot service interface
    java_spring_controller_serializer.dart  # Spring Boot controllers
    java_spring_rest_controller_serializer.dart  # Spring Boot REST controllers
    spring_map_type_resolver_config.dart
    spring_rest_support.dart, spring_source_support.dart, spring_subscription_transport_config.dart  # static Spring runtime files
  kotlin/
    kotlin_serializer.dart         # Kotlin types, inputs, enums
    kotlin_imports.dart            # Kotlin import resolution
    kotlin_mapping_serializer.dart
    kotlin_spring_server_serializer.dart
    kotlin_spring_controller_serializer.dart
    kotlin_spring_rest_controller_serializer.dart
    kotlin_map_type_resolver_config.dart
    kotlin_spring_rest_support.dart, kotlin_source_support.dart, kotlin_subscription_transport_config.dart  # static Spring runtime files
  typescript/
    typescript_serializer.dart     # TypeScript types, inputs, enums
    express_apollo_server_serializer.dart   # Express/Apollo server
    express_apollo_server_constants.dart
    express_apollo_rest_serializer.dart     # Express REST router (`@glRest*` served by the server)
    express_apollo_rest_constants.dart      # runtime support of that router (`rest/support.ts`)
    typescript_apollo_server_base.dart      # shared by Express and NestJS: contracts, loaders, context, import helpers
    nest_apollo_server_serializer.dart      # NestJS: abstract-class services, @Resolver/@ResolveField classes, GraphLinkModule
    nest_apollo_rest_serializer.dart        # NestJS @Controller per service for `@glRest*`, 404/405 fallback
    nest_apollo_server_constants.dart       # NestJS runtime (REST support derived from Express, request guards)
  swift/swift_serializer.dart      # Swift types, inputs, enums (+ swift_mapping_serializer.dart)
  python/python_serializer.dart    # Python (pydantic v2) types, inputs, enums (+ python_mapping_serializer.dart)
  python/python_openapi_serializer.dart  # FastAPI router / Django urlpatterns serving the OpenAPI spec and docs
  python/python_ariadne_server_serializer.dart  # shared Ariadne server base: Protocol services/guards, resolvers, loaders, GraphLinkServices
  python/fastapi_ariadne_server_serializer.dart  # FastAPI entry point (create_app)
  python/django_ariadne_server_serializer.dart   # Django entry point (create_urlpatterns with the GraphQL view, create_app for WebSocket)
  python/fastapi_rest_serializer.dart, django_rest_serializer.dart  # request/response types of the shared REST handlers
  python/python_ariadne_server_constants.dart    # static runtime (loader, source support, depth guard, WS handler, Django view and WebSocket wrapper)
  python/python_rest_serializer.dart             # abstract: framework-neutral route table for `@glRest*`
  python/python_rest_constants.dart              # REST runtime: framework-neutral core, Starlette and Django support/uploads/downloads, FastAPI router, Django urls
  go/go_serializer.dart            # Go (structs + json tags) types, inputs, enums (+ go_mapping_serializer.dart)
  client_serializers/              # one subdirectory per language
    <lang>/<lang>_client_serializer.dart            # facade: generateClient, queries/mutations/subscriptions classes
    <lang>/<lang>_client_operation_serializer.dart  # per-operation code
    <lang>/<lang>_client_constants.dart             # static runtime templates
    <lang>/<lang>_client_vars.dart                  # reserved generated identifiers
    <lang>/<lang>_rest_operation_serializer.dart    # methods for GLRestOperations (runtime in <lang>_rest_constants.dart)
    <lang>/<lang>_client_runtime_serializer.dart    # resolver base, cache, APQ, WS handler, exceptions, uploads (clientSerializer.runtime)
    <lang>/<lang>_client_adapters_serializer.dart   # HTTP/WS/REST transport adapters (clientSerializer.adapters)
                                   # runtime/adapters: Dart, Java, Kotlin, TypeScript, Python only; Swift and Go keep it in one file
    java/, kotlin/                 # also *_client_context.dart; java/java_reactive_flavor.dart (Reactor/RxJava 3/Mutiny)
```

---

## Adding a new directive (feature)

1. **Register it** — add to `model/built_in_dirctive_definitions.dart` so the parser
   accepts it without a validation error.
2. **Expose it** — add a getter on the relevant extension file
   (`gl_grammar_extension.dart` for schema-wide, `gl_grammar_cache_extension.dart` for
   cache-related, etc.). Keep derivation logic here, not in generators.
3. **Generate it** — call the new getter in the relevant generator and pass the result to
   the serializer.
4. **Emit it** — write the code-string logic in the relevant serializer under
   `serializers/`.
5. **Test it** — add a subdirectory under `test/` with a minimal `.graphql` schema and a
   Dart test file that asserts on the generated output string.

---

## Adding a new target language

1. Create `generators/<lang>_client_generator.dart` (or `<lang>_server_generator.dart`).
2. Create `serializers/client_serializers/<lang>/<lang>_client_serializer.dart` for operation
   methods, and `serializers/<lang>/<lang>_serializer.dart` for types/inputs/enums.
3. Add a new config section to `config.dart` (follow the pattern of `DartClientConfig`).
4. Wire the new generator into `main.dart` dispatch logic.
5. Add end-to-end examples under `examples/<lang>/`.

---

## Test structure

```
test/
  new_parser/          # Lexer + parser unit tests for every grammar construct
  queries_mutations/   # Query/mutation code generation
  cache/               # @glCache / @glCacheInvalidate generation
  maps_to/             # @glMapsTo / @glMapField (input mapping)
  upload/              # File upload directive
  fragments/           # Fragment generation and referencing
  interface/           # Interface and common-field handling
  inheritence/         # Type inheritance scenarios
  extensions/          # GraphQL schema extensions
  projections/         # Projected types derived from query selection sets/fragments (not a directive)
  input/               # Input type generation
  input_types_ref_check/
  base_types_and_unions/
  similar_types/
  schema_merging/      # Multi-file schema merging
  batch_mappging/      # Batch query generation
  queries_auto_gen/    # Auto-generated query strings
  serializers/         # Serializer unit tests
  server/              # Server (Spring Boot) generation
  java/                # Java-specific generation
  dart/                # Dart-specific generation
  client/              # Client mode tests
  responses/           # Response type generation
  validation/          # Schema validation error tests
  parse_errors/        # Parser error handling
  gl_expand/           # Query expansion
  gl_internal/         # Internal utilities
  rest/, rest_nullable/  # @glRest* IR and generation, @glRestNullable
  openapi/             # OpenAPI document generation
  kotlin/              # Kotlin-specific generation
  scalars/, strict/, throwing_decode/  # scalar codecs, strict decoding
  persisted_queries/   # APQ
  <lang>_serializer_tests/  # go, python, swift, typescript serializer unit tests
  ...
```

Each test is self-contained and builds its own `GlSchema`. There is no shared fixture.

**Define the schema as an inline `const String` in the Dart test file — do NOT read a
separate `.graphql` file.** Pass it straight to `parser.parse(schema)`. Reserve external
`.graphql` files only for genuinely large fixtures (e.g. the real-world `gitlab_schema/`
schema); every normal test keeps its schema inline as a `const`.

```dart
const schema = '''
type Query { product(id: ID!): Product }
type Product { id: ID! name: String }
''';

test('...', () {
  final g = GLParser(/* flags */);
  g.parse(schema);
  expect(/* assert on generated output */);
});
```

```bash
fvm dart test test/cache/              # single directory
fvm dart test test/cache/cache_test.dart  # single file
# fvm dart test (no path) runs ALL tests — do NOT run without asking the user first
```

This project uses **fvm** (Flutter Version Manager) — always prefix `dart`/`flutter`
commands with `fvm` (e.g. `fvm dart test`, `fvm dart run ...`, `fvm dart pub get`).

### Running tests — mandatory rules

**Never run the full test suite (`fvm dart test` with no path).** It is slow and floods
the context. Only run the specific directory or file relevant to your change. If you
believe a full run is genuinely needed, STOP and ASK the user first — do not run it on
your own initiative.

**Never run a test command and read its raw output directly.** Test output is huge and
fills the context window. Always redirect to a log file and only grep for failures:

```bash
fvm dart test test/cache/ > /tmp/test.log 2>&1; grep -E "FAILED|Error|✗" /tmp/test.log
```

If you need more detail on a specific failure, grep the log file for that test's name —
do not cat/Read the whole log. If this constraint can't be satisfied for some reason,
stop and ask the user to run the tests manually instead.

---

## End-to-end integration tests

Two top-level directories outside `test/`, testing opposite ends of the pipeline —
don't confuse them:

- **`integration_tests/`** — GraphLink-**generated clients** for Dart/Java/TS/Kotlin/Swift/Python/Go,
  split in two groups. `mock/` (`*_client_tests/`, schema in `schema_mock/`) runs them
  against canned-response adapters, no server. `real/` (`*_client_tests_real/`, schema in
  `schema_real/`) runs them against a hand-written, trusted Spring Boot server
  (`real/spring_server/`, `real/spring_upload_server/`) JAR. This validates **generated
  client code** — most cross-language parity bugs have been caught here.
  The reactive GraphQL suites `real/java_client_tests_{reactor,rxjava3,mutiny}_real` share `schema_real/` and derive most of their tests
  from `java_client_tests_real` via `real/generate_reactor_tests.dart` into a git-ignored `src/test/generated/` (`.block()` appended for
  Reactor, each call wrapped in the package's `Rx.block(...)` for RxJava 3 and Mutiny). The flavor-neutral hand-written tests
  (`SubscriptionsTest`, the mock adapter core and the multipart adapter core) live once in `real/java_reactive_shared/`; each package
  adds only its `Rx` helper and thin `MockAdapter` / `RealMultipartAdapter` wrappers. `SubscriptionReconnectTest` is blocking/Reactor only.
  Edit the blocking test, not the derived copy.
- **REST operations** (`@glRest*`, Kotlin client): `mock/kotlin_rest_tests` and `real/kotlin_rest_client_tests_real` (OkHttp, port 9994,
  Gradle `--offline` works with a warm cache). Run with `make -C integration_tests kotlin-rest kotlin-rest-real`.
- **REST operations** (`@glRest*`, Java client): one mock and one real package per flavor, all against `real/schema_rest/`.
  Blocking: `mock/java_rest_tests` (canned `GLRestAdapter`) and `real/java_rest_client_tests_real` (JDK `HttpClient`, port 9987).
  Reactive: `mock/java_rest_{reactor,rxjava3,mutiny}_tests` and `real/java_rest_{reactor,rxjava3,mutiny}_client_tests_real`
  (ports 9980, 9979, 9978; the real ones use `real/rest_server/server.py`). The three mock packages compile one shared
  `mock/java_rest_reactive_shared` test source, and the three real ones share `real/java_rest_reactive_shared`; each package only
  adds a small `Rx` helper (`block`, `failure`) and, for the mocks, a `MockRest`. The reactive real packages derive the rest of
  their tests from the blocking package via `real/generate_reactor_tests.dart` (`.block()` for Reactor, `Rx.block(...)` for RxJava 3
  and Mutiny, which return `Maybe`/`Completable`/`Uni`). Edit the blocking test, not the derived copy. `java_rest_reactor_client_tests_real`
  also reruns its tests against the Spring `WebClient` REST adapter (`webclient/` variant, `make variants`). Run with
  `make -C integration_tests java-rest java-rest-reactor java-rest-rxjava3 java-rest-mutiny` and the same names with `-real`.
- **`@glRestNullable`** (lenient REST responses): every REST real package has a lenient test (`LenientTest` / `lenient_test` / `LenientTests`) against the
  `/lenient/*` routes of `real/rest_server/server.py` and the `lenient*` / `strict*` operations of `real/schema_rest/rest.graphql`: partial payloads
  decoded into the `*Rest` copies, a polymorphic list, a union, a cached call, and the strict twins on the same payload that must fail.
  Swift has no strict twins: every Swift `fromJson` throws on a missing non-null field, so its strict types need no separate case. The Java reactive
  packages derive `LenientTest` from the blocking one.
- **Fault injection** (bad responses): `real/fault_server/server.py` arms one fault per request (`POST /_arm?fault=<name>`); `fault_server/cases.json`
  is the one table of cases every language reads. Each REST real package has a fault test (`fault_test.dart`, `FaultTest.java`, `FaultTest.kt`,
  `fault.test.ts`, `test_faults.py`, `FaultTests.swift`, `fault_test.go`) on its own fault port (9950 to 9969, see each Makefile; shared recipe in
  `fault_server/fault.mk`). A language's open defects are skipped in its `knownDefects` map with the reason; remove the entry when fixed.
  Add a fault in `server.py` and a row in `cases.json`, then run every language.
  The same server speaks `graphql-transport-ws` for the GraphQL real packages (`fault_server/ws_cases.json`, `POST /_arm?fault=ws-...&times=N`,
  `GET /_ws_log`); each has a `ws_faults` test (`ws_faults_test.dart`, `WsFaultsTest.java`, `WsFaultsTest.kt`, `ws-faults.test.ts`,
  `test_ws_faults.py`, `WsFaultsTest.swift`, `ws_faults_test.go`) (open defects go in `KNOWN_DEFECTS` / `knownDefects`, none today). Fault ports 9940 to 9947 (the same server also serves a 10 MB GraphQL response, `huge-users`, to each package's `HugeResponseTest`); the reactive Java packages run `WsFaultsStreamsTest` from `java_reactive_shared/` on 9948, 9949 and 9955.
  The same server (`--live`) stands in for Spring in the reconnect tests: they start and kill it per port (it serves `labelTicks`, `secureTicks`, their `*Starts` queries and `Ack-Delay` like Spring), so no suite needs `SERVER_JAR` any more.

- **Uploads** (GraphQL multipart and REST, streaming rules shared by every client): one `*_client_upload_tests_real` package per target
  (`dart` and `dart_dio`, `java` with JDK/OkHttp variants, `java_reactor` with JDK/WebClient variants, `kotlin`, `typescript`, `python`,
  `swift`, `go`). Each runs the same real-socket tests against an in-process recording server (6 MB sha256, Content-Length for known
  lengths, chunked for unknown, progress ends at the total, no read-ahead, no progress when the length is unknown, two-file list) and,
  when `UPLOAD_SERVER_URL` is set, against `real/spring_upload_server` (ports 9998/9991). Swift uses `recording_server.py` (port 9970).
  Run with `make -C integration_tests <lang>-upload-real` (e.g. `go-upload-real`). When changing an upload runtime, change every target's
  rules together and rerun these.
- **REST operations** (`@glRest*`, Go client): `mock/go_rest_tests` and `real/go_rest_client_tests_real` (net/http, port 9981;
  `comma/` output reruns the same tests on 9982). Run with `make -C integration_tests go-rest go-rest-real`.
- **REST operations** (`@glRest*`, Swift client): `mock/swift_rest_tests` and `real/swift_rest_client_tests_real` (URLSession, port 9983;
  `comma/` output reruns the same tests on 9984). Needs Xcode. Run with `make -C integration_tests swift-rest swift-rest-real`.
- **REST operations** (`@glRest*`, Python client): `mock/python_rest_tests` and `real/python_rest_client_tests_real` (httpx, port 9985;
  `REST_VARIANT=comma` reruns the same tests against `comma/` output on 9986). Run with
  `make -C integration_tests python-rest python-rest-real`.
- **REST operations** (`@glRest*`, TypeScript client): `mock/typescript_rest_tests` and `real/typescript_rest_client_tests_real`
  (fetch on port 9993; `REST_VARIANT=axios` reruns the same tests against `axios/` output on 9989). Run with
  `make -C integration_tests typescript-rest typescript-rest-real`.
- **REST operations** (`@glRest*`, Dart client): `mock/dart_rest_tests` (canned adapter) and
  `real/dart_rest_client_tests_real` + `real/dart_rest_dio_client_tests_real` against `real/rest_server/server.py`
  (stdlib Python; `/echo/**` reports what arrived on the wire, other routes are CRUD, counters, uploads/downloads,
  status codes). Schema in `real/schema_rest/`. The Dio package runs the same tests (imported from the http package's
  `test/`) with `REST_VARIANT=dio` (COMMA lists, BRACKET nesting) on port 9996; the http package uses 9995.
  Run with `make -C integration_tests dart-rest-real dart-rest-dio-real` (needs `python3`).
- **`integration_tests/persisted_queries/`** — the persisted-queries (APQ) suites, kept apart from the
  ones above: `mock/` (canned `ApqServer`), `real/` (against `spring_persisted_queries_server`, ports
  9997/9992) and a shared `schema/`. Own `Makefile` (`make -C integration_tests persisted-queries`) and
  own workflow `.github/workflows/persisted-queries.yml`.
- **`server_integration_tests/`** — a **client x server matrix**: every generated
  server target (`servers/`) driven by every generated client harness (`clients/`).
  `servers/` holds one subdirectory per generated server target (`typescript_server`,
  `typescript_upload_server`, `java_server`, `java_server_reactive`,
  `kotlin_server_blocking`, `kotlin_server_suspend`, `python_fastapi_server`, `python_django_server`, `nestjs_server`,
  plus upload, GraphQL-only and REST-only variants and the shared `python_impl/`) — flat, not grouped by language.
  `clients/` holds one subdirectory per generated client harness (`dart_client`,
  `ts_client`, `java_client`, `java_reactive_client`, `kotlin_client`, `python_client`, `swift_client`, `go_client`,
  plus `dart_upload_client` for the upload-only suite). The top-level `Makefile` has one `ci-<server>-client` target per
  server (parameterized by `CLIENT=dart|ts|java|kotlin|...`) so any client can be pointed at
  any server. This validates **generated server code**.

- **Server start/stop and the fault suite**: every server Makefile includes `server_integration_tests/scripts/server.mk` (`scripts/server.sh`
  waits for HTTP and WebSocket readiness, stops by process group, never kills a port it did not start). `server_faults/` sends malformed and
  hostile requests (`cases.json`, runner `run_faults.py`) to each server; defects not fixed yet are in `known_defects.json` (remove an entry when
  fixed, a passing known defect fails the run). Run with `make -C server_integration_tests ci-faults-<typescript|java|java-reactive|kotlin-blocking|kotlin-suspend>`.
  Progress and findings: `server_integration_tests/HARDENING.md`.
- **REST on the server**: `schema_rest/rest.gql` (merged into every server's schema, never into a client's) holds `@glRest*` operations; every
  server implements them (`impl/RestImpl.*`, `rest-impl.ts`) and `server_rest/` (`cases.json`, runner `run_rest.py`) drives all of them over raw HTTP.
  Run with `make -C server_integration_tests ci-rest-<typescript|java|java-reactive|kotlin-blocking|kotlin-suspend>`; `ci-http-<server>` runs the fault
  and the REST suite on one server start (what CI does). Covers paths, query, headers, JSON, forms, nested and JSON-text values, uploads, downloads,
  `responsePath`, `@glIntercept` / `@glInjectContext`. Design and limits: `server_integration_tests/REST_SERVER.md`.
- **GraphQL data on the server**: `server_graphql/` (`cases.json`, runner `run_graphql.py`, `known_defects.json`) checks the exact `data` every server returns:
  every root field, the emitted schema (introspection), server-side defaults, batch mappings with several parents, mapTo types, null propagation and
  subscriptions over raw WebSocket. Part of `ci-http-<server>`; alone with `make -C server_integration_tests ci-graphql-<server>`. Open bugs:
  `server_integration_tests/reports/SERVER_GRAPHQL.md`.
- **Python server (FastAPI + Ariadne)**: `servers/python_fastapi_server` (port 9975, own `.venv`; `graphql-core` is pinned below 3.2.14 because Ariadne's enum
  patch breaks on it). Services return pydantic models and the resolvers hand `to_json()` dicts to Ariadne, with `__glSource__` carrying the real instance to
  schema mappings, like Express. Run with `make -C server_integration_tests ci-http-python-fastapi` (faults, REST and GraphQL suites) and
  `make -C server_integration_tests ci-python-fastapi-client CLIENT=dart`. GraphQL multipart uploads and `@glRest*` uploads are served; the upload suite runs the Dart harness against
  `servers/python_upload_server` (port 9974) with `make -C server_integration_tests ci-upload-python`.
  The Django flavor (`djangoAriadne`, `servers/python_django_server` port 9972, upload server 9971) shares `servers/python_impl/` with both and runs with `ci-http-python-django`, `ci-python-django-client CLIENT=dart` and `ci-upload-python-django`.
  Both frameworks also have GraphQL-only and REST-only servers (`python_{fastapi,django}_{graphql,rest}_server`, ports 9923/9922/9921/9920; `ci-http-python-<framework>-<graphql|rest>`, all at once with `ci-http-python-modes`): the REST schema is `schema_rest/rest.gql`, the GraphQL one next to it is `rest_graphql.gql`.
- **NestJS server**: `servers/nestjs_server` (port 9926; Nest 11, `@nestjs/apollo` 13 on Apollo Server 5; its `impl/` is a copy of the Express one, keep them in step).
  Services are abstract classes provided in `app.module.ts`; the app needs `rawBody: true` for form-encoded REST. Run with `make -C server_integration_tests ci-http-nestjs`
  (faults, REST and GraphQL suites) and `make -C server_integration_tests ci-nestjs-client CLIENT=dart`; uploads with `make -C server_integration_tests ci-upload-nestjs`
  (`servers/nestjs_upload_server`, port 9927). Express and NestJS share `typescript_apollo_server_base.dart`: change shared output once and regenerate both.
- **Java 8**: `make -C server_integration_tests java8-check` compiles the generated Java clients with `javac --release 8` (`scripts/java8_check.sh`;
  the `java11` transports excepted). Fails today, see `server_integration_tests/reports/JAVA8_COMPAT.md`.

```bash
cd integration_tests && make all-real                              # generated clients vs hand-written Spring server
cd server_integration_tests && make ci-java-client CLIENT=kotlin    # one client x one server
cd server_integration_tests && make java                            # all 4 clients vs the Java MVC server
```

---

## Build & run

```bash
fvm dart pub get                       # install deps
fvm dart run lib/src/main.dart -c path/to/config.json   # run without compiling
fvm dart compile exe lib/src/main.dart -o glink          # compile binary
make deploy                        # compile + install to ~/bin
```

---

## Creating a PR

Use `~/bin/pr.sh <branch-name>` — the branch name doubles as the commit message and
PR title, so keep it short and descriptive (`feature/...`, `fix/...`, `chore/release-X.Y.Z`).

```bash
~/bin/pr.sh fix/watch-debounce
```

The script does everything in one go, from the current branch:

1. `git checkout -b <branch-name>` — **do not create the branch beforehand**, the script fails if it exists
2. `git add .` — stages everything, including untracked files; check `git status` first
3. commit (message = branch name), `git push -u origin`
4. `gh pr create` then `gh pr merge --squash --admin --delete-branch` — **merges
   immediately and bypasses CI**
5. checks out the base branch again and pulls

Because it merges on the spot, never run it without the user explicitly asking. Before
running it for a release, bump `pubspec.yaml` and add the `CHANGELOG.md` entry first.

---

## Conventions

- Extension files (`gl_grammar_*_extension.dart`) use Dart `extension` on `GlSchema`.
  Keep all derived/computed logic there — not in generators or serializers.
- Serializers return `String` or write via `writeToFile`. Keep them pure where possible.
- Config types in `config.dart` use `fromJson` named constructors — add new keys there.
- Built-in directive names are defined in `model/built_in_dirctive_definitions.dart`.
- Generated files start with a `// GENERATED` header. Never edit them.
- `plans/` contains Markdown design docs for past decisions. Read-only context.

### Code-gen string building (`*CodeGenUtils`, e.g. `SwiftCodeGenUtils`)

Every target language has a `<Lang>CodeGenUtils` class implementing `CodeGenUtilsBase`
(`swift_code_gen_utils.dart`, similarly for Dart/Kotlin/Java/TypeScript) with block-builders (`block()`, `method()`/`createMethod()`,
`structDecl()`, `protocolDecl()`, `ifStatement()`, `tryCatchFinally()`,
`switchStatement()`, `forEachLoop()`, …). Serializers must build class/function/control-flow
bodies through these, not through hand-formatted string templates.

- **Never hand-indent with string concatenation.** Don't write `'    $x'` per line or
  `.join(',\n    ')`. Build the joined string first, then indent it once with the
  `ident()` extension (`extensions.dart`) — it walks every line of a multi-line string
  and skips blank lines.
- **Prefer the `*CodeGenUtils` builders over raw triple-quoted templates.** If a
  `'''...'''` string is assembling a class, function, `if`, or `do`/`catch`, check for an
  existing helper before writing it as text.
- **Trailing commas: join, don't append-then-join.** For comma-separated multi-line
  lists (args, struct fields), use `list.join(',\n')` — never
  `list.map((e) => '$e,').join('\n')`, which leaves a trailing comma before the closing
  bracket/paren (a hard parse error on Swift <6.1/Linux CI, confirmed by real regressions).
- **When no helper fits a shape** (e.g. a closure header with a named parameter like
  `{ continuation in ... }`, which `block()` can't express), compose the inner pieces
  with the utils helpers anyway and splice them under a manual header/footer, still
  applying `.ident()` — don't fall back to a fully manual multi-line string.
- **`GLClassModel` is file-level only** (imports + body glue via `toFileContent()`). It
  never renders a class/struct body itself — that's always the language's
  `*CodeGenUtils`.

### Comments

Write way fewer comments. Let the code speak for itself — clear names, small
functions, and obvious structure beat prose.

- Default to no comment. Only add one when it captures a non-obvious *why*
  (a hidden constraint, an edge case being deliberately excluded, a workaround
  for a specific bug) that isn't derivable from reading the code itself.
- Never write a comment that restates what the next line already says
  (`// loop over fields` above a `for (var f in fields)`).
- No doc comments (`///`) on private helpers whose name and signature already
  say what they do. Reserve `///` for public API where callers can't see the
  implementation.
- Don't narrate the change history, the task that prompted the code, or which
  caller uses it — that belongs in the commit message, not the source.
- Prefer expressing the "why" through a well-named variable/function over a
  comment explaining a poorly-named one.

---

## What to avoid

- Never edit files under `generated/` directories — they are outputs.
- Do not modify `pubspec.lock` unless explicitly changing dependencies.
- Do not add runtime dependencies to `pubspec.yaml` — generated code must stay
  dependency-free.
- Do not run `dart compile exe` on every change — use `dart run` for development.
- Do not run `make generate` across all `examples/` unless explicitly asked
  (`make generate-examples`).

---

## Site (graphlink.dev)

```bash
make site-dev      # live-reload MkDocs preview at http://localhost:8000
make site-docs     # build MkDocs docs → site/dist/
make site-local    # build + serve full site at http://localhost:8082
```

Doc sources: `site/docs-src/*.md`. Built HTML: `site/dist/` (served from the site root).
`llms.txt`, `llms-full.txt`, `llms/<page>.txt` and `sitemap.xml` are generated by the build
hook from `docs-src/` — edit the sources (and the page's frontmatter `title`/`description`),
never `dist/`. See `site/CLAUDE.md` for the rules.
