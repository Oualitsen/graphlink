# Plan: @glStrict — Schema-Faithful Entity Types + `<Type>Projection` for Server Generation

## Context

In server mode, `GLSerializer.forceFieldNullable` (true when `mode == CodeGenerationMode.server`)
forces every field of a generated `type` to be nullable, regardless of the `!` markers in the
schema. This is **structurally required** for the type's role as a GraphQL response shape:
GraphQL resolvers operate per-field (`PropertyDataFetcher` / `@SchemaMapping`), and the object a
resolver returns may not have every field populated — especially relation fields that are
resolved lazily or via separate `DataFetcher`s. A non-null Kotlin/Java type couldn't represent
"not yet fetched", so all-nullable is the only viable shape for the controller-facing type.

The problem: when a GraphQL `type` also represents a row in the database (the common case —
"the schema reflects what the DB holds, you never hand-write an entity class"), this same
all-nullable class is *also* used as the JPA entity / repository generic param / business-logic
model. There, all-nullable is wrong:

- It doesn't reflect real DB constraints (`NOT NULL` columns become `T?` in Kotlin).
- In Kotlin specifically, every field access throughout business logic needs `?.`/`!!`/`requireNotNull`,
  defeating null-safety.
- In Java it's less painful (no compile-time enforcement) but still loses information.

`@glStrict` makes the **schema-declared name** (`<Type>`) the real-nullability entity/business
type, and introduces a second, additive class — `<Type>Projection` — with all-nullable fields and
zero annotations, intended purely as the GraphQL response/transport shape, plus a `toProjection()`
conversion from `<Type>` to `<Type>Projection`.

Applies to Java Spring, Kotlin Spring, and the TypeScript/Express server target.

---

## Design

### Directive & config

```graphql
type User @glStrict {
  id: ID!
  name: String!
  address: Address
}
```

- `@glStrict` is a per-type opt-in directive (registered in `built_in_dirctive_definitions.dart`).
- A global config flag (`generateStrictTypes: bool`, on `SpringServerConfigBase` and the
  TS server config) sets the default for **all** types — `@glStrict` on individual types is then
  mostly redundant but harmless.
- Strictness is a **flat per-type boolean**: `@glStrict` present on the type, or
  `generateStrictTypes: true` globally. No transitive closure, no propagation — a type's
  strictness never depends on what other types reference it or what it references. (See
  "Naming" below for why this is possible without a closure.)

### Naming: `<Type>` vs. `<Type>Projection`

- **`<Type>Projection`** is generated for **every** type, unconditionally — strict or not.
  Always all-nullable, **always zero annotations** (plain data class/record/interface). This is
  the GraphQL response/transport shape: what `@SchemaMapping`/`@QueryMapping` controller methods
  return.
- **`<Type>`** always keeps the schema-declared name and any user-authored annotations
  (`@Entity`, `@Table`, `@Id`, `@Column`, etc. via the annotation extension).
  - If the type is **strict**: `<Type>` has **real schema nullability** (matches `!` markers).
    This is the JPA entity / repository generic param / business-logic model.
  - If the type is **not strict**: `<Type>` is generated exactly as today — all-nullable,
    serving double duty as both entity and response shape. **No behavior change** for projects
    that don't use `@glStrict`/`generateStrictTypes`.

Because `<Type>Projection` always exists, a strict type's projection can always reference
`<FieldType>Projection` for its field types — whether or not `<FieldType>` itself is strict —
with no lookup against any closure/set. This is what eliminates the closure computation
entirely (see below).

### No closure needed

An earlier version of this design computed a transitive `strictTypes` closure (seed set of
`@glStrict` types, propagated across object-typed fields, list element types, and interface
implementors, with cycle handling) to determine which types needed a `<Type>Projection` sibling.

This is unnecessary: since `<Type>Projection` is generated for *every* type, there's nothing to
propagate. Adding `@glStrict` to one type never changes the generated shape of any other type —
fully local, fully decoupled. This also removes any need for a `@glNoStrict` opt-out: there's no
"is this type pulled into someone else's closure" question to opt out of.

### Field typing inside `<Type>` and `<Type>Projection`

For `<Type>` (any type, strict or not):

- Field type references are **unchanged** — a field of type `Address` still refers to `Address`,
  never `AddressProjection`.
- Nullability: real schema nullability if the type is strict; all-nullable (as today) if not.

For `<Type>Projection` (any type, strict or not):

- Every field is nullable (forced, regardless of schema `!`).
- Every field type reference is rewritten to `<FieldType>Projection` — unconditionally, since
  `<FieldType>Projection` always exists.

So `forceFieldNullable` reduces to: `true` for `<Type>Projection`, always; for `<Type>`, `true`
unless the type is strict.

### `toProjection()` — selection-aware copy via a flat path set

Two earlier ideas were considered and rejected:

- **Eager field-by-field copy** (always "safe" since non-null → nullable never has a
  nullability mismatch — everything would trivially auto-map under `@glMapsTo`'s
  `ToMappingPlan` rules). Rejected: copying every relation field would touch every Hibernate
  lazy proxy / lazy collection on `<Type>`, regardless of what the client requested —
  reintroducing the N+1s per-field resolution exists to avoid.
- **Thin wrapper with delegating getters** (`UserProjection(private val entity: User)`, each
  getter calling `entity.field?.toProjection()` lazily on access). This solves overfetching for
  *blocking* Hibernate, but has no single shape that also works for reactive (Kotlin
  `suspend` can't be a property getter; `Mono<Address>` for `User.address` is the wrong type
  and forces reactive ceremony onto blocking code).

**Chosen approach:** `toProjection()` takes an optional, framework-agnostic selection — a flat
`Set<String>` of qualified field paths (`"address"`, `"address/city"`, `"orders/items/sku"`,
…) — and does a *selective* eager copy, synchronous, identical signature in blocking and
reactive:

```kotlin
fun User.toProjection(selection: Set<String>? = null): UserProjection = UserProjection(
    id = id,
    name = name,
    address = if (selection == null || selection.any { it == "address" || it.startsWith("address/") })
                  address?.toProjection(selection?.subSelection("address"))
              else null,
)
```

- `selection == null` is the **default** and means "no restriction — populate everything".
  This makes `toProjection()` directly usable outside a GraphQL request: tests, REST endpoints,
  batch jobs, internal service-to-service calls — `userEntity.toProjection()` just works.
- A non-null `selection` restricts which fields get touched. For blocking/Hibernate, a field
  not present in `selection` is never accessed, so its lazy proxy/collection is never
  initialized. For reactive/R2DBC, `toProjection()` doesn't fetch anything itself — the
  repository/service layer is responsible for fetching according to the same selection (the
  existing `injectDataFetching` story); `toProjection()` just mirrors that selection on the way
  out.
- List fields: `entity.orders?.map { it.toProjection(selection?.subSelection("orders")) }` — the
  same sub-selection applies to every element.
- Mapping is **one-directional** (`<Type>` → `<Type>Projection`). No reverse mapping — inputs
  already have their own mapping story (`@glMapsTo`/`@glMapField`), which is unrelated.

#### Selection representation — `Set<String>`, no generated class

No custom `GLSelection` class is needed. `DataFetchingFieldSelectionSet.getFields("*/**")`
(graphql-java) returns fully-qualified nested field paths. **Verified** against a running
Spring GraphQL server (graphql-java + Spring GraphQL):

- Simple nesting — `{ getPatientById { id room { id } } }` →
  `[Patient.id, Patient.room, Patient.room/Room.id]`: `/`-separated for depth, each segment
  prefixed `<TypeName>.<fieldName>`.
- Interface + fragments — for the selection set of `pet` in
  `{ pet { id name ... on Dog { bark } ... on Cat { meow } } }` →
  `[[Cat, Dog].id, [Cat, Dog].name, Dog.bark, Cat.meow]`: fields common to multiple possible
  types get a bracketed type-list prefix; fragment-only fields get a single-type prefix.

In both cases the field name is everything after the **first** `.` in each `/`-separated
segment (no `.` occurs inside the bracketed list itself), so one transform handles both shapes:

```kotlin
val selection: Set<String> = selectionSet.getFields("*/**")
    .map { it.qualifiedName.split("/").joinToString("/") { seg -> seg.substringAfter(".") } }
    .toSet()
```

This collapses the examples above to `{"id", "room", "room/id"}` and
`{"id", "name", "bark", "meow"}` respectively — a flat superset for type-conditional
selections, which is sufficient: `DogProjection.toProjection()` only ever looks for `bark`
(ignoring the unrelated `meow` entry), and vice versa for `CatProjection`.

`toProjection()` only needs two tiny, generated-once helpers (same minimal-footprint precedent
as `GraphLinkError`):

```kotlin
private fun Set<String>?.contains(field: String): Boolean =
    this == null || any { it == field || it.startsWith("$field/") }

private fun Set<String>?.subSelection(field: String): Set<String>? =
    this?.filter { it.startsWith("$field/") }?.map { it.removePrefix("$field/") }?.toSet()
```

```java
private static boolean glSelectionContains(Set<String> selection, String field) {
    if (selection == null) return true;
    return selection.stream().anyMatch(f -> f.equals(field) || f.startsWith(field + "/"));
}

private static Set<String> glSubSelection(Set<String> selection, String field) {
    if (selection == null) return null;
    return selection.stream()
        .filter(f -> f.startsWith(field + "/"))
        .map(f -> f.substring(field.length() + 1))
        .collect(Collectors.toSet());
}
```

Benefits over a custom tree class:

- `Set<String>` is trivially constructible in tests/REST/batch jobs (`setOf("id", "address/city")`)
  — no need to build a `GLSelection(mapOf(...))` tree.
- The graphql-java adapter is one small generated function.
- Same shape (`Set<string>` / `string[]`) ports directly to the TS/Apollo target.
- Fragments on interface-typed fields need no special handling — a flat path set is sufficient
  even for type-conditional selections (verified above).

### Spring controller integration — selection extraction is always-on for strict types

Spring GraphQL resolves `DataFetchingFieldSelectionSet` synchronously from the
`DataFetchingEnvironment` at invocation time, independent of the controller method's return type
— it works identically for blocking, `Mono`/`Flux`, and `suspend` methods. This means:

- For any controller method whose return type is **strict**, GraphLink **always** injects
  `DataFetchingFieldSelectionSet selectionSet` as a method parameter (regardless of the
  `injectDataFetching` config), converts it to `Set<String>` via the adapter above, and calls
  `.toProjection(selection)` on the service's result before returning — e.g.
  `serviceResult.map { it.toProjection(selection) }` (reactive),
  `serviceResult.toProjection(selection)` (blocking/suspend).
- Controllers for **non-strict** types are untouched — no injection, no conversion, exactly as
  today.
- `injectDataFetching` remains **orthogonal and unchanged**: it still injects the full
  `DataFetchingEnvironment` into the controller method and forwards it to the service call
  (`java_spring_controller_serializer.dart:114-121`, equivalent in Kotlin). Since
  `DataFetchingEnvironment.getSelectionSet()` returns `DataFetchingFieldSelectionSet`, a service
  that wants `Set<String>` itself when `injectDataFetching: true` can derive it the same way —
  no new config dimension. The two injections (`DataFetchingFieldSelectionSet` for
  `toProjection()`, `DataFetchingEnvironment` for `injectDataFetching`) may both be present on
  the same method; Spring resolves each by parameter type independently.

### Annotations on `<Type>Projection`

`<Type>Projection` is a plain POJO (Java) / POKO (Kotlin) — **zero annotations**, for every
type, strict or not:

- No JPA (`@Entity`, `@Table`, `@Column`, `@Id`, …) — those are entity/persistence concerns and
  stay on `<Type>`.
- No Jackson — Spring GraphQL resolves response types via the execution engine's property
  fetchers, not Jackson serialization.
- No jspecify null-safety annotations (`getJSpecifyAnnoation`) either — every field on
  `<Type>Projection` is nullable by construction, so `@Nullable` everywhere adds no information.
- Any user-authored `@`-annotations (via the annotation extension) on the original type/fields
  are stripped on the projection.

`<Type>` keeps its annotations unconditionally — strict or not, this is unchanged from today.

### Implementation approach: `toProjected()` on `GLTypeDefinition`

To avoid threading a "which variant" parameter through every method of every language serializer,
the projection variant is produced by **cloning the IR**, not by parameterizing the serializers:

- `GLTypeDefinition` gets a method `toProjected()` (no closure/set argument — see "No closure
  needed" above) that returns a new `GLTypeDefinition`:
  - `token` → `<Type>Projection`
  - `directives` → `[]` (and each field's `directives` → `[]`) — zero annotations, since
    `serializeDecorators(def.getDirectives())` naturally emits nothing.
  - Built from `getSerializableFields(CodeGenerationMode.server)` — the same field list `<Type>`
    already uses, so `@glSkipOnServer` fields are absent from `<Type>Projection` exactly as
    they're absent from `<Type>` today. No new filtering logic (see "`@glSkipOnServer`
    interaction" below).
  - every field's `GLType`/`GLListType` cloned with `nullable: true`.
  - every field's type reference rewritten to `<FieldType>Projection` (unconditional).
  - sets a new `isProjection` bool flag to `true` (default `false` on all other instances).
- `GLInterfaceDefinition extends GLTypeDefinition`, so `toProjected()` is inherited;
  interface-specific data (implementor list, etc.) carries through the clone, and each
  implementor also gets its own `<Implementor>Projection` via the same unconditional rule.
- `forceFieldNullable`: `true` for `<Type>Projection` (always); for `<Type>`, `true` unless the
  type is strict (today's unchanged behavior for non-strict types).
- Generators: for **every** type, additionally call `serializeTypeDefinition(def.toProjected())`
  and write the result alongside `<Type>`. Existing serializer code (`doSerializeTypeDefinition`,
  `serializeField`, `serializeDecorators`, `serializeType`) requires **no changes** — it already
  does the right thing given the cloned IR.

### `@glSkipOnServer` interaction

No special handling needed. `getSerializableFields(CodeGenerationMode.server)`
(`gl_token_with_fields.dart`, via `shouldSkipSerialization`) already excludes
`@glSkipOnServer` fields from `<Type>`'s field list — these fields aren't properties on the
server-side class at all (fields with arguments are *required* to carry `@glSkipOnServer` and
are resolved via a separate `@SchemaMapping` method instead). Since `toProjected()` builds
`<Type>Projection` from this same field list, these fields are absent from both classes —
exactly as `<Type>` behaves today. The `@SchemaMapping` resolver mechanism is untouched and
fully orthogonal: it resolves the field independently on whatever object `toProjection()`
returned.

### `@glRepository` + `@glStrict` on the same type

`<Type>` becomes the `@Entity` / repository generic param (`JpaRepository<User, Long>`) — this
is now the default/natural outcome of the naming swap, not a special case.

### Per-framework adapter (the only framework-coupled piece)

A small generated adapter converts the host framework's selection-set type into `Set<String>`:

- **graphql-java-based** (Spring GraphQL, Quarkus/SmallRye, Micronaut GraphQL):
  `selectionSet.getFields("*/**").map { it.qualifiedName.split("/").joinToString("/") { seg -> seg.substringAfter(".") } }.toSet()`
  (verified format — see "Selection representation" above).
- **Apollo/GraphQL.js**: walk `GraphQLResolveInfo.fieldNodes` → `selectionSet.selections`
  (resolving fragment spreads) into a flat set of `/`-joined paths — see "TypeScript / Express
  target" below.

### TypeScript / Express target

- `<Type>` and `<Type>Projection` are plain `export interface`s (`typescript_serializer.dart:142`)
  — erased at runtime, no methods/decorators. `toProjected()`'s "strip directives/annotations"
  step is a no-op for TS (interfaces never carry decorators); `<Type>` vs `<Type>Projection`
  differ only in nullability and field-type references (`<FieldType>` → `<FieldType>Projection`,
  unconditionally, same as every other target).
- `toProjection()` is generated as a **standalone function**, not a method —
  `toUserProjection(user: User, selection?: Set<string>): UserProjection` — since TS interfaces
  have no receiver/namespace to attach a method to.
- **File placement**: same convention as Kotlin/Java — `<Type>` and `<Type>Projection` (plus
  `toUserProjection`) live in sibling files in the types directory, with the projection file
  importing `User` from the business-logic file (one-directional, avoids cycles).
- **Selection adapter**: graphql-js has no `getFields("*/**")` equivalent. Build the flat
  `/`-joined `Set<string>` by walking `GraphQLResolveInfo.fieldNodes` →
  `selectionSet.selections`, resolving `FragmentSpread`s via `info.fragments`. No type-prefix
  stripping is needed here — graphql-js field names aren't type-qualified — so this adapter is
  arguably simpler than the graphql-java one. The two selection-helper functions
  (`contains`/`subSelection`) port directly to `Set<string>`.
- **`useResolveInfo`** gets the same "always-on for strict types" treatment as Spring's
  `DataFetchingFieldSelectionSet` injection: for resolvers returning a strict type,
  `GraphQLResolveInfo` is always injected regardless of the `useResolveInfo` config flag.

### Consequences for type generation

- `<Type>Projection` is a plain Kotlin `data class` / Java `record` / TS `interface` —
  `toProjection()` produces a new instance via selective copy, no wrapping, so
  `typeAsDataClass`/`typeAsRecord` apply to it the same way they do today for the (formerly
  all-nullable) `<Type>`.
- For non-strict types, `<Type>` is generated exactly as today (all-nullable, annotated).
  `<Type>Projection` is additionally generated as a near-duplicate (all-nullable, zero
  annotations) — purely additive, and serves as a safe, always-present reference target for any
  strict type whose projection points at this type.

### Why not reuse `@glMapsTo` / `ToMappingPlan`

`ToMappingPlan`/`FromMappingPlan` (`gl_input_mapping.dart`) solve a harder, differently-shaped
problem: mapping between two **different** definitions (`input` ↔ `type`) with possibly
different field names (`@glMapField`), missing fields, mismatched nested types — hence
`autoMapped`/`defaultParams`/`requiredParams`/`promoted`/`nullableListDefaults`.

For `<Type>` → `<Type>Projection`, it's the *same* field names and the conversion isn't even a
copy in the input-mapping sense — it's a selective, selection-aware copy with a nullability
widening (non-null → nullable always succeeds). None of `ToMappingPlan`'s hard-case machinery
would ever trigger. A small dedicated generator (iterate `getSerializableFields(mode)`, check
strictness per type, rewrite field-type references to `<FieldType>Projection`) is more honest
and avoids carrying unused complexity.

---

## Non-goals

- No change to input (`@glMapsTo`/`@glMapField`) mapping.
- No change to `<Type>` generation for non-strict types — fully backward compatible for projects
  that don't use `@glStrict`/`generateStrictTypes`.
- No reverse (`<Type>Projection` → `<Type>`) mapping.
- No `GLSelection` class or other new generated support type beyond two small selection-helper
  functions.
- No transitive closure computation, no `@glNoStrict` opt-out — strictness is a flat per-type
  flag with strictly local effects.
