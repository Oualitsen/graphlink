# Projected Types — Blind Fast Path for Abstracts (interfaces/unions)

## Goal

Make `createProjectedTypes` fast on large, abstract-heavy schemas (e.g. the
GitHub schema: ~1008 types, 52 interfaces, 47 unions) **without** changing the
generated output.

This doc records *what was changed and why*, so the optimization can later be
revisited / replaced with a structurally cleaner solution that does not depend on
a special-cased "fast path".

---

## Where this lives

- `lib/src/gl_grammar_projection_extension.dart` — `createProjectedTypes()` and its
  helpers (`createProjectedType`, `_registerAllFieldsBlind`,
  `_isSoleAllFieldsSpread`, and the now-removed `_reachesAbstract`).
- `lib/src/model/new_parser/gl_parser.dart` — the `_timed(...)` instrumentation
  wrapping each step of the client-mode `validateSemantics()` pipeline (kept in
  the tree to keep profiling the pass; logs at debug level).

`createProjectedTypes` runs in the client branch of
`GLParser.validateSemantics()`.

---

## Background — what `createProjectedTypes` does

For every query operation, GraphLink turns the operation's selection set into a
concrete "projected type" (the shape actually returned/deserialized). With
`generateAllFieldsFragments` + `autoGenerateQueries`, each declared type gets an
auto-generated query whose selection is a single `_all_fields_<T>` spread.

Per query element, `createProjectedType` has two routes:

1. **Slow path** — `createProjectedTypeOnType`: rebuild every field, allocate a
   fresh `GLTypeDefinition`, compute `getHash` (serializes the whole field set),
   then `findSimilarTo` (hash-bucket scan + `isSimilarTo`) to dedup, then
   generate a name. This is the general, always-correct route.
2. **Fast (blind) path** — `_registerAllFieldsBlind`: when the selection is just
   the generated all-fields spread, the projected type *is* the declared type
   (its cyclic edges were already relaxed to nullable by
   `forceCyclicEdgesNullable`). So we register the declared type (and everything
   reachable) directly, skipping the rebuild + `getHash` + `findSimilarTo` work.

The blind path is the key to performance: for an all-fields/auto-query schema the
overwhelming majority of projected types are just the declared types, so the slow
path's hashing and similarity scanning is pure overhead.

---

## The problem

The blind fast path was gated so it **only applied to pure-object subgraphs**.
The gate (in `createProjectedType`) was:

```dart
if (type is! GLInterfaceDefinition &&
    _isSoleAllFieldsSpread(projectionMap) &&
    !_reachesAbstract(type, <String>{})) {
  _registerAllFieldsBlind(type, <String>{});
  ...
}
```

with `_reachesAbstract` returning `true` if the type — or **any object type
reachable from it through fields** — either implements an interface, or has a
field whose target is an interface or union.

Two consequences made the fast path almost never fire on real schemas:

1. **Interface/union roots were excluded outright** (`type is! GLInterfaceDefinition`),
   and `_registerAllFieldsBlind` only knew how to walk *object* types — it
   ignored interface/union targets, so it could not produce the projected-interface
   structure. `_reachesAbstract` existed purely as a safety net for that gap.

2. **`_reachesAbstract` is all-or-nothing at the root.** A single interface or
   union *anywhere downstream* disqualifies the entire tree from the fast path.
   In a schema like GitHub's — where a `Node`-style interface is implemented by
   almost everything — virtually every root reaches an abstract, so nearly the
   whole schema fell back to the slow `getHash` + `findSimilarTo` path. That is
   the bottleneck.

There was also a secondary correctness/efficiency bug in the gate's first
condition (see below).

### Secondary bug: `_isSoleAllFieldsSpread` length check

```dart
bool _isSoleAllFieldsSpread(Map<String, GLProjection> projectionMap) {
  if (projectionMap.length != 1) return false;            // <-- too strict
  return projectionMap.values.first.allFieldsSpread;
}
```

`__typename` is auto-injected into inline-fragment blocks
(`GLInlineFragmentDefinition` constructor, `lib/src/model/gl_fragment.dart`) and
is carried by interface/union all-fields projections because it is required for
`fromJson` dispatch. So a block can legitimately be
`{ <all-fields spread>, __typename }` (length 2), which the `length != 1` check
wrongly rejected. "Sole all-fields spread" should mean *exactly one real
selection that is an all-fields spread*, ignoring the implicit `__typename`.

---

## Why blind registration is correct for abstracts

The all-fields fragment of an interface (built by `_createProjectionForInterface`
in `gl_grammar_fragment_extension.dart`) projects through **every** implementor:

```
_all_fields_Pet  ->  ... on Dog { _all_fields_Dog __typename }
                     ... on Cat { _all_fields_Cat __typename }
```

So the all-fields projection of an interface is structurally the **declared
interface** (all its fields, all implementors), and each implementor's projection
is structurally its **declared type**. Unions are converted to interfaces by
`convertUnionsToInterfaces` before this pass, so they behave identically.

This was verified empirically (schema: interface `Pet` with `Dog`/`Cat`, plain
object `Owner`): the *slow path already produced* bare `Pet` in
`projectedInterfaces` (implementations `[Dog, Cat]`) and bare `Dog`/`Cat` in
`projectedTypes`. It just paid `getHash` + `findSimilarTo` + name generation per
node to rediscover the declared shapes. Blind registration produces the same
result directly.

The `interface_union_handling_test.dart` cases confirm the partial-vs-full split
is preserved:
- auto `getAnimal` (full all-fields) → `getAnimal` field type `Animal` (bare).
- hand-written `getMyAnimal` (partial `... on Dog { name } ... on Cat { name }`)
  → field type `Animal_Name` (slow path, generated name). Because its block is
  **not** an `allFieldsSpread`, `_isSoleAllFieldsSpread` returns false and it
  correctly stays on the slow path.

---

## The fix

### 1. `_isSoleAllFieldsSpread` ignores `__typename`

```dart
bool _isSoleAllFieldsSpread(Map<String, GLProjection> projectionMap) {
  GLProjection? spread;
  for (final entry in projectionMap.entries) {
    if (entry.key == GLParser.typename) continue;
    if (spread != null) return false; // more than one real selection
    spread = entry.value;
  }
  return spread != null && spread.allFieldsSpread;
}
```

### 2. `_registerAllFieldsBlind` handles interfaces/unions

- If `type` is a `GLInterfaceDefinition`: register the declared interface into
  `projectedInterfaces`, wire its implementations
  (`type.addImplementation(impl)` / `impl.addInterface(type)`), and recurse into
  each implementor.
- For object fields whose target is an interface/union (resolved via the
  `interfaces` map, which already includes converted unions), recurse into that
  abstract instead of skipping it.
- A per-store `containsKey` guard makes the walk **idempotent across query
  elements**: a type reachable from many roots is registered exactly once. (The
  old object-only version re-registered the same declared type once per element,
  appending duplicate entries to the `_typeHashIndex` bucket and lengthening
  every later `findSimilarTo` scan.)

### 3. Gate simplified

`_reachesAbstract` is **removed**. The fast path is now gated only by
`_isSoleAllFieldsSpread`:

```dart
if (_isSoleAllFieldsSpread(projectionMap)) {
  _registerAllFieldsBlind(type, <String>{});
  return type is GLInterfaceDefinition
      ? (projectedInterfaces[type.token] ?? type)
      : (projectedTypes[type.token] ?? type);
}
```

---

## Verification

Relevant suites pass **individually** (run per-file to avoid the pre-existing
cross-file global-state contamination described below):

- `test/inheritence/interface_union_handling_test.dart`
- `test/projections/projections_test.dart`
- `test/interface/interface_test.dart`
- `test/interface/interface_extends_interface_fromjson_test.dart`
- `test/base_types_and_unions/unions_test.dart`
- `test/inheritence/inheritance_projection_test.dart`
- `test/inheritence/double_clause_test.dart`

(The full suite was not run — project rule: never run all tests without explicit
acceptance. Use the `_timed` debug logs in `validateSemantics` to measure the
`createProjectedTypes` step on a large schema before/after.)

---

## Known limitations / debt for the future revisit

The whole point of this note: **the speed currently depends on a special-cased
fast path.** A cleaner long-term design would make the *general* path fast enough
that the blind shortcut is unnecessary. Things to address when revisiting:

1. **The fast path is a parallel code path.** It duplicates structural knowledge
   (what the all-fields projection of a type/interface looks like) that also
   lives in the slow path and in the fragment generator. Divergence risk.

2. **`createProjectedTypeOnType` (slow path) is the real cost.** It rebuilds the
   full field set, allocates new `GLTypeDefinition`/`GLField` objects, and hashes
   them, even when the answer is "the declared type". A better approach: detect
   structural identity up front, or memoize projected types by
   (type, selection-set) identity, so the slow path is only taken for genuinely
   partial projections.

3. **`getHash` allocates a `GLGraphqlSerializer(g)` per uncached call**
   (`gl_type_definition.dart`). The parser already owns a shared `g.serializer`;
   reuse it. (`_cachedHash` covers repeat calls on the same definition, but each
   freshly-built projected type still hashes once.)

4. **`_typeHashIndex` / `_interfaceHashIndex` are file-level mutable globals** in
   `gl_grammar_projection_extension.dart`, cleared at the start of
   `createProjectedTypes`. This causes **cross-test contamination** when multiple
   test files run in the same isolate (observed: a batch run of
   projections+interface+unions+inheritence+fragments fails the same way on
   `main`, before this change — `+12 -1`). These should be **instance fields on
   `GLParser`** (like `sccIdsCache`, `fragmentBlockCache`, etc.). Doing so also
   removes the need to `.clear()` them and the risk of stale state leaking
   between parser instances. Not fixed here to keep the change scoped to
   `createProjectedTypes` behavior.

5. **`_reachesAbstract` removal widened fast-path coverage.** If a future change
   reintroduces a projected structure for abstracts that is *not* the declared
   interface (e.g. interface-level field narrowing), the blind path assumption
   ("projected interface == declared interface for a full all-fields spread")
   must be re-checked.

---

## Out of scope (intentionally left in working tree, not part of this work)

- `test/pfav_perf/pfav_perf_test.dart` threshold change (2000ms → 12000ms) — not
  authored as part of this optimization; left out of the PR.
