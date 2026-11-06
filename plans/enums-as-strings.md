# Enums as strings (client option)

Status: draft plan, nothing implemented. Open questions at the bottom need answers before step 1.

## Decisions so far

- Scope is **clients and servers** (Spring Java/Kotlin, Express). (Q2)
- `enumsAsStrings` together with `strictEnums` is a **configuration error**, not a silent override. (Q3)
- A **constants holder is generated** in string mode, one per declared enum, named after the enum. (Q4)
- The schema is untouched: enums stay enums in the SDL and in the query text. Only the generated code changes.
  Defaults use the wire value as a string literal. (Q8)

## Goal

An opt-in client option that makes every enum reference generate as the language's string type, so a value the
client has never seen cannot break decoding and can be sent back unchanged. The decision is made in the IR;
serializers stay dumb.

Not the goal: replacing `strictEnums`/tolerant enums. Tolerant enums (`unknownValue__`, `strictEnums: false`)
stay the default for frontends.

## What exists today (read from the code)

- `GLParser.enums: Map<String, GLEnumDefinition>`. `GLEnumDefinition` keeps directives (`GLDirectivesMixin`),
  documentation, per-value directives (`@deprecated` -> `isDeprecated` / `deprecationReason`), `codeName`
  normalisation and keyword-safe names.
- Tolerant enums are already an IR concern: `createGrammar` passes `tolerantEnums: !lang.strictEnums` to `GLParser`,
  and at the end of parsing `GLParser` calls `addUnknownValue()` on every non-`@glInternal` enum. Serializers
  only read `def.unknownValue`. `strictEnums` is a field on every client config in `config.dart` and in
  `graphlink_generator_builder.dart`, `cli_help.dart`.
- `grammar.isEnum(token)` (`gl_validation_extension.dart`) is the branch point. ~30 serializer sites use it to
  decide "convert through `fromJson`/`toJson`" or to resolve a type: Dart (`castDynamicToType`, `callToJson`),
  Java, Kotlin, Swift, TypeScript, Python, Go serializers, the client operation serializers (Dart, Java, Kotlin,
  Swift, Python incl. REST), `gl_client_serializer.dart` (collects enum/input argument tokens to import),
  Spring controllers.
- Type names resolve through `GLSerializer.resolveCodeName`, which falls back through
  `types -> interfaces -> projectedTypes -> inputs -> enums -> unions -> wireToken`, then `typeMap`.
- Enum defaults (`= USER`) go through `enumConstantName` / `serializeDefaultLiteral` (per language).
- Flutter (Dart only) builds dropdown/radio widgets and `*Labels` classes from `parser.enums` and reads
  `GlUiEntity` enum names (`gl_ui_entity.dart`, `flutter_types_*`, `flutter_inputs_*`).
- The GraphQL query strings (`gl_graphql_serializer.dart`) print the original type tokens, for example
  `$status: Status!`. They must keep doing so.

## Hard constraints

1. **Do not mutate the type token or `nullable`.** The `__gl_query__` text and the schema SDL read
   `GLType.token`; rewriting `Status` to `String` would send `$status: String!` and the server would reject it.
   (Same constraint as `plans/default-values.md`.)
2. **The enum definition stays in `parser.enums`** with its values and directives. Only how references resolve
   changes.
3. **Serializers do not read the option.** They ask the IR. No `if (config.enumsAsStrings)` in a serializer.
4. Both modes. Server mode has no `tolerantEnums` today (`createGrammar` does not pass it on the server branch)
   and the server configs have no `strictEnums`, so the server needs its own flag and its own verification.
5. No new runtime dependency; generated code stays dependency-free.

## Design

### Config

- New `enumsAsStrings: bool` (default `false`) on every client language config and on the server configs
  (`SpringServerConfig`, `ExpressApolloServerConfig`) in `config.dart` `fromJson`, builder keys, `cli_help.dart`.
- Setting it together with `strictEnums: true` fails config loading with a message naming both keys.
- `createGrammar` passes it to `GLParser` as `enumsAsStrings` on both the client and the server branch.

### IR

- In `GLParser`, when `enumsAsStrings` is on, **do not call `addUnknownValue()`** (no sentinel member needed).
- Split the meaning of `isEnum` in a way that keeps the existing ~30 call sites correct without editing their logic:
  - `isEnum(token)`: "is generated as an enum type". Returns `false` when `enumsAsStrings` is on.
  - new `isEnumDefinition(token)` (or `declaresEnum`): "the schema declares this enum". Always true for declared
    enums. Used by GraphQL serialization, Flutter, validation, imports of definitions, and anywhere the definition
    itself is needed.
  - Every `grammar.enums[...]` direct lookup in a serializer must be reviewed: it is either "needs the definition"
    (keep) or "resolve the type name" (route through the IR).
- Type-name resolution: a single IR-owned answer to "what type name do I print for this token", so
  `resolveCodeName` returns the string type (via `typeMap['String']`) for enum tokens in string mode instead of
  the enum's `codeName`. Today this logic lives in the serializer base class; it should read an IR getter.
- Defaults: `enumConstantName` and `serializeDefaultLiteral` branch on the IR answer, so `= USER` becomes the
  string literal `"USER"` (wire value, not the normalised constant name).
- Constants holder: the generator still emits one file per declared enum, but its content is a holder of
  `String` constants built from the retained definition (wire value as the value, `codeName` as the identifier,
  `@deprecated` carried over, documentation kept). Files that use an enum no longer import the enum as a type;
  they reference the holder only if a default literal or similar needs it, otherwise not at all.
  `gl_client_serializer.dart` argument-token collection (lines ~169 and ~245) must stop treating the enum as an
  import of a type.
- Holder shape per language (to confirm during the Dart-first step): Dart `abstract final class` with
  `static const String`; Java `final class` with `public static final String`; Kotlin `object` with `const val`;
  TypeScript `as const` object; Swift `enum`-less namespace with `static let`; Python class with constants;
  Go a `const` block (Go has no namespaces, so identifiers need the enum name as prefix; collision rules needed).
- Directives that stay meaningful on the retained definition: `@deprecated` on values (constants holder or
  doc comment), annotations/decorators on the enum, `@glInternal` (skip), `@glExternal`. Directives on a
  *field* of enum type are unaffected. Which of these have an effect on a plain `String` field is question 5.

### Generators and serializers

- Generators emit the holder file in place of the enum file; the IR flag selects which serializer method runs.
- Serializers: add nothing language-specific except the holder emitter (one small method per language, built
  through `*CodeGenUtils`, no hand-built strings).
- Languages: Dart, Java, Kotlin, TypeScript, Swift, Python, Go. Port from Dart first (project rule), then the others.

### Server mode (needs its own investigation)

Not yet read: `jvm_spring_*_serializer_base.dart`, `java/kotlin_spring_*`, `express_apollo_server_*`.
Things to verify before writing code:

- What Spring for GraphQL does when a controller parameter is `String` for a GraphQL enum argument, and when a
  field resolver returns a `String` for an enum field (graphql-java validates the returned value against the
  declared enum values; an undeclared value is an error). I believe this works but have not verified it.
- Spring controllers have `grammar.isEnum` sites (`jvm_spring_controller_serializer_base.dart` lines ~330, ~374)
  and the interceptor tag enum (`glInterceptorTagEnumName`) is an internal enum that must stay a real enum, or the
  interceptor feature needs its own treatment.
- Express/Apollo: the TS enum import paths (`express_apollo_server_serializer.dart` ~388, ~430, ~540, ~967).
- Mapped inputs (`@glMapsTo`) and schema mappings that copy enum fields between types.
- `server_integration_tests/` matrix: every server target times every client, now with both modes on each side.

### Flutter

Flutter UI generation depends on the enum definition (labels, dropdown values). Options in question 6. Until
decided, `enumsAsStrings` plus Flutter widgets is rejected at config validation, not silently degraded.

## Steps (TDD, IR-first)

1. IR unit tests (`test/enums_as_strings/`, inline `const` schemas, no generation yet):
   - flag off: behaviour unchanged (`isEnum` true, tolerant `unknownValue` present).
   - flag on: `isEnum` false, `isEnumDefinition` true, no `unknownValue`, definition and directives intact,
     type token untouched, type-name resolution returns the string type for fields, list elements, arguments,
     input fields, and nested list-of-list.
   - defaults: `Role = USER` resolves to the string `"USER"`; list and nested defaults.
   - code names: wire value is used, not the normalised or keyword-safe constant name.
2. Config plumbing (`config.dart`, builder, CLI help) with a validation test for conflicting options.
3. Dart serializer and client operation serializer: generated output tests asserting `String` fields and no
   enum file or import.
4. Mock integration (`integration_tests/mock/dart_client_tests`): new enum-as-string variant, see question 7.
5. Repeat for Java, Kotlin, TypeScript, Swift, Python, Go, each followed by its mock package.
6. REST: path, query, header, form and multipart enum parameters, and enum response fields, in every
   `*_rest_tests` package. The REST operation serializers have their own `isEnum` sites
   (`python_rest_operation_serializer.dart`, `swift_rest_operation_serializer.dart`, ...).
7. Real-server run (`real/*_client_tests_real` variant) to prove an unknown value round-trips: read a record
   containing a value the schema does not declare, send it back, server receives it unchanged.
8. Docs (`site/docs-src/`) and `CHANGELOG.md` entry; update `ARCHITECTURE.md`/`CLAUDE.md` only if the
   `isEnum` split changes the documented rules.

## Risks

- ~30 `isEnum` call sites change meaning. A missed `grammar.enums[...]` lookup would still produce the enum type
  name in string mode; step 1 type-resolution tests and the per-language compile in mock packages are the net.
- Generated query strings must still declare enum variables with the enum name (constraint 1). Needs an explicit
  test on `__gl_query__` output in string mode.
- Cache keys: if cache keys are built from serialised arguments, enum arguments must serialise identically in
  both modes only if the cache is shared across modes (it is not). Confirm.
- Swift `toJson()` and Go/Python decoders currently special-case the `unknownValue__` member; none of that code
  should run in string mode.

## Open questions

Answered: scope (both), both-options (error), holder (generate), default literal (wire string). See Decisions.

1. **Name and shape of the option.** `enumsAsStrings: bool`, or fold `strictEnums` into a three-state
   `enums: "typed" | "strict" | "string"`? The three-state version is cleaner (and makes the conflict error
   impossible) but is a config change right before release.
2. **Why servers?** The motivation for clients (old app, new value) does not obviously apply to a server, which
   owns the schema and graphql-java rejects undeclared values anyway. Which server problem does this solve?
   The answer decides whether server support is full parity or a smaller subset (for example arguments only).
3. **Directives that must survive.** I only confirmed `@deprecated` on values, `@glInternal` and `@glExternal`
   on enums. Which others do you attach to enums or enum values? With the holder they can be carried over.
4. **Flutter.** Dropdowns/radios need the value list. Reject the combination, or generate the widgets from the
   retained definition while the field type is `String`?
5. **Test strategy.** Rerun each existing package with a string-mode output (like `REST_VARIANT=comma`), or a
   smaller dedicated test set per language? The same question applies to the server matrix.
6. **Interceptor tag enum.** Should `glInterceptorTagEnumName` stay a real enum in string mode?
7. **Release timing.** Part of the unreleased 6.0.0 changelog entry, or its own minor version?
