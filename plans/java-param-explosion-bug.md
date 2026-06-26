# Java Client: 1216-Parameter Method Explosion

## Symptom

Compiling `GraphLinkQueries.java` fails with:

```
GraphLinkQueries.java:[285,30] too many parameters
```

The `enterprise` method has **1216 parameters** — 5× over Java's 255 limit.

## The `enterprise` query in the schema

```graphql
enterprise(
  invitationToken: String
  slug: String!
): Enterprise
```

Only **2 arguments**.

## What the 1216 actually are

Every parameter beyond the first 2 is a **field-level argument** from the
`_all_fields_Enterprise` fragment tree, promoted to a query-level variable:

| Parameter | Source |
|---|---|
| `avatarUrlSize` | `Enterprise.avatarUrl(size: Int)` |
| `assignedOrganizationsAfter` | `Enterprise.organizations(after: String, ...)` |
| `assignedOrganizationsFirst` | `Enterprise.organizations(first: Int, ...)` |
| `twoFactorRequiredSettingOrganizationsValue` | Deeply nested field on `Enterprise` |
| ... | (1211 more) |

The auto-query system recursively walks every field at every depth in the
`Enterprise` type and collects ALL field arguments — including pagination
cursors (`after`, `before`, `first`, `last`), order-by inputs, filter
booleans, etc. — and adds them as `$variables` on the query definition.

## Why this is a bug

1. **Uncompilable** — Java's method parameter limit is 255. 1216 is 5× over.
2. **Unusable** — No developer can or should call a method with 1216
   parameters. Most are optional pagination/filter args with sensible defaults.
3. **Unnecessary** — The generated method body shows that 95%+ of these
   parameters just get default-coalesced:
   ```java
   if (assignedOrganizationsOrderBy == null) {
     assignedOrganizationsOrderBy = new EnterpriseTeamOrganizationOrder(...);
   }
   ```
   They never vary per-call in practice.
4. **Explosive recursion** — `_all_fields_Enterprise` depends on nested
   fragments (`_all_fields_Organization`, `_all_fields_User`, …). Field
   arguments from the entire transitive dependency graph are collected,
   creating a combinatorial explosion.

## Root cause

The auto-query argument collection (in `GLGrammarFragmentExtension`) does not
distinguish between:

- **The query's own arguments** — legitimate to expose as method parameters
- **Field arguments needed by the fragment tree** — should use defaults or a
  config object, not individual method parameters

## Possible fixes

1. Stop promoting fragment field arguments to method parameters altogether
2. Only promote required (non-null, no-default) field arguments
3. Cap the depth of argument collection
4. Use a builder / input-object pattern for fragment-derived arguments
5. Emit a single `Map<String, Object>` parameter for the fragment field args
