# `@glMapsTo` v7: one direction, declared on the source, server only

Status: ready to implement. Target: v7 (breaking changes allowed).
Supersedes Features 1 and 2 of `input-mapping-extensions.md` (`generate: TO|FROM|BOTH`, `mode: CLIENT|SERVER|BOTH`).

## Why

Today `@glMapsTo` goes on an input only, targets a type only, and generates two methods on the input:

```graphql
input UpdateArticleInput @glMapsTo(type: "Article") { ... }
# → UpdateArticleInput.toArticle()
# → UpdateArticleInput.fromArticle(article, ...)
```

Problems:

1. Both methods are always generated, used or not.
2. Only input → type. A type cannot map to anything, and an input cannot target another input.
3. One target per input.
4. Generated for clients and servers alike, while mappings are mostly a backend need.

## The rule

**The directive is placed on the source, and generates one method on the source: `to<Target>()`.**
No `from` method anywhere. A reverse mapping is a second `@glMapsTo` on the other side.

```graphql
input UpdateArticleInput @glMapsTo(type: "Article") { ... }        # → input.toArticle()
type Article @glMapsTo(type: "UpdateArticleInput") { ... }         # → article.toUpdateArticleInput()
```

Placement is the direction, so no `direction` argument is needed.

## Schema

```graphql
input CreateArticleInput @glMapsTo(type: "Article") {
  title: String!
  authorId: ID!
}

type Article
  @glMapsTo(type: "ArticleSummary")
  @glMapsTo(type: "UpdateArticleInput") {
  id: ID!
  title: String! @glMapField(to: "headline", target: "ArticleSummary")
  authorId: ID!
}
```

- `@glMapsTo(type:)` is **repeatable**. Allowed on `type` and `input`. The target can be a `type` or an `input`.
- `@glMapField(to:)` renames a field for one target. `target:` says which one:
  - source with **one** `@glMapsTo`: `target:` is optional (it can only mean that target);
  - source with **several** `@glMapsTo`: `target:` is **required** on every `@glMapField` of that source, even when
    the field name would be unambiguous. Adding a second target to a source therefore makes its untargeted
    `@glMapField`s a validation error, so a rename never silently applies to a target it was not meant for.
- `@glMapField` is repeatable (one occurrence per target it renames for).
- `@glMapField(target:)` naming a type that is not one of the source's `@glMapsTo` targets is a validation error.

Not allowed (validation errors):

- Source or target that is an enum, scalar, union or interface. Interfaces and unions are a separate design (dispatch on
  the concrete type); out of the first version.
- The same target declared twice on one source.
- A source mapping to itself.
- Two targets of one source producing the same method name `to<Name>` (possible with renamed types through `codeName`).

## Generated method

Unchanged from today's `toXxx()` behavior, generalized from "input → type" to "any object/input → any object/input":

- Fields with the same name (or `@glMapField` alias) and a compatible type are copied.
- Target fields with no source counterpart become **required parameters** of `to<Target>()`.
- Nullable source → non-null target becomes a `default<Field>` parameter, as today.
- Nested fields are mapped through the nested source's own `@glMapsTo` to the nested target; when that nested
  mapping needs parameters, the field is promoted to a parameter, as today.
- Lists of mapped elements are mapped element-wise, as today.
- **Only data fields take part.** On the server, fields with arguments (served by schema mappings) and
  `@glSkipOnServer` fields are not data on the generated class: they are never copied, never become parameters,
  and `@glMapField` on them is a validation error. `ToMappingPlan` already filters with `getSerializableFields(mode)`;
  keep it and cover it with tests (check `test/gl_skip_on_server_map_to/` against the new rule).
- **Java records** (`examples/java/app_record`): `to` methods only read, so they are added to records as today
  (`serializeRecord(..., extraStatements: generateMappingMethods(def))`).

Example (Kotlin):

```kotlin
fun toUpdateArticleInput(): UpdateArticleInput = UpdateArticleInput(id = id, title = title)
fun toArticle(id: String, published: Boolean): Article = Article(id = id, title = title, authorId = authorId, published = published)
```

## Where it is generated

**Servers by default. Clients only on opt-in.**

- Server targets (Spring Java/Kotlin, Express, NestJS, FastAPI, Django): always.
- Client targets: only when the client config enables it:

  ```json
  { "clientConfig": { "dart": { "generateMappers": true } } }
  ```

  `generateMappers`, set per client target (`dart`, `java`, `kotlin`, `typescript`, `swift`, `python`, `go`), default
  `false`. Named like the existing server option `generateRepositories`. Added to each client config class in
  `config.dart` (`fromJson`).

On a client, a mapping is generated only when both source and target are generated for that client (today's
`projectedTypes` check, kept).

## IR

- `GLInputDefinition.mapsToType` (single) becomes a list of declared mappings on any type with fields:
  `List<GLMapsTo> mapsTo` with `{ targetName, tokenInfo }`. The common base looks like `GLTokenWithFields`; confirm.
- `GLField.mapFieldTo` becomes target-aware: `mapFieldTo(targetName)`.
- `ToMappingPlan.resolve(source, target, …)` is generalized from `(GLInputDefinition, GLTypeDefinition)` to
  `(fields source, fields target)`. Nested resolution stops asking `allInputs[x]?.mapsToType == y` and asks a single
  registry: `GLParser.mappingFor(sourceName, targetName)`.
- **`FromMappingPlan` is deleted** and `GLMappingSerializer.fromMethod` with it. Its cases (input-only fields, nullability
  promotions) are the `toXxx()` cases seen from the other side, already handled by `ToMappingPlan`.
- `gl_grammar_maps_to_extension.dart`:
  - `validateMapsToDirectives()` loops over types and inputs, validates each declared pair.
  - `resolveMappingPlans(def, mode)` returns the plans for one definition, or none when the mode/config excludes them.
- `GLSerializer.generateMappingMethods(def)` takes any definition, emits one `to` method per plan. Kotlin calls the plans
  directly today (`kotlin_serializer.dart`); move it to the shared path.

## Per language

| Language | Today | Change |
|---|---|---|
| Dart, Java, Kotlin, Swift, Go, Python | mapping serializer exists | drop `fromMethod`; call `toMethod` for types too |
| TypeScript | **no mapping serializer** | new `TypeScriptMappingSerializer`, needed for Express and NestJS servers (shape below) |

**Kotlin.** It builds its mapping methods in its own `_generateToMappingMethods` / `_generateFromMappingMethods`
(`kotlin_serializer.dart`) instead of `GLSerializer.generateMappingMethods`, because `fromXxx` had to go in the
`companion object` while `toXxx` is an instance method. With `from` gone, that split has no reason left: delete both
helpers and use the shared `generateMappingMethods`, like the other languages.

**TypeScript.** Generated types are `interface`s with a merged `namespace` holding `toJson` / `fromJson`, so an
interface cannot carry a `toX()` instance method. The mapping goes in the same namespace, as a function taking the
source, consistent with `toJson`:

```typescript
export namespace Article {
  export function toJson(obj: Article): Record<string, unknown> { ... }
  export function fromJson(json: Record<string, unknown>): Article { ... }
  export function toArticleSummary(obj: Article): ArticleSummary {
    return { id: obj.id, headline: obj.title };
  }
}
// call site: Article.toArticleSummary(article)
```

So TypeScript is "class style" by construction (a function next to the type, not a method on it), with no new config.

Mutual mappings (`A → B` and `B → A`) make the two files import each other:

- Dart, Java, Kotlin, Swift, Go: fine.
- Python: circular import. Import the target inside the method, or under `TYPE_CHECKING` plus a local import.
- TypeScript: usually fine (classes used at call time only). Needs a test.

## Migration (v6 → v7)

| v6 | v7 |
|---|---|
| `input X @glMapsTo(type: "T")` gave `x.toT()` | unchanged |
| `X.fromT(t, ...)` | add `@glMapsTo(type: "X")` on `T`, call `t.toX(...)` |
| mappings generated on clients | add `"generateMappers": true` to the client config |

Changelog and docs page must show the `fromT` → `t.toX` rewrite.

## Tests

- `test/maps_to/`: rewrite the existing suites on the new rule (inline schemas):
  - type → type, type → input, input → input, input → type;
  - several targets on one source, `@glMapField(target:)` per target, missing `target:` with several targets is an
    error, `target:` naming an undeclared target is an error;
  - required parameters, `default<Field>` parameters, nested and list mappings, promotion;
  - no `from` method generated anywhere;
  - server generates, client does not, client with `generateMappers: true` does;
  - fields with arguments and `@glSkipOnServer` fields excluded on the server; `@glMapField` on them is an error;
  - two targets producing the same `to<Name>` is an error;
  - Java record with mapping methods;
  - validation errors listed above.
- One generation test per language, including the new TypeScript serializer and the Python mutual-import case.
- `examples/java/gl_mapping`, `examples/dart/gl_mapping`, `examples/java/app_record`: update schemas to the new rule.

## Out of scope (for now)

- Mapper style config (`inline | class`, see the v7 model discussion). This plan keeps today's inline methods.
- Interfaces and unions as source or target (rejected by validation, see above).
- Schema-level defaults (Feature 3 of `input-mapping-extensions.md`); still valid, applies to the `default<Field>`
  parameters of `to` methods.

## Decisions (settled)

1. Client opt-in: `generateMappers`, per client target, default `false`.
2. Interfaces and unions: out of the first version, rejected by validation.
3. Two targets producing the same `to<Name>`: validation error.
4. Fields with arguments and `@glSkipOnServer` fields never take part in a mapping.
5. `@glMapField(target:)` is required on every `@glMapField` of a source that declares several `@glMapsTo`.
6. Java records keep receiving mapping methods.
