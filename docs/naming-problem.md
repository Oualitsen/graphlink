# Naming Problem: Exhaustive Projections Should Use Clean Type Names

## The Philosophy

When a query projection selects **all fields** of a type, the generated class should use
the schema type's name directly (`Employee`) rather than a structural name
(`Employee_IdManagerName`). This is already the intended behavior — the mechanism
exists — but it breaks for types involved in `@glExpand` cycle-breaking.

## How Clean Naming Currently Works (Non-Cyclic)

`createProjectedTypes` pre-populates `_typeHashIndex` with all schema types.
When `addToProjectedTypes` is called for a projected type, it calls `findSimilarTo`,
which does a hash lookup:

```
projected type hash == schema type hash → findSimilarTo returns schema type → clean name used
```

The hash is computed from field names + their serialized types:
```
User { firstName: String!, lastName: String!, address: Address }
hash = "address:Address?,firstName:String!,lastName:String!"
```

If the projected User selects all fields and its sub-projections also have clean names,
the hash cascades correctly and `findSimilarTo` finds the schema type → `"User"`.

## Where It Breaks With @glExpand

With cyclic inline expansion (e.g. `Employee { manager: Employee }`, default depth 1),
`createAllFieldsFragment` generates:

```graphql
fragment allFields_Employee on Employee {
  id
  name
  manager {      # inline block — NOT a fragment spread
    id
    name
    # manager omitted (depth exhausted)
  }
}
```

The `manager` sub-block has only scalar fields. Its projected type is named
`Employee_IdName` (structural, because it only has 2 of 3 fields).

Now when computing the hash of the outer `Employee` projected type:

```
outer Employee hash = "id:ID!,manager:Employee_IdName?,name:String!"
schema Employee hash = "id:ID!,manager:Employee?,name:String!"
```

**The hashes differ** because `Employee_IdName ≠ Employee`.
`findSimilarTo` returns nothing → `_generateName` falls through to structural name
→ `Employee_IdManagerName` instead of `Employee`.

The same cascade failure applies to multi-type cycles:
`Customer → Order → Product → Supplier → Customer`.
The leaf `Customer_IdName` (from Supplier's inline-expanded `customers` field)
causes the entire chain to get structural names.

## Root Cause

The inline-expanded leaf type (`Employee_IdName`) is a **partial projection of
`Employee`** — it has all scalar fields but is missing the cyclic complex field
(`manager`). It was dropped by the cycle-breaker, not by the developer.
Yet `findSimilarTo` has no way to know this — it just sees a hash mismatch.

## Proposed Fix

Add a flag to the leaf type to signal that it is **exhaustive because of cycle-breaking**
(not because the developer intentionally omitted fields).

**Step 1** — Identify cyclic leaves after `createProjectedTypes()`:

A projected type `P` derived from schema type `X` is a *cyclic leaf* if:
- It has all **scalar** fields of `X`
- Its only missing fields are **complex** fields (the cyclic back-references that
  were dropped by `_createInlineExpandBlock`)

**Step 2** — Update `findSimilarTo` to recognise cyclic leaves:

When no hash match is found, check if the definition is a cyclic leaf for its
`derivedFromType`. If yes, return that schema type as the similar definition.

**Effect** — With `Employee_IdName` recognized as a cyclic leaf for `Employee`:
- `findSimilarTo(Employee_IdName)` → returns schema `Employee`
- `manager` field type becomes `Employee` (clean name)
- Outer `Employee` hash → `"id:ID!,manager:Employee?,name:String!"` = schema hash
- `findSimilarTo(outerEmployee)` → returns schema `Employee` → clean name ✓

The cascade is restored without touching `_generateName` or the hash function.

## Constraints

- Only apply cyclic-leaf detection when `generateAllFieldsFragments: true`
  (otherwise it would affect manually-written partial projections).
- A type is only a cyclic leaf if ALL its missing fields are complex types —
  never scalars. This prevents false positives for hand-written queries that
  omit scalar fields.
- The check must use `derivedFromType` (the schema type a projected type was
  built from) to know which schema type to compare against.
