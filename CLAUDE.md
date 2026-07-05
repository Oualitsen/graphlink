# GraphLink — Agent Codebase Guide

GraphLink is a Dart CLI (`glink`) that reads `.graphql` schema files and generates
fully-typed client and server code for Dart/Flutter, Java, TypeScript, and Spring Boot.
Generated files have **zero runtime dependency** on GraphLink.

---

## Repository layout

```
lib/src/
  main.dart                        # CLI entry: arg parsing, config loading, dispatch
  config.dart                      # GeneratorConfig + all per-target config types
  grammar_factory.dart             # Builds GlSchema from parsed tokens
  gl_grammar_io.dart               # Reads .graphql files → LogicalFile structures
  gl_grammar_extension.dart        # Computed props on GlSchema (caching, directives …)
  gl_grammar_annotation_extension.dart
  gl_grammar_cache_extension.dart
  gl_grammar_fragment_extension.dart
  gl_grammar_maps_to_extension.dart   # @glMapsTo / @glMapField logic
  gl_grammar_projection_extension.dart
  gl_grammar_service_extension.dart
  gl_grammar_upload_extension.dart    # File upload directive logic
  gl_validation_extension.dart        # Schema validation rules
  model/                           # Intermediate representation (see Key model types)
  generators/                      # One entry-point generator per target
  serializers/                     # Code-writing logic (see Serializer map)
  tree/                            # AST / token tree used by lexer+parser
  excpetions/                      # Custom exception types

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
Extension methods run lazily (gl_grammar_*_extension.dart)
  — compute derived data as Dart getters on GLParser
    │
    ▼
Generator (dart/java/typescript/server)
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
| `GlFragment` | `model/gl_fragment.dart` | GraphQL fragment |
| `GlUnion` | `model/gl_union.dart` | Union type |
| `GlEnumDefinition` | `model/gl_enum_definition.dart` | Enum definition |
| `GeneratorConfig` | `config.dart` | Parsed `glink.json` / `glink.yaml` |

---

## Generator map

| File | Responsibility |
|---|---|
| `generators/dart_client_generator.dart` | Dart/Flutter client output |
| `generators/java_client_generator.dart` | Java client output |
| `generators/typescript_client_generator.dart` | TypeScript client output |
| `generators/server_generator.dart` | Spring Boot / Express server output |
| `generators/barrel_file_handler.dart` | Barrel/index file generation |

Each generator owns the decision of *which* files to emit and *which* serializers to
call. It does not contain string-building logic — that lives in serializers.

---

## Serializer map

```
serializers/
  gl_serializer.dart               # Base serializer interface/utilities
  gl_client_serializer.dart        # Shared client serializer base
  gl_graphql_serializer.dart       # Query string generation (shared)
  annotation_serializer.dart       # Annotation helpers
  code_generation_mode.dart        # Enum: client vs server mode
  server_serializer.dart           # Abstract server serializer base
  server_serializer_utils.dart     # Shared server utilities
  spring_server_serializer.dart    # Spring Boot controller + service interface
  spring_controller_serializer.dart
  express_apollo_server_serializer.dart  # Express/Node.js server (planned)
  dart_serializer.dart             # Dart types, inputs, enums
  java_serializer.dart             # Java types, inputs, enums
  java_imports.dart                # Java import resolution
  typescript_serializer.dart       # TypeScript types, inputs, enums
  flutter_types_serializer.dart    # Flutter widget types
  client_serializers/
    dart_client_serializer.dart    # Dart client methods (queries/mutations/subs)
    dart_client_constants.dart
    java_client_serializer.dart    # Java client methods
    java_client_operation_serializer.dart
    java_client_context.dart
    java_client_constants.dart
    typescript_client_serializer.dart
    typescript_client_constants.dart
  flutter_inputs/
    flutter_inputs_serializer.dart          # Flutter InputFormWidget generation
    flutter_inputs_companion_serializer.dart
    flutter_inputs_field_serializer.dart
    flutter_inputs_state_serializer.dart
    flutter_inputs_date_serializer.dart
    flutter_inputs_shared_serializer.dart
    flutter_inputs_type_helpers.dart
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
2. Create `serializers/client_serializers/<lang>_client_serializer.dart` for operation
   methods, and `serializers/<lang>_serializer.dart` for types/inputs/enums.
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

- **`integration_tests/`** — a hand-written, trusted Spring Boot server
  (`spring_server/`, `spring_upload_server/`) paired with GraphLink-**generated clients**
  for Dart/Java/TS/Kotlin (`*_client_tests*/`). The `_real` suites run the generated
  client against the real running Spring Boot JAR. This validates **generated client
  code** — most cross-language parity bugs have been caught here.
- **`server_integration_tests/`** — organized **per generated server target**. Each
  subdirectory pairs a GraphLink-**generated server** under test with a
  GraphLink-generated client used purely as a harness to drive requests. Currently
  `typescript/` covers the Apollo/Express server (with a generated Dart client as the
  harness). Future generated server targets get their own sibling directory here. This
  validates **generated server code**.

```bash
cd integration_tests && make all-real   # generated clients vs hand-written Spring server
cd server_integration_tests && make ci  # generated server(s) vs generated client harness
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

## Conventions

- Extension files (`gl_grammar_*_extension.dart`) use Dart `extension` on `GlSchema`.
  Keep all derived/computed logic there — not in generators or serializers.
- Serializers return `String` or write via `writeToFile`. Keep them pure where possible.
- Config types in `config.dart` use `fromJson` named constructors — add new keys there.
- Built-in directive names are defined in `model/built_in_dirctive_definitions.dart`.
- Generated files start with a `// GENERATED` header. Never edit them.
- `plans/` contains Markdown design docs for past decisions. Read-only context.

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
make site-docs     # build MkDocs docs → site/docs/
make site-local    # build + serve full site at http://localhost:8082
```

Doc sources: `site/docs-src/*.md`. Built HTML: `site/docs/`.
When editing a doc page, also update `site/llms.txt`, `site/llms-full.txt`, and SEO meta
tags — see `site/CLAUDE.md` for sync rules.
