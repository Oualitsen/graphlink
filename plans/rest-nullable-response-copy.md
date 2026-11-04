# REST responses: `@glRestNullable` (nullable copy of the response type)

Status: implemented (objects, lists, interfaces, unions). Tests: `test/rest_nullable/` (config, copy, interface, validation) and a
lenient test in every REST real package. See "Implementation notes" at the end.

## Problem

REST operations take their response type from the GraphQL schema, so nullability is whatever the schema says. That schema is
often the *target* GraphQL contract (non-null fields) while the legacy REST API it fronts omits fields or sends `null`.
Today a missing non-null field fails the call (`Type.field is missing or null in the response`).

Types are shared between REST and GraphQL operations, so loosening `Product` would loosen the GraphQL operations too.
An opted-in REST operation therefore gets its own generated copy of the response type.

## Decisions

1. **Directive:** `@glRestNullable`, on the REST operation. A separate directive, not an argument of `@glRest`.
2. **Copy name:** type name + suffix, default `Rest` (`Product` -> `ProductRest`). One project-wide option, never per operation.
3. **Fields:** every field of the copy is nullable, at every depth. Only the outermost level of a field changes.
4. **List elements:** driven by the schema. `[Product!]!` -> `[ProductRest!]`, `[Product]!` -> `[ProductRest]`,
   `[[Int!]!]!` -> `[[Int!]!]`. A `null` element in a non-null-element list still fails fast.
5. **No conversion** back to the original type, now or later (it would be misused).
6. **Top-level result nullability** (`Product!` vs `Product`) stays derived from the schema.
7. **Arguments and inputs:** untouched. Results only.
8. **Where copies live:** `projectedTypes` / `projectedInterfaces`. No new registry, no serializer or generator changes.
9. **Name collision** with an existing type is a validation error naming both and the suffix option.
10. **Nested copies:** same suffix; one shared copy per type.
11. **Interfaces and unions are in v1.** Unions are already converted to interfaces (`fromUnion`), so both take one path.
12. **Misuse is a validation error:** the directive on a text, binary or void response, on a response with nothing to copy
    (a scalar or enum result), or on a field that is not a REST operation.

13. **`@glTypeName` stays GraphQL-only, with a REST-specific error.** It names the generated types of GraphQL documents
    (selections, operations, fragments) and `input` types. REST has no selection set, and a per-operation name would break decisions 2
    and 10. Checked on the current code: on a REST field it is already rejected, but with the generic placement message
    (`@glTypeName cannot be used on FIELD_DEFINITION (allowed: FIELD, INLINE_FRAGMENT, ...)`), which never mentions REST. Replace it for
    REST operations with a dedicated error, e.g. "`@glTypeName` does not apply to REST operations: the result type is named by the
    schema type, and a `@glRestNullable` copy by the `<suffix>` option". It is not accepted on a `type` either (see spike 7), so the copy's
    code name is simply `<token><suffix>`.

## Consequences to document

- Moving an operation to GraphQL changes its result type from `ProductRest` to `Product`. The directive is an explicit
  opt-in and an exception to "remove the directive and the call site does not change".
- The copy is deep: every object type reachable from the response is copied. Enums and scalars are reused.
- The discriminator of an interface is a wire property read from the raw JSON, normally not a schema field, so making
  fields nullable never touches it.

## What was read (facts the design relies on)

- Client pipeline in `GLParser.parse` (`model/new_parser/gl_parser.dart`) runs, in order: `resolveRestOperations()`,
  `validateRestOperations()`, `resolveRestDiscriminators()`, ..., `createProjectedTypes()`, `registerRestResponseTypes()`,
  `cleanProjectedInterfacesImplementations()`, `fixProjectedInterfaceConflicts()`, `addClientTypesToProjectedTypes()`.
- `registerRestResponseTypes()` (`parser_extensions/gl_grammar_rest_extension.dart`) registers the *original* declared types
  as projected, via `_registerAllFieldsBlind` -> `addToProjectedTypes(type, similarityCheck: false)`, wiring
  `type.addImplementation(impl)` / `impl.addInterface(type)` for interfaces. It does not create copies.
- `restReachableTypeNames` / `_computeReachable()` in the same file walks everything reachable from the REST response types
  (fields plus, for an interface, its implementers). Today it is rooted at all REST operations.
- `cleanProjectedInterfacesImplementations()` removes from each projected interface every implementation whose token is not in
  `projectedTypes`. Copies must be registered **before** it runs.
- `fixProjectedInterfaceConflicts()` groups a projected interface's implementations by `derivedFromType?.token ?? impl.token`
  and splits groups of two or more. Leave `derivedFromType` null on copies so each is its own group.
- `restDiscriminators` is keyed by the parent's token and holds `GLRestDiscriminator(parent, field, valueByType)`.
  `valueByType` is already fully resolved (`declared[m] ?? m`). Dart, Java, Kotlin, TypeScript, Python and Go look it up by
  the interface token; Swift looks it up by `wireToken` (to confirm for copies).
- `GLRestOperation` (`model/gl_rest_operation.dart`) has a final `GLField field`. All serializers read `op.field.type`.
  `allowsEmptyBody` is computed from the field's type nullability in `resolveRestResponse`.
- Directives are declared in SDL in `model/internal_directive_declarations.dart`
  (e.g. `directive @glRestDiscriminator(field: String!, values: GLMap) on INTERFACE | UNION`), with name constants in
  `model/built_in_dirctive_definitions.dart`.
- A project-wide parser option travels: top-level `GeneratorConfig` field (`config.dart`, e.g. `disableCache`) ->
  `grammar_factory.dart` -> `GLParser` constructor parameter.
- `applyServerLenientNullability()` (`parser_extensions/gl_grammar_strict_extension.dart`) has the `_toFullyNullable` shape to
  reuse, except it also makes list elements nullable; here elements follow the schema.
- Note for tooling: `parser_extensions/gl_grammar_projection_extension.dart` contains bytes that make plain `grep` treat it as
  binary. Use `grep -a`.

## Design

### Directive and option
- Add `const glRestNullable = "@glRestNullable"` and the SDL line `directive @glRestNullable on FIELD_DEFINITION` (also check the
  `--print-directives` output and any test that lists declared directives).
- New top-level config key, default `"Rest"`, name to settle (`restNullableSuffix`). Add to `GeneratorConfig`, pass through
  `grammar_factory.dart` to a new `GLParser` parameter.

### Validation (`validateRestOperations`, or a sibling method)
Fire before any copy is built:
- `@glRestNullable` on a field that is not a REST operation;
- `@glTypeName` on a REST operation (dedicated message, decision 13);
- operation response kind is text, binary or none;
- operation result is a scalar or enum (nothing to copy);
- name collision: `<token><suffix>` already exists among `types`, `interfaces`, `inputs`, `enums`, `scalars`, `unions`,
  `projectedTypes`, `projectedInterfaces`, or two reachable types would produce the same copy name.

### Pipeline hook
New step `createRestNullableCopies()` in client mode, **directly after `registerRestResponseTypes()` and before
`cleanProjectedInterfacesImplementations()`**.

### Algorithm
1. Roots: the response type names of the opted-in operations. If none, return.
2. Closure: the same walk as `_computeReachable()` but rooted at the opted-in operations only (parameterize it). It follows
   field types and, for an interface, its implementers.
3. Create the copy of each type in the closure before filling any fields (a name -> copy map built first), so cycles
   (`Product.related: [Product!]`) and shared references resolve to the same copy.
4. For each copy:
   - name `<token><suffix>`; `nameDeclared: true` so projected-type similarity merging never folds it into another type;
   - fields: `field.ofType(...)` where the outermost level becomes nullable, list element nullability is kept, and the inner
     token is renamed when it names a copied type (scalars and enums are left alone);
   - `interfaceNames`: only interfaces that are in the closure, renamed. Relations to interfaces no REST operation reaches are dropped
     (the type already redeclares every field);
   - implementations wired explicitly with `addImplementation` / `addInterface`, because `getTypesImplementing` only scans the
     original `types`;
   - `derivedFromType` null; interface copies get `fromUnion: false`;
   - directives: start with none, then check what serializers need (see verification list).
   - register with `addToProjectedTypes(copy, similarityCheck: false)`.
5. Discriminators: for each copied interface that has an original `restDiscriminators` entry, add
   `restDiscriminators[copyName] = GLRestDiscriminator(parent: copyName, field: <same>, valueByType: {copyMember: <original wire value>})`.
   Reuse the original resolved values. A default would otherwise become the copy's name (`"DogRest"` instead of `"dog"`).
6. Rewrite each opted-in operation: replace its entry in `restOperations` with a new `GLRestOperation` whose `field` is
   `op.field.ofType(<same list/null structure, copy token>)`. Add a small `withField` copy helper on `GLRestOperation`.
   Everything else (path, arguments, cache, response path) is unchanged.

### Edge cases to handle
- One type reachable from an opted-in and a normal operation: both the original and the copy exist.
- Two opted-in operations sharing nested types: one copy per type.
- Cycles and self references.
- `forceCyclicEdgesNullable()` runs earlier; the copy is all-nullable anyway.
- Types with `@glExternal`, `@glTypeName` or `mappedToType`: decide per case; reject with a clear error if a copy would be wrong.
- `@glCache` on an opted-in operation: the cache stores JSON, so decoding to the copy should be fine; needs a test.

## Verification spike (do first, before the implementation is finished)

1. Swift: `restDiscriminators[wireToken]` for a copy named `PetRest`.
2. `fromUnion: false` on a copy of a union-derived interface: the keyword and normalization passes sync `fromUnion` interfaces to their
   union's code name (`gl_grammar_keyword_extension.dart`), so confirm a copy is not matched or broken by them.
3. What serializers read from directives on a projected type (`getTypeNameFromGQExternal` in `gl_serializer.dart`); confirm an
   empty directive list is safe.
4. `fixProjectedInterfaceConflicts()` leaves copies alone with `derivedFromType` null.
5. `_getCommonInterfaceFields` uses `derivedFromType!` but is only reached for interfaces created from GraphQL projections;
   confirm copies never reach it.
6. Code names: copies go through keyword sanitizing and normalization as projected types; confirm the resulting code name equals
   the token for ordinary names.
7. Resolved: `@glTypeName` on a `type` is rejected (`cannot be used on OBJECT`), contrary to `site/docs-src/directives.md`, so copies use
   `<token><suffix>` as their code name. The REST-specific message (decision 13) has to be raised from the directive-validation pass,
   which runs before `validateRestOperations()` and would otherwise win with the generic message; add a test that a REST operation
   with `@glTypeName` produces the new message.

## Tests (IR first, in `test/rest/`, inline `const` schemas)

- Object copy: `ProductRest` exists in `projectedTypes` with every field nullable; `Product` unchanged; GraphQL operations still return `Product`.
- Deep copy: nested object, list of objects, shared nested type between two operations gives one copy.
- List nullability follows the schema: `[X!]!`, `[X]!`, `[[X!]!]!`.
- Cycles and self references.
- Interface with discriminator: `PetRest` implemented by `DogRest` and `CatRest`, discriminator entry keyed `PetRest` with the original wire
  values (default values included), unreachable extra interfaces dropped.
- Union: same as the interface case through the synthesized interface.
- Operation rewrite: `restOperations` entry points at the copy and keeps nullability, path, cache and response path.
- Validation errors for every misuse in decision 12, and for name collisions.
- Directive declaration appears in `--print-directives` output.
- Generated output: one assertion per target language that a field of the copy is optional and that the interface copy decodes by discriminator.
- Real server: add endpoints to `real/rest_server/server.py` that return partial payloads (missing and `null` fields; a polymorphic
  payload with missing fields) and operations on them in `real/schema_rest/`. Add tests to one target first (Java blocking, which the
  reactive suites derive from), then the others.

## Order of work

1. Directive declaration, constant, config key, `GLParser` parameter.
2. IR tests for objects, lists, validation; then `createRestNullableCopies()` for objects.
3. Spike items 1 to 6, then interfaces, unions and discriminator copies.
4. Generated-output tests per language.
5. Real-server endpoints and tests, one target at a time.
6. Docs (`site/docs-src/rest-client.md`, `configuration.md`), `CHANGELOG.md`, `CLAUDE.md` integration-test notes.

## Done when

- Every misuse in decision 12 fails at parse time with a clear message.
- A schema with an opted-in operation generates `ProductRest` (and interface copies) on all seven clients, and a partial payload decodes on each target against the real REST server.
- GraphQL output and non-opted-in REST operations are byte-for-byte unchanged.

## Implementation notes

- New step `createRestNullableCopies()` in `parser_extensions/gl_grammar_rest_nullable_extension.dart`, called right after
  `registerRestResponseTypes()`. The reachability walk was parameterized as `restReachableTypeNamesFrom(operations)`.
- Fields use `GLType.makeNullable` (outer level only), types are renamed with `ofNewName`.
- Replacing the operation's field is not enough: the field must also replace the original on its owning type
  (`replaceField`), because the last pipeline step (`normalizeIdentifiers`) names the fields of `types`. Without it Python kept
  `lenientProduct` instead of `lenient_product`. Covered by the "naming" tests.
- Client serializers decided which types a REST operation imports by looking only at `types` / `interfaces`. `isRestImportableType`
  (in `gl_grammar_rest_extension.dart`) now also consults the projected maps; Dart, Java, Kotlin, Python and TypeScript use it.
- `@glTypeName` on a REST operation is rejected by `rejectTypeNameOnRestOperations()`, which runs before `validateDirectives()` and
  looks at the extension blocks too (`extensibleTokens`), because extension fields are merged later.
- Verification spikes: the discriminator lookups by token work for copies in Dart, Java, Kotlin, TypeScript, Python, Go and Swift;
  `fixProjectedInterfaceConflicts` and `cleanProjectedInterfacesImplementations` leave the copies alone with `derivedFromType` null;
  `fromUnion: false` on a union copy is fine with the keyword and normalization passes.
- Known gap found on the way (not part of this feature): Swift strict types decode with force unwraps, so a missing non-null field
  traps instead of throwing a named error like the other targets.
