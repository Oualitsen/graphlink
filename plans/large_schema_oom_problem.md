# Large Schema OOM / Fragment Generation Problem

## Goal
GraphLink should be able to handle arbitrarily large schemas (target: 10M types).
Currently it fails on the real-world github schema (`test/github_schema/schema.docs.graphql`) — **1008 types, 401 inputs, 252 enums, 47 unions, 52 interfaces**.

---

## What has been fixed already (merged to main)

### 1. Stack overflow in `_createInlineExpandBlock`
**File:** `lib/src/gl_grammar_fragment_extension.dart`

`_createInlineExpandBlock` is called recursively to inline-expand cyclic fields in all-fields fragments. A long non-cyclic chain (Link1→Link2→...→LinkN→CyclicRoot) caused a Dart stack overflow because non-cyclic types never decremented `remainingDepth`, so the recursion was unbounded.

**Fix applied:** Path-based cycle detection — track types visited on the current call stack. The path check is **only applied to non-cyclic types** (types NOT in `cycleTypes`), because cyclic types must be allowed to re-enter for `@glExpand(depth:N)` to work correctly.

```dart
// correct: path check only for non-cyclic types
if (path.contains(typeName) && !cycleTypes.contains(typeName)) return null;
```

**Test:** `test/fragment/circular_type_reference_test.dart`

---

## The remaining problem: OOM during `createAllFieldsFragments`

### What happens
Pipeline memory at start: **~260 MB** (just for parsing 1008 types).  
`createAllFieldsFragments` is called and **exhausts memory before generating even ~10 fragments**.

### Root cause
`_createInlineExpandBlock` is called for each cyclic field in a type being generated. For a cyclic type in `inProgress`, at depth=0 (default `@glExpand(depth:1)` → `depth-1=0`):

- **Cyclic fields** (`fieldTypeName in cycleTypes`): correctly skipped (`isCyclic && remainingDepth <= 0 → null`)
- **Non-cyclic fields**: `nextDepth = remainingDepth` (UNCHANGED) → recursion continues with the same depth=0 through the entire non-cyclic subgraph

Example:
```
_createInlineExpandBlock("User", depth=0, cycleTypes={User, Project})
  address: Address  (non-cyclic, depth stays 0)
    district: District  (non-cyclic, depth stays 0)
      region: Region  (non-cyclic, depth stays 0)
        country: Country  (non-cyclic, depth stays 0)
          ...
```
For the github schema with 1008 types and deep inter-connections, this traverses hundreds of types per cyclic field, creating millions of `GLProjection` / `GLFragmentBlockDefinition` objects → OOM.

### Why this is hard to fix

The spec for `@glExpand` is: **depth only limits re-entry into the cyclic type itself, not the expansion of non-cyclic types**. So simply decrementing depth for all fields breaks `@glExpand(depth:2)` behaviour.

Attempted fix that was reverted: `if (remainingDepth <= 0) return null` for ALL object fields — this fixed OOM and `@glExpand(depth:2)` (with the cyclic-exclusion path fix), but the user correctly identified it changes the semantics: non-cyclic fields should be fully expanded, not limited by the cyclic depth.

---

## Current state of `_createInlineExpandBlock`

```dart
GLFragmentBlockDefinition? _createInlineExpandBlock(
    String typeName, int remainingDepth, Set<String> cycleTypes,
    [Set<String>? visitedOnPath]) {
  final path = visitedOnPath ?? <String>{};
  // Only block non-cyclic types from path revisit; cyclic types use depth.
  if (path.contains(typeName) && !cycleTypes.contains(typeName)) return null;

  final typeDef = types[typeName] ?? interfaces[typeName];
  if (typeDef == null) return null;

  path.add(typeName);

  final projections = typeDef.getSerializableFields(mode).map((field) {
    if (!typeRequiresProjection(field.type)) {
      return GLProjection(scalar...);
    }
    final fieldTypeName = field.type.inlineType.token;
    final isCyclic = cycleTypes.contains(fieldTypeName);

    if (isCyclic && remainingDepth <= 0) return null;

    final nextDepth = isCyclic ? remainingDepth - 1 : remainingDepth; // ← non-cyclic stays same
    return GLProjection(block: _createInlineExpandBlock(fieldTypeName, nextDepth, cycleTypes, path));
  }).whereType<GLProjection>().toList();

  path.remove(typeName);
  return GLFragmentBlockDefinition(projections);
}
```

**The path check bounds LINEAR stack depth** but does NOT bound the NUMBER of objects created — each unique non-cyclic type in the subgraph still gets fully expanded inline, creating a large object tree.

---

## Key constraint

The path check (non-cyclic only) prevents stack overflow but not OOM because:
- The github schema has wide non-cyclic subgraphs reachable from cyclic types
- Each unique type appears at most once per path (path check), but there are hundreds of unique types
- Creating inline `GLFragmentBlockDefinition` / `GLProjection` trees for all of them simultaneously causes OOM

---

## What was discussed but not implemented

The user suggested a smarter approach: instead of inlining the non-cyclic subgraph at depth=0, use **pre-generated fragment spreads** as cycle-break anchors. The idea was dropped because it got complicated. The direction to explore is finding a way to bound the non-cyclic inline expansion without changing the `@glExpand` depth semantics.

---

## Files relevant to this problem

- `lib/src/gl_grammar_fragment_extension.dart` — `_createInlineExpandBlock`, `createAllFieldsFragment`, `createAllFieldsFragments`
- `lib/src/gl_grammar_extension.dart` — `allFieldsFragmentName`, `defaultExpandDepth`
- `test/github_schema/github_probe.dart` — probe script that runs generation against the github schema and prints memory per step
- `test/github_schema/fragment_inspect.dart` — small test to inspect generated fragments
- `test/github_schema/schema.docs.graphql` — the 1.4MB github schema
- `test/gl_expand/gl_expand_test.dart` — tests for `@glExpand` depth behaviour (must all pass)
- `test/fragment/circular_type_reference_test.dart` — regression test for the stack overflow fix
