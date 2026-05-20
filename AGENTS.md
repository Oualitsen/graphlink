# GraphLink — Agent Instructions

GraphLink is a Dart CLI tool (`glink`) that reads `.graphql` schema files and generates
fully-typed client and server code for Dart/Flutter, Java, TypeScript, and Spring Boot.
The generated files have **zero runtime dependency** on GraphLink.

---

## Repository layout

```
lib/src/
  main.dart                   # CLI entry point — arg parsing, config loading, dispatch
  config.dart                 # GeneratorConfig and all per-target config types
  grammar_factory.dart        # Builds the GlSchema (grammar) from parsed tokens
  gl_grammar_io.dart          # Reads .graphql files into LogicalFile structures
  gl_grammar_extension.dart   # Computed properties on GlSchema (caching, directives, …)
  gl_grammar_maps_to_extension.dart  # @glMapsTo / @glMapField logic
  gl_grammar_upload_extension.dart   # File upload directive logic
  gl_validation_extension.dart       # Schema validation rules
  model/                      # Intermediate representation (GlSchema, GlField, GlType, …)
  generators/                 # One entry-point generator per target:
    dart_client_generator.dart
    java_client_generator.dart
    typescript_client_generator.dart
    server_generator.dart
  serializers/                # Code-writing logic — one serializer per target/concern
  tree/                       # AST / token tree used by the lexer+parser
  excpetions/                 # Custom exception types

test/                         # One subdirectory per test scenario, each with a schema
plans/                        # Design docs for past and future features (read-only context)
examples/                     # End-to-end example projects
site/                         # graphlink.dev website (MkDocs docs + custom landing page)
```

---

## Build & run

```bash
# Install dependencies
dart pub get
# or, if using fvm:
fvm flutter pub get

# Compile the CLI binary
dart compile exe lib/src/main.dart -o glink

# Install to ~/bin (must be on PATH)
make deploy

# Run without compiling (development)
dart run lib/src/main.dart -c path/to/config.json
```

---

## Tests

```bash
# Run all tests
dart test

# Run a single test directory
dart test test/gl_expand/

# Run a single test file
dart test test/gl_expand/gl_expand_test.dart
```

Tests live in `test/`. Each subdirectory is a self-contained scenario: a `.graphql` schema
plus a Dart test file that calls the generator and asserts on the output. There is no
shared test fixture — each test sets up its own grammar.

---

## Generation pipeline

```
.graphql files
    │
    ▼
grammar_factory.createGrammar(config)   → GlSchema (the "grammar")
    │
    ▼
gl_grammar_io.parseFiles(grammar, logicalFiles)   → populates grammar.types, .queries, etc.
    │
    ▼
Extension methods run automatically (gl_grammar_extension, gl_validation_extension, …)
    │
    ▼
Generator (dart/java/typescript/server) → calls serializers → writes output files
```

`GlSchema` is the central intermediate representation. Extensions on it (in
`gl_grammar_*_extension.dart`) compute derived data — which queries are cached, which
fields have upload directives, etc. — as Dart getters so generators don't duplicate logic.

---

## Key model types

| Type | Where | What it represents |
|---|---|---|
| `GlSchema` | `model/gl_schema.dart` | The entire parsed schema |
| `GlTypeDefinition` | `model/gl_type_definition.dart` | A GraphQL `type` |
| `GlInputDefinition` | `model/gl_input_definition.dart` | A GraphQL `input` |
| `GlField` | `model/gl_field.dart` | A field on a type or input |
| `GlQueries` | `model/gl_queries.dart` | All queries, mutations, subscriptions |
| `GlDirective` | `model/gl_directive.dart` | A directive instance on a field/type |
| `GeneratorConfig` | `config.dart` | Parsed `glink.json` / `glink.yaml` |

---

## Adding a feature — checklist

1. **Schema directive**: add it to `model/built_in_dirctive_definitions.dart` so the
   parser recognises it.
2. **Model access**: expose the directive's data via a getter on the relevant extension
   file (`gl_grammar_extension.dart` for most things).
3. **Generator**: call the new getter in the relevant generator (`dart_client_generator`,
   etc.) and pass it to the serializer.
4. **Serializer**: write the code-emitting logic in the relevant serializer under
   `serializers/`.
5. **Test**: add a subdirectory under `test/` with a minimal schema that exercises the
   feature and a test file that asserts the generated output.

---

## Conventions

- Generated files begin with a `// GENERATED` header comment. Never edit them manually.
- Extension files (`gl_grammar_*_extension.dart`) use Dart `extension` syntax on
  `GlSchema` or `GlGrammar`. Keep derived/computed logic there — not in generators.
- Serializers return `String` (the code to write) or write directly via `writeToFile`.
  Keep serializers pure where possible.
- Config types in `config.dart` use named constructors (`fromJson`) — add new config
  keys there and expose them as fields.
- The `plans/` directory contains Markdown design docs. Read them for background context
  on past decisions. Do not modify them.

---

## Site (graphlink.dev)

```bash
make site-dev      # Live-reload MkDocs preview at http://localhost:8000
make site-docs     # Build MkDocs docs (outputs to site/docs/)
make site-local    # Build + serve full site at http://localhost:8082
```

Doc source files live in `site/docs-src/*.md`. The built HTML is in `site/docs/`.
When editing any doc page, also update `site/llms.txt`, `site/llms-full.txt`, and
the page's SEO meta tags — see `site/CLAUDE.md` for the full sync rules.

---

## What to avoid

- Do not edit any file under a `generated/` directory — these are outputs, not sources.
- Do not modify `pubspec.lock` unless explicitly changing dependencies.
- Do not add runtime dependencies to `pubspec.yaml` without discussion — the generated
  code must remain dependency-free.
- Do not run `dart compile exe` on every code change — use `dart run` for development.
- The `examples/` projects each have their own `Makefile`. Do not run `make generate`
  across all examples unless explicitly asked (`make generate-examples`).
