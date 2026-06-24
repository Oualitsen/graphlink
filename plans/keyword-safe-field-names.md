# Keyword-safe field names in generated code

## Problem

GraphQL field/input-field/argument names are not globally reserved. A schema can
legally declare:

```graphql
input ProductFilter {
  default: Boolean   # `default` is a keyword in Dart, Java, TS, Kotlin
  class: String      # `class` is reserved in Dart/Java/Kotlin
}
```

When we emit a class property named `default` (or `class`, `new`, `void`, `is`,
`in`, `enum`, `final`, …) the generated code does not compile in the target
language. We need every emitted **identifier** that originates from a schema name
to be a legal identifier in the target language, while the **wire representation**
(GraphQL query text + JSON keys) keeps the original name.

## Key invariant: two distinct names per field

Every field currently uses a single `field.name` / `tokenInfo` token for *both*
roles. Any fix must split them:

| Role | Must use | Where it appears |
|---|---|---|
| **Code name** (identifier) | sanitized, keyword-safe | class property, constructor param, getter/setter, local var |
| **Wire name** (original) | the raw schema token | GraphQL query string, JSON key in `toJson`/`fromJson` |

If we rename `default` → `default_` in the Dart class but forget the wire name,
serialization silently breaks (server gets `default_` instead of `default`).

## Where names flow today (evidence)

- `model/gl_field.dart` — `GLField.name` is a single `TokenInfo`; no notion of a
  separate code name.
- `serializers/dart_serializer.dart`
  - `doSerializeField` (line ~109): emits `<type> <name>;` using `def.name`.
  - `fieldToJson` (line 384): `'<field.name>': <field.name><toJsonCall>` — **same
    token used as JSON key and property**. This is exactly the place a naive
    rename would break the wire format.
  - `fieldFromJson` (line 391): `<field.name>: json['<field.name>']` — same issue.
  - enum values (`doSerializeEnumDefinition`, line 46) and `toJson`/`fromJson`
    switch cases have the **same problem for enum values** (e.g. a value named
    `default` or `in`).
- `serializers/java_serializer.dart`, `typescript_serializer.dart`,
  `kotlin_serializer.dart` — parallel emission paths, each needs the same
  treatment. Kotlin can also use backticks (`` `default` ``) as an escape, which
  is a language-specific option worth considering.
- `serializers/gl_graphql_serializer.dart` — builds the GraphQL query/fragment
  text; this must **always** use the original wire name (never sanitized).
- `model/gl_query_element.dart` (`escapedToken`/`nonEscapedToken`) — projected /
  response types derive class fields from query selection tokens, so the same
  sanitization must reach projection-generated fields, not just declared types.
- Existing precedent for name translation:
  - `@glMapField` (`GLField.mapFieldTo`, `gl_grammar_maps_to_extension.dart`)
    already separates a source field name from a target name — a model for how a
    code-name override could look.
  - `gl_parser.dart` already has `_reservedEnumValues = {true,false,null}`
    (validation) and a `keywords` set for the GraphQL lexer — but **no
    target-language keyword tables exist yet**.

## Approaches (to decide together)

1. **Auto-sanitize (rename) at emit time.** Each language serializer owns a
   keyword set + a sanitize rule (e.g. append `_`, or prefix). Code name derived
   automatically; wire name untouched. Pros: zero schema changes, works for every
   schema. Cons: need a stable, collision-free rule; the renamed identifier leaks
   into the public generated API (users type `obj.default_`).

2. **Language-native escaping where available.** e.g. Kotlin backticks. Only
   partial — Dart/Java/TS have no backtick escape, so this can't be the whole
   solution.

3. **Schema-author override directive** (e.g. extend `@glMapField` / a new
   `@glRename`). Explicit, but pushes work onto the user and doesn't protect
   schemas we don't control (e.g. the GitLab schema fixture).

Likely answer: **(1) as the baseline**, with (2) for languages that support it,
and (3) available as an escape hatch.

## Open questions for discussion

1. **Sanitization rule** — trailing underscore (`default_`), prefix (`$default`,
   `gl_default`), or per-language convention? Must avoid colliding with a real
   field that already has the sanitized name.
2. **Scope of "identifier"** — fields, input fields, enum values, type names,
   argument names, query/mutation method names, generated variable names. Which
   are actually at risk? (Type names are PascalCased so lower risk; field/arg/enum
   names are the hot spots.)
3. **Keyword tables** — one shared table or per-serializer? Where do they live —
   a new `model/<lang>_reserved_words.dart`, or inside each serializer? Include
   contextual keywords and built-in type names (e.g. Dart `String`, `num`)?
4. **Wire-name plumbing** — add a `codeName` getter on `GLField` (and the enum
   value / query element equivalents) computed from a serializer-provided keyword
   set, vs. having each serializer sanitize locally at every call site. A single
   getter is safer (one place to get the toJson/fromJson split right).
5. **Cross-language parity** — the integration tests (`integration_tests/`) are
   the natural place to prove the wire format is unchanged after a rename. Add a
   schema with keyword fields to a parity suite.
6. **Collisions** — if a schema has both `default` and `default_`, the rule
   produces a clash. Detect and error, or disambiguate with a counter?

## Suggested next step

Agree on the sanitization rule + the `codeName`/wire-name split design, then
prototype in the Dart serializer only (smallest blast radius), add a focused test
under `test/` with an inline schema containing keyword field/enum names, and
verify `toJson`/`fromJson` still emit the original wire keys before fanning out to
Java / TypeScript / Kotlin.
