# Plan: @glExpand — Cycle Detection & Forced Nullability

## Context

GraphLink auto-generates all-fields fragments and query strings
(`generateAllFieldsFragments` / `autoGenerateQueries`). When the schema's
object-type graph contains a cycle, this expansion cannot continue forever —
a query string is finite. `@glExpand(depth: N)` already bounds how deep the
**query selection** recurses into a cyclic relation.

### Cycle-breaking is the default, not opt-in

`@glExpand` is **not** required for any of this to happen. A cycle in the
schema makes all-fields expansion non-terminating regardless of whether the
directive is present, so **cycle detection and breaking run by default** for
every cyclic type, using `defaultExpandDepth` (default `1`). `@glExpand(depth:)`
only **overrides the depth** for the query/fragment selection of a specific
type — it never decides *whether* the cycle is broken. The type-level forced
nullability (below) is purely structural and applies to every in-SCC edge
whether or not `@glExpand` is written anywhere.

### Terminology: these are `_all_fields_<Type>` fragments

GraphLink does not emit standalone "projection" classes for this path. It
generates **all-fields fragments** named `_all_fields_<Type>`
(`GLGrammarExtension.allFieldsFragmentName`, `allFields = '_all_fields'`),
spread into the auto-generated query selections. The plain `Author` / `Book`
classes shown below are illustrative shorthand for "the type produced by the
`_all_fields_Author` / `_all_fields_Book` fragment" — the cycle/nullability
rule applies to those fragments and the projected types derived from them.

### The problem

The problem is on the **type** side, not the query side. The current
implementation tries to bound the type by inline-expanding cyclic types up to
`depth` levels, which:

1. Either collapses the root and the depth-1 intermediate into a single
   self-referential type (depth ≥ 2 produces an unused `<Type>_<gibberish>`
   leaf), or
2. Would require one distinct, gibberish-named type per depth level.

It also leaves `isExhaustive` returning wrong results for `depth > 1`, and —
critically — makes a field's **nullability depend on `depth`**.

### Why depth-dependent nullability is unacceptable

We target null-safe languages (Dart, Kotlin, TypeScript, and Java via
JSpecify). A field's nullability is part of its public type contract. If
bumping `depth` could flip `book` from `Book` to `Book?`, then a config change
silently turns every `author.book.title` in user code into a compile error
(Dart/Kotlin/TS) or a JSpecify violation (Java).

The generated **type** must therefore be **depth-independent**. Only the
generated **query/fragment** is allowed to vary with `depth`.

### The parity argument (why one type set forces break-all)

Consider a two-type cycle with non-null edges:

```graphql
type Author {
  id: ID!
  name: String!
  book: Book!      # non-null
}

type Book {
  id: ID!
  title: String!
  author: Author!  # non-null — closes the Author ↔ Book cycle
}

type Query {
  getAuthor(id: ID!): Author!
}
```

`@glExpand(depth: N)` on `getAuthor` adds one hop per increment:

```
depth 0:  { id name }
depth 1:  { id name book { id title } }
depth 2:  { id name book { id title author { id name } } }
depth 3:  { id name book { id title author { id name book { id title } } } }
```

The **leaf type alternates with every increment** — even depth ends on an
`Author` (drops `book`), odd depth ends on a `Book` (drops `author`):

| depth | leaf type | dropped edge | ⇒ must be nullable |
|------:|-----------|--------------|--------------------|
| 0 | `Author` | `Author.book` | `Author.book` |
| 1 | `Book`   | `Book.author` | `Book.author` |
| 2 | `Author` | `Author.book` | `Author.book` |
| 3 | `Book`   | `Book.author` | `Book.author` |

Because we emit **one** `Author` class and **one** `Book` class regardless of
`depth`, **both** `Author.book` and `Book.author` must be nullable — otherwise
`fromJson` crashes for every depth of the wrong parity.

This rules out "minimal break" (relaxing only one canonical back-edge): for a
fixed type set, every edge in the cycle is a potential truncation point.
A "full-loop depth" definition would let one edge stay non-null, but it is
**query-set-dependent** (a later `getBook` query flips the requirement) and
contradicts the single-hop `depth` semantics — rejected.

**Conclusion:** every field whose target type is in the same cycle is forced
nullable. For the common case of a self-cycle (e.g. `Employee.manager`) there
is only one cyclic edge, so this is identical to "break the single edge" — the
extra cost is paid only on genuine multi-type cycles, where it is unavoidable.

---

## Design

### Rule

Build the directed graph of object types (edges = object-typed fields, list
element types included, interface/union targets expanded to their members).
Compute strongly-connected components (Tarjan). Then:

> A field is **forced nullable** in the generated `_all_fields_<Type>` fragment
> (and the projected type derived from it) **iff** the field's target type and
> the field's declaring type belong to the same SCC.

This runs by default for every cyclic type — `@glExpand` is not required.
An SCC (Strongly-Connected Component) is the set of types that are all mutually
reachable through object-field edges, i.e. the types tangled in a cycle
together. Self-cycles are singleton SCCs with a self-edge.

- A self-edge is a singleton SCC — its one cyclic field is forced nullable.
- A cyclic type may still have **outward** edges to non-cyclic (leaf) types;
  those keep their **declared** nullability.

```graphql
type Author {
  id: ID!
  name: String!
  book: Book!         # Book ∈ SCC(Author)        → forced nullable → Book?
  country: Country!   # Country ∉ SCC(Author)      → stays non-null  → Country
}
```

### List edges

For an in-SCC list field, relax the **outer** type only — the relation may be
absent, but its elements are not individually nullable:

```
[Order!]!   →   List<Order>?      (NOT List<Order?>)
```

This matches the existing `_toProjectionFieldType` convention
(`lib/src/model/gl_type_definition.dart`).

### Interface / union edges

A field returning an interface or union counts as in-SCC if **any** concrete
member type is in the declaring type's SCC. Without this, indirect cycles that
pass through an abstract type slip past the detector and produce non-null
self-referential edges that cannot deserialize.

### Type vs query/fragment (decoupled)

- **Type / `_all_fields_<Type>` fragment:** depth-independent. Full field set;
  in-SCC edges nullable. One fragment + one projected type per type. No
  `<Type>_<gibberish>` per-level types for the cyclic case.
- **Query selection:** depth-bounded, single-hop semantics, exactly as today —
  the auto-generated query spreads `_all_fields_<Type>` and recurses into the
  cyclic relation up to `depth` levels:
  - `depth 0` → `{ id name }` (cyclic relation omitted from the selection)
  - `depth 1` → `{ id name book { id title } }`
  - `depth 2` → `{ id name book { id title author { id name } } }`
  - `depth: 0` is **kept** — it is the legitimate "scalars only, don't recurse"
    shallow fetch.

At any depth, an omitted cyclic edge is absent from the JSON and reads back as
`null` — consistent with the forced-nullable type.

### `isExhaustive`

A cyclic projected type now holds **every** schema field (in-SCC edges merely
relaxed to nullable). It is therefore exhaustive by construction. Redefine
exhaustiveness as **full field coverage** rather than recursive descent into
sub-projections. This:

- makes the cyclic type correctly exhaustive for all depths, and
- removes the infinite-recursion hazard in the current
  `GLTypeDefinition.isExhaustive` (where `sub == this` for a self-referential
  type). A visited-set guard is the fallback if descent is retained.

---

## Validation (already implemented)

`@glExpand(depth:)` must be a non-negative integer (`>= 0`). A negative or
non-integer value throws `ParseException`. A missing `depth` falls back to
`defaultExpandDepth` (default `1`).

- `lib/src/gl_expand_grammar_extension.dart` — `checkGLExpandDirectives()`
- Wired into `GLParser.validateSemantics()` before `createAllFieldsFragments()`.

---

## Implementation steps

1. **SCC pass.** Add a cycle-detection getter to a grammar extension
   (`gl_expand_grammar_extension.dart`): build the object-type graph
   (fields → target type, list elements unwrapped, interface/union members
   expanded) and compute SCCs. Expose `bool fieldClosesCycle(ownerType, field)`
   or a precomputed `Set` of in-SCC `(type, field)` edges.

2. **Force nullability** when building the `_all_fields_<Type>` fragments and
   their projected types (`gl_grammar_fragment_extension.dart` —
   `generateAllFieldFragment` / `_generateForField` and the projected-type
   construction): when a field's edge is in-SCC, emit it nullable
   (outer-nullable for lists). This applies to every cyclic type by default,
   independent of `@glExpand`. Replace the existing depth-based
   inline-expansion type multiplication.

3. **Query selection** keeps single-hop depth bounding (`defaultExpandDepth`,
   overridden per-type by `@glExpand(depth:)`); ensure the omitted-edge case is
   driven by `depth`, decoupled from the fragment/type shape.

4. **`isExhaustive`** (`lib/src/model/gl_type_definition.dart`): redefine as
   full-field coverage; remove the self-recursion hazard.

5. **Tests** (`test/gl_expand/`):
   - Two-type non-null cycle (`Author`/`Book`): both edges nullable in the
     generated Dart types; `fromJson` round-trips at depth 0, 1, 2.
   - Self-cycle: single edge nullable; query strings at depth 0/1/2 match the
     single-hop expansion.
   - Outward leaf edge keeps declared non-null nullability.
   - Interface/union-mediated cycle is detected.
   - `isExhaustive` true for cyclic projected types at depth > 1.
   - Negative / non-int depth throws (already covered).

---

## What this avoids

- No `<Type>_<gibberish>` per-depth type explosion.
- No depth-dependent nullability — generated type contracts are stable across
  `depth` changes, safe for Dart/Kotlin/TS/JSpecify.
- No query-set-dependent nullability.
