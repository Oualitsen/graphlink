# Plan: `@glStrict` — Interface-Split Entity Types for Server Generation (Consolidated, Final)

## Status

This is the **authoritative** design for `@glStrict`. It supersedes:

- `plans/glstrict-server-types.md` — the original `<Type>Data` + `toProjection()` selective-copy design.
- `plans/glstrict-projection-interface.md` — the `prefetch()` interface revision.

Both are kept for historical context, but where they conflict with this doc, **this doc wins**.
The big change from both: **there is no `<Type>Data`, no `toProjection()`/`toData()` copy, no
`prefetch()`, no capture step, no controller `@Transactional`-for-capture, and no always-on
selection injection.** The design reduces to a clean two-artifact interface split that is
data-source-agnostic.

Carried over **unchanged** from the prior docs (referenced, not repeated):

- The verified selection-format adapter (`getFields("*/**")` → `Set<String>`, type-prefix
  stripping) — see `glstrict-server-types.md` "Selection representation". We no longer generate
  this by default (see §6), but the verification still stands if a user wants it.
- `@glSkipOnServer` handling via `getSerializableFields(CodeGenerationMode.server)`.

---

## 1. The problem (recap)

In server mode, `GLSerializer.forceFieldNullable` forces every field of a generated `type` to be
nullable, because the type doubles as the GraphQL response shape and a resolver may return an
object where not every field is populated. When that same class is *also* the JPA entity /
business model, all-nullable is wrong: it doesn't reflect DB constraints, and in null-safe
languages (Kotlin, TS strict) it forces `?`/`!!`/`requireNotNull` throughout otherwise-clean
business code.

This feature (codenamed `@glStrict`) separates the two roles — strict by default, with
`@glServerLenient` as the per-type opt-out (§9):

- **`<Type>`** — the schema-declared name, with **real schema nullability** and all user
  annotations. The entity / repository generic param / business model.
- **`GL<Type>Projection`** — an **interface** with **all-nullable** getters and **zero
  annotations**. The transport/response contract and the polymorphic boundary.

The all-nullable interface absorbs "not everything is populated" at the boundary (computed
fields, separately-resolved fields, partial projections) **without contaminating the strict
entity**. This rationale is fully data-source-agnostic, which is why the interface survives every
simplification below.

---

## 2. The locked design

Unconditionally (see §9 — no activation step), for **every** object `type`:

1. **`GL<Type>Projection`** — an interface (Java `interface` / Kotlin `interface` / TS
   `export interface`):
   - Every getter nullable, regardless of schema `!`.
   - Zero annotations (interfaces carry no JPA/Jackson/jspecify concerns).
   - Every field-type reference rewritten to `GL<FieldType>Projection`. Because `GL<Type>Projection`
     is generated for *every* type, this never needs a closure or lookup — the target always
     exists (same "No closure needed" reasoning as the original doc).

2. **`<Type>`** — the schema-declared name, **implements `GL<Type>Projection`**:
   - Keeps all user-authored annotations (`@Entity`, `@Table`, `@Id`, `@Column`, …) — unchanged.
   - **Strict** type → real schema nullability (matches `!`). The JPA entity / business model.
   - **Non-strict** type → all-nullable, exactly as generated today. No behavior change.
   - Field-type references unchanged — `<Type>.address: Address`, never `GLAddressProjection`.

3. **The GraphQL boundary returns `GL<Type>Projection`; the service layer returns the strict
   `<Type>` by default.**
   - **Controller handlers and `@SchemaMapping` relation resolvers** declare `GL<Type>Projection`
     as their return type — the all-nullable transport contract and the polymorphic boundary. The
     controller returns the service result **directly** — no copy, no DTO, no transaction wrapper.
     The concrete→interface upcast (`User` → `GLUserProjection`) is implicit and always safe.
   - **Service (business) methods return the strict concrete `<Type>` by default.** This is the
     whole point of the feature: business code composes services and gets non-null fields back —
     no `!!`, no downcasts, no `requireNonNull`. Materializing a full strict entity is the ~99%
     case.

   **Opt-in for partial fetches: `@glReturnsProjection`.** A service method *cannot* return a
   partial object as a strict `<Type>` — a strict type forces every non-null field to be populated
   at construction, so there is no way to express "only `id` and `name` were fetched." The
   all-nullable `GL<Type>Projection` is the only type that can. When a developer wants
   selection-driven partial fetching (the client selected only `id, name`, so fetch only those
   columns), they mark that operation with **`@glReturnsProjection`**: that one service method then
   returns `GL<Type>Projection` instead of the concrete type, **and the `DataFetchingEnvironment` is
   automatically injected into it** (no separate `injectDataFetching` toggle needed for that
   method) so the selection set is in hand. Unmarked operations stay strict-concrete. The
   optimization is thus a per-operation opt-in for the ~1% who want it, with **zero** all-nullable
   tax on everyone else. The concrete→interface upcast at the controller boundary is identical
   either way, so no boundary code changes.

### Why the override type-checks

For `<Type>.field: <FieldType>` to validly override `GL<Type>Projection.field: <GLFieldTypeProjection>?`,
we need `<FieldType> <: <GLFieldTypeProjection>?`:

- `<FieldType>` always implements `GL<FieldType>Projection` (every type does).
- A non-null type is a subtype of its nullable counterpart in Kotlin (`T <: T?`), via covariant
  return types in Java, and structurally in TS.

So every field — scalar, relation, or list — validly overrides its projection getter, strict or
not.

---

## 3. Generated shapes per language

> **Read this before the examples.** The code blocks below deliberately show an *embedded
> object field* shape (`address: GLAddressProjection?`, `orders: List<GLOrderProjection>?` living
> directly on the interface) so the type-system mechanics — nullable rewrite, `GL<FieldType>Projection`
> references, and list covariance — are all visible in one place. **This embedded shape only
> occurs for document stores** (Mongo/Elasticsearch/etc., §5), where documents return fully
> materialized. **For the relational / Spring-JPA common case, object relations carry
> `@glSkipOnServer` and are resolved by their own `@SchemaMapping` resolver (§6), so they are
> absent from both `<Type>` and `GL<Type>Projection`** — the interface is then **scalar/enum-only**.
> The field-ref-rewrite + `List<? extends …>` machinery (§10.1) therefore fires only for embedded
> fields; for relational entities it is dormant. The relational shape is shown at the end of this
> section.

### Kotlin

```kotlin
interface GLUserProjection {
    val id: String?
    val name: String?
    val address: GLAddressProjection?
    val orders: List<GLOrderProjection>?
}

@Entity
data class User(
    @Id override val id: String,
    @Column override val name: String,
    @ManyToOne override val address: Address?,
    @OneToMany override val orders: List<Order>?,
) : GLUserProjection
```

`List<Order> <: List<GLOrderProjection>` for free — Kotlin `List<out E>` is covariant. **No
wildcard, no Kotlin serializer change for variance.**

### Java

```java
public interface GLUserProjection {
    String getId();
    String getName();
    GLAddressProjection getAddress();
    List<? extends GLOrderProjection> getOrders();   // wildcard REQUIRED — Java generics invariant
}

@Entity
public class User implements GLUserProjection {
    @Id private String id;
    private String name;
    @ManyToOne private Address address;
    @OneToMany private List<Order> orders;

    @Override public String getId() { return id; }
    @Override public String getName() { return name; }
    @Override public Address getAddress() { return address; }    // covariant return: Address <: GLAddressProjection
    @Override public List<Order> getOrders() { return orders; }  // valid override of List<? extends GLOrderProjection>
}
```

**Java-only wrinkle**: list getters on `GL<Type>Projection` need `List<? extends GLXProjection>` so
`<Type>`'s `List<X> getOrders()` is a valid covariant override. Single-object getters need no
wildcard.

### TypeScript (simplest target)

```ts
export interface GLUserProjection {
  readonly id: string | null;
  readonly name: string | null;
  readonly address: GLAddressProjection | null;
  readonly orders: GLOrderProjection[] | null;
}

export interface User extends GLUserProjection {   // optional; structural typing also suffices
  readonly id: string;
  readonly name: string;
  readonly address: Address;
  readonly orders: Order[];
}
```

- A GraphQL `type` already serializes to `export interface` (`typescript_serializer.dart`
  `_serializeType`), so both artifacts use the existing path.
- Arrays are covariant (`Order[] <: GLOrderProjection[]`) — **no `? extends` equivalent needed**.
- TS is **structural**: a `User` is assignable wherever `GLUserProjection` is expected with or
  without `extends`. Emitting `extends GLUserProjection` is optional but recommended for
  compile-time override verification + self-documentation (see §10 for the small util change it
  needs).
- No lazy-loading/session problem exists in JS, so the Apollo/Express resolver just returns the
  object typed as `GL<Type>Projection`. None of the JVM machinery applies.

### Relational (Spring / JPA) — the common case

Here `address` and `orders` carry `@glSkipOnServer`, so the interface holds only scalars and
each relation is a separate resolver:

```kotlin
interface GLUserProjection {
    val id: String?
    val name: String?
    val addressId: String?      // FK scalar, not the relation
}

@Entity
data class User(
    @Id override val id: String,
    @Column override val name: String,
    @Column override val addressId: String,
) : GLUserProjection

// Relations resolve on their own (generated from @glSkipOnServer), returning projections:
@SchemaMapping fun address(user: User): GLAddressProjection = addressService.byId(user.addressId)
@SchemaMapping fun orders(user: User): List<GLOrderProjection> = orderService.forUser(user.id)
```

No `GLAddressProjection` field appears on `GLUserProjection`; no list covariance is exercised. This
is the shape the bulk of `test/strict/` should assert against.

---

## 4. What was removed, and why (so nobody re-derives it)

| Removed | Why |
|---|---|
| `<Type>Data` concrete copy class | Not needed once relations resolve via `@SchemaMapping` (§6). The interface alone gives the all-nullable transport contract + polymorphism. |
| `toProjection()` / `toData()` selective copy | Same — no copy target to populate. |
| `prefetch()` | As written it ran in the controller *after* the service transaction already closed (non-OSIV) → would itself throw `LazyInitializationException`. Made redundant by per-resolver fetching. |
| Controller `@Transactional`-for-capture | Only existed to keep the session open during the copy/prefetch. With no copy, the controller needs no transaction it wouldn't otherwise have. |
| Always-on `Set<String>` selection injection | Was only there to drive the copy. Selection now rides on existing `injectDataFetching` (§6). |

The decisive realization: **the `LazyInitializationException` / OSIV problem only exists if
GraphQL traverses a lazy relation through a property on a detached entity.** Resolving relations
via `@glSkipOnServer` → `@SchemaMapping` (§6) means the root resolver returns only the entity's
own eagerly-loaded scalar columns, and each relation is fetched by its own resolver in its own
transaction. The problem evaporates — and the solution is identical across all data sources.

---

## 5. Data-source independence

The interface split and per-resolver relation fetching work identically for:

- **JPA / Hibernate** — root resolver returns scalar columns; relations via `@SchemaMapping`.
- **MongoDB** — documents return fully materialized; no proxies, no session.
- **Elasticsearch / Cassandra** — same; full materialization, no lazy associations.
- **R2DBC / reactive** — no lazy loading; fetch exactly what you query.

The earlier `<Type>Data`/`prefetch()` machinery was a JPA/Hibernate-only workaround that would
have taxed every backend. This design has no JPA-specific generated artifacts.

---

## 6. Relations and the selection set

- **Relations resolve via `@glSkipOnServer` → `@SchemaMapping`** — the idiomatic GraphLink
  pattern, portable across all data sources, and the on-ramp to `@BatchMapping`/DataLoader for
  N+1. Example: `Address address(User user)` delegating to a service method that does
  `addressRepo.findById(user.getAddressId())`. Each is its own resolver invocation, called only
  when the field is selected, in its own transaction.
- **The selection set is NOT a new feature.** It rides on the existing `injectDataFetching` flag
  (`config.dart` `SpringServerConfigBase.injectDataFetching`): when on, the
  `DataFetchingEnvironment` is injected into the controller and/or service and the developer does
  whatever they want with it (including deriving `Set<String>` via the verified adapter, or
  driving Mongo `fields().include` / ES `_source` projection). No correctness depends on it.

### Documented developer responsibilities (one doc note each)

1. **Relational entities must not keep object relations as direct properties.** For
   relational / JPA backends, every object-to-object reference (`User.address`,
   `User.orders`) **must** carry `@glSkipOnServer` so it resolves via its own `@SchemaMapping`
   resolver. Embedding the related object as an entity property is **not a supported pattern**
   under non-OSIV: GraphLink would emit it as a property, `PropertyDataFetcher` reads it
   post-session → `LazyInitializationException`. This is why the lazy-init hazard is
   *structurally* avoided rather than left to chance — the supported shape never traverses a lazy
   association through a detached entity. (Embedded, fully-materialized object fields on document
   stores are the exception, per §5: they are not lazy and may stay as direct properties.)
2. **Lazy scalar collections** (`@ElementCollection`, `@Basic(fetch = LAZY)`): not relations to
   types, so `@SchemaMapping` is less natural. Same rule: map eager or write a resolver. Rare.

---

## 7. Implementation approach (IR + serializers)

Reuse the **existing** interface serialization machinery (`serializeInterface` in
`java_serializer.dart:1025`, the Kotlin equivalent, and TS `_serializeType`) by synthesizing the
projection interface from the type's IR — do **not** parameterize every serializer method.

### IR: synthesize `GL<Type>Projection`

Add a method on `GLTypeDefinition` (working name `toProjectionInterface()`; the original doc's
`toProjected()`) that returns a synthetic `GLInterfaceDefinition`:

- name → `GL<Type>Projection`
- fields → built from `getSerializableFields(CodeGenerationMode.server)` (so `@glSkipOnServer`
  fields are absent exactly as they are from `<Type>` — no new filtering)
- each field's `GLType`/`GLListType` cloned with `nullable: true`
- each field's type reference (object/interface element token) rewritten to `GL<FieldType>Projection`
- `directives` → `[]` (and each field's `directives` → `[]`) — zero annotations fall out naturally
  from `serializeDecorators([])`
- a new `isProjection` bool flag set `true` (default `false` elsewhere)

`GLInterfaceDefinition extends GLTypeDefinition`, so this is inherited; user-declared interfaces
get their own `GL<Interface>Projection` and implementors carry the `: GL<Interface>Projection` through.

### `<Type>` implements the interface

Append `GL<Type>Projection` to `<Type>`'s `interfaceNames` so the existing `implements` / `: `
emission picks it up with no new code.

### Nullability decision

`forceFieldNullable` becomes context-aware instead of a flat `mode == server`:

- **`GL<Type>Projection`** → always nullable (the cloned fields are already `nullable: true`).
- **`@glServerLenient` `<Type>`** → forced nullable (today's behavior, unchanged).
- **default (non-`@glServerLenient`) `<Type>`** → **not** forced; emit real schema nullability.

Cleanest mechanism: carry strictness on the definition (default `true`, `false` if `@glServerLenient`)
and compute `forceFieldNullable` from `isProjection` + that flag, rather than a global getter.
Because the projection interface's field nullability is baked into the cloned IR, the only real
change for `<Type>` is "don't force-nullify unless `@glServerLenient`."

### Generators

For every server-mode object type, unconditionally additionally serialize
`toProjectionInterface()` and write it to the interfaces directory, and add the `implements`
clause to `<Type>`. Existing `doSerializeTypeDefinition` / `serializeField` /
`serializeDecorators` / `serializeType` need no behavioral change beyond the nullability rule and
the Java list-wildcard (§10).

### Service & boundary return types

For server methods, the return-type emission is:

- **Controller handlers and `@SchemaMapping` resolvers** → `GL<Type>Projection` (always, at the
  boundary). The generated body delegates to the service and returns the result directly; the
  concrete→interface upcast is implicit.
- **Service methods** → strict concrete `<Type>` **by default**. Expose a getter (e.g.
  `GLQueryDefinition.returnsProjection`) on the relevant `gl_grammar_*_extension.dart` that is
  `true` when the operation carries `@glReturnsProjection`; the service serializer picks
  `GL<Type>Projection` vs `<Type>` from it.
- **`@glReturnsProjection` ⇒ auto-inject `DataFetchingEnvironment`.** Whatever conditional today
  gates the `DataFetchingEnvironment` parameter on `injectDataFetching` must also fire when the
  operation's `returnsProjection` is true — i.e. the effective condition is
  `injectDataFetching || returnsProjection`, scoped to that method. Keep this derivation in the
  extension getter, not the serializer.

---

## 8. Type-kind interactions (to verify with tests)

- **Object types** — the main case, as above.
- **User-declared GraphQL `interface`s** — `GL<Interface>Projection` generated via the inherited
  `toProjectionInterface()`; implementors implement both `GL<Interface>Projection` and their own
  `GL<Type>Projection`. Verify the multi-interface `implements` list emits correctly (Java/Kotlin)
  and that TS handles it (TS renders GraphQL interfaces as union type aliases, not interfaces —
  decide whether the projection of a user interface is itself an `export interface` or follows the
  union-alias path).
- **Unions** — **decided:** GraphLink already converts a union to an interface internally, so a
  union's projection rides the **exact same inherited `toProjectionInterface()` path** as a
  user-declared interface. `GL<Union>Projection` is emitted as an interface over the
  `GL<Member>Projection`s, and each union member's `<Member>` (and `GL<Member>Projection`) carries
  the `: GL<Union>Projection` membership through the normal `implements` emission. No union-specific
  machinery is needed — it is the interface case.
- **Enums / custom scalars** — no fields, no projection. Field-ref rewrite skips them (only
  object/interface tokens are rewritten).

---

## 9. Config & activation

- **Strict is the default.** Every `type` is strict (real schema nullability) unless marked
  `@glServerLenient`. There is no `@glStrict` directive and no `generateStrictTypes` flag — the
  `GL<Type>Projection` split (§2) and strict nullability are **always generated** for server
  targets, with no activation step and no "is strictness in use anywhere" check.
- **`@glServerLenient`** — per-type directive, registered in `model/built_in_dirctive_definitions.dart`.
  Opts that one `<Type>` *out* of strict nullability: its fields are forced all-nullable,
  exactly as `GLTypeDefinition.forceFieldNullable` does for every type today. `GL<Type>Projection`
  is still generated for a `@glServerLenient` type (every type gets one, per §2), and the type still
  `implements GL<Type>Projection` — only its own field nullability reverts to all-nullable.
- **`@glReturnsProjection`** — per-**operation** directive (on a query/mutation field, or a
  `@glSkipOnServer` relation field), registered in `model/built_in_dirctive_definitions.dart`.
  Opts that one service method into returning `GL<Type>Projection` instead of the strict concrete
  `<Type>`, for selection-driven partial fetches. It also causes the `DataFetchingEnvironment` to
  be **auto-injected** into that method regardless of the global `injectDataFetching` setting — the
  selection set is required to fetch selectively, so the directive implies the injection. There is
  **no** global service-return flag; the per-operation directive is the only opt-in, so the ~99%
  who don't use it pay no all-nullable tax. (A future refinement could widen granularity, but the
  directive already targets exactly the operations that want it.)
- **Java requires `jspecify: true` to benefit.** In Java, strict vs. all-nullable is *only*
  visible to the compiler/IDE through `@NonNull`/`@Nullable` annotations, and those are emitted
  only when `jspecify` is on (`SpringServerConfig.jspecify`). With `jspecify: false`, both
  `<Type>` and `GL<Type>Projection` getters are bare `String`, and the strict/lenient distinction is
  invisible to tooling. The generator should warn (or docs should strongly recommend) enabling
  `jspecify`. Kotlin gets the distinction natively (`String` vs `String?`); TS gets it via
  `| null`.
- **No backward-compatibility mode.** Because this is an early-stage feature with no prior
  consumers, server generation always emits the `GL<Type>Projection` split — there is no "no
  strictness declared, output is byte-identical to today" path and no migration-warning step.
  `@glServerLenient` is the only per-type lever, and it affects only that type's own field
  nullability — never the global split, which is unconditional.
- Strictness is a **flat per-type boolean** (default `true`, flipped to `false` by `@glServerLenient`)
  with strictly local effects — no transitive closure.

---

## 10. The two small serializer changes to nail

1. **Java `List<? extends GLXProjection>` wildcard.** List rendering lives in
   `java_serializer.dart` `serializeTypeReactive` (the `_listOf(...)` call, ~line 251). When
   rendering a **projection-interface getter** whose element type is an object/interface type,
   emit `List<? extends GLElementProjection>` instead of `List<GLElementProjection>`. Localized:
   gate on "serializing a projection interface's list getter." Kotlin and TS need nothing
   (covariant `List<out>` / covariant arrays).
2. **Java record accessor naming — decided: match the entity kind (already supported).** When
   `<Type>` is a `record`, `GL<Type>Projection` emits record-style accessors (`id()`, not `getId()`)
   so the record satisfies the interface without explicit getters; when `<Type>` is a POJO/class,
   the interface emits JavaBean getters (`getId()`). The serializer already chooses accessor style
   from the target type's kind this way today, so `GL<Type>Projection` inherits the correct behavior
   through the existing path — no serializer change, just confirm the synthesized interface flows
   through it.

Plus one **optional** TS change:

3. **TS `extends` clause.** To emit `export interface User extends GLUserProjection`, the TS
   `createInterface` helper (`typescript_code_gen_utils.dart`) needs an `extends`/`interfaceNames`
   param — the current TS calls (`typescript_serializer.dart:119,145`) pass only `interfaceName` +
   `fields`, unlike Java's `createInterface` which already takes `interfaceNames`. Small addition.
   If skipped, pure structural typing still works.

---

## 11. Naming: avoid clash with the client projection feature

`projectedTypes` / `projectedInterfaces` already exist in `gl_grammar_projection_extension.dart`
— but that is the **client-side** "minimal type derived from a query's selection set/fragments"
feature (the `test/projections/` suite). The server `GL<Type>Projection` interface is a **different**
concept. They never coexist in one output (client-mode vs server-mode), but reusing "projection"
internally will confuse maintainers. Give the new server artifact a **distinct internal IR name**
(e.g. the `isProjection` flag plus a term like `entityInterface` / `transportInterface` in code),
even though the **generated** suffix stays `Projection`.

---

## 12. Non-goals

- No change to input (`@glMapsTo`/`@glMapField`) mapping.
- No reverse (`GL<Type>Projection` → `<Type>`) mapping.
- No `<Type>Data` / copy / `prefetch()` / capture / always-on selection / closure.
- No `@glStrict` directive, no `generateStrictTypes` flag, no activation step, no
  backward-compat "split is off" mode — see §9.

---

## 13. Open items

Resolved and moved into the body: union handling (§8 — rides the interface path), record accessor
naming (§10.2 — match the entity kind), return types (§2.3 — boundary returns `GL<Type>Projection`,
services return strict concrete `<Type>` by default, `@glReturnsProjection` opts a single
operation into projection returns + auto-injected `DataFetchingEnvironment`), relation handling
(§6 — always `@glSkipOnServer`). Still open:

1. **User-declared GraphQL interface + TS** — TS renders GraphQL interfaces as union type aliases.
   Decide the projection shape for a user interface in TS (an `export interface` vs following the
   union-alias path). The `GL<Union>Projection` decision in §8 leans toward emitting an
   `export interface`; confirm that is consistent for user-declared interfaces too in TS.
2. **Reactive return types** — confirm return-type emission wraps correctly for both shapes:
   boundary methods in `Mono<GLUserProjection>` / `Flux<GLUserProjection>` / `suspend ... :
   GLUserProjection`, and default concrete service methods in `Mono<User>` / `Flux<User>` /
   `suspend ... : User`.

---

## 14. Test plan

Add a `test/strict/` suite (self-contained `.graphql` + Dart tests asserting on emitted output):

- Kotlin: `GL<Type>Projection` interface (all-nullable, no annotations), `<Type> : GLUserProjection`
  with `override`, `List<out>` covariance (no wildcard), default-strict vs `@glServerLenient`
  nullability.
- Java: same, plus `List<? extends GLXProjection>` on the interface and covariant single-object
  returns; record and POJO variants; accessor-name agreement.
- TS: both `export interface`s, optional `extends`, covariant arrays, structural assignability.
- Controllers/services: return type is `GL<Type>Projection`; controller returns service result
  directly; no `<Type>Data`/`@Transactional`-for-capture emitted.
- `GL<Type>Projection` and the split are emitted unconditionally — verify a schema with zero
  directives still gets the full split, and that `@glServerLenient` only changes that one type's field
  nullability (not the split).
- `@glSkipOnServer` fields absent from both `<Type>` and `GL<Type>Projection`.
- Interactions: user-declared interface implementor implements both projections; union handling
  per §13.

End-to-end (later): a generated strict server target under `server_integration_tests/` driven by
a generated client harness, verifying relations resolve via `@SchemaMapping` under both OSIV and
non-OSIV.
