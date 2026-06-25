# Client Code-Gen Refactor Plan

This document tracks the ongoing refactor to make Dart, TypeScript, Java, and Kotlin
client serializers consistent: delegating operation rendering to a dedicated operation
serializer, using top-level const variable names instead of `safeLocalVar`, and emitting
each generated type into its own file.

Dart is **complete**. TypeScript is next, then Java/Kotlin const cleanup.

---

## Status

| Target | Delegation | Const vars | Separate files |
|---|---|---|---|
| Dart | ✅ Done | ✅ Done | ✅ Done |
| TypeScript | ✅ Done | ✅ Done | ✅ Done |
| Java | ✅ Done (context class) | ⬜ Planned | ✅ Done |
| Kotlin | ✅ Done (context class) | ⬜ Planned | ✅ Done |

---

## Task A — TypeScript: full parity with Dart

### A1. Create `typescript_client_vars.dart`

Top-level `const` strings replacing all `_cg.safeLocalVar(...)` getters in
`TypeScriptClientSerializer`. Pattern: `'gl_${name}__'` (same as Dart).

Variables needed (from current `_sv*` getters in `typescript_client_serializer.dart`):

```dart
const svOperationName    = 'gl_operationName__';
const svVariables        = 'gl_variables__';
const svPartialQueries   = 'gl_partialQueries__';
const svResponseMap      = 'gl_responseMap__';
const svStaleData        = 'gl_staleData__';
const svCacheFutures     = 'gl_cacheFutures__';
const svRemaining        = 'gl_remaining__';
const svRemainingCount   = 'gl_remainingCount__';
const svPayload          = 'gl_payload__';
const svResponseText     = 'gl_responseText__';
const svResponse         = 'gl_response__';
const svResult           = 'gl_result__';
const svData             = 'gl_data__';
const svQuery            = 'gl_query__';
const svFragMap          = 'gl_fragmentMap__';
const svTagLocks         = 'gl_tagLocks__';
const svStore            = 'gl_store__';
const svAdapter          = 'gl_adapter__';
const svHandler          = 'gl_handler__';
const svMultipartAdapter = 'gl_multipartAdapter__';
const svMap              = 'gl_map__';
const svParts            = 'gl_parts__';
const svSlot             = 'gl_slot__';
const svAllParts         = 'gl_allParts__';
const svGen              = 'gl_gen__';
```

Remove `TypeScriptCodeGenUtils.safeLocalVar` once these replace all call sites.

---

### A2. Create `typescript_client_operation_serializer.dart`

Extract from `TypeScriptClientSerializer` into a new class
`TypeScriptClientOperationSerializer(GLParser, TypeScriptCodeGenUtils, GLGraphqlSerializer, GLSerializer, {bool observables})`:

Methods to extract:
- `_queryToMethod(def)` — cache + partial query logic
- `_mutationToMethod(def)` — delegates to `_mutationToMultipartMethod` for uploads
- `_mutationToMultipartMethod(def)` — multipart form upload
- `_subscriptionToMethod(def)` — async generator or Observable

Helpers to extract:
- `_serializePartialQuery(dq, hasFrags)`
- `_generateVariables(def, {nullifyUploads})`
- `_getMethodArgs(def)`
- `_resolveArgType(arg)`
- `_serializeInvalidation(def)`
- `_errorCheckStatement()`
- `_returnTypeName(def)`
- `_hasFullResponseSupport` (getter)

The `observables` flag must be passed at construction time (it changes method signatures
and return types throughout).

---

### A3. Refactor `TypeScriptClientSerializer`

- Add `late final TypeScriptClientOperationSerializer _opSer` initialised in constructor.
- `render*Method` delegates to `_opSer`.
- Remove all `_sv*` getters; import `typescript_client_vars.dart` instead.
- Keep monolithic `generateClient()` for test backward-compatibility (emits everything
  in one string as today).
- Add per-file generators (see A4).
- Add `generateClientOnlyFile()` for the lean `GraphLinkClient` class.

---

### A4. Extract TypeScript infrastructure to separate generated files

Each constant in `typescript_client_constants.dart` maps to one generated `.ts` file.
Types that are currently private (`_` prefix) become public when moved to their own file.

| Generated file | Source constant | Renames |
|---|---|---|
| `graph-link-cache-store.ts` | `tsCacheStore` | none (already public) |
| `graph-link-in-memory-cache-store.ts` | split from `tsCacheStore` | none |
| `graph-link-cache-entry.ts` | split from `tsCacheInfra` | `_GraphLinkCacheEntry` → `GraphLinkCacheEntry` |
| `graph-link-tag-entry.ts` | split from `tsCacheInfra` | `_GraphLinkTagEntry` → `GraphLinkTagEntry` |
| `graph-link-lock.ts` | split from `tsCacheInfra` | `_Lock` → `GraphLinkLock` |
| `graph-link-partial-query.ts` | split from `tsCacheInfra` | `_GraphLinkPartialQuery` → `GraphLinkPartialQuery` |
| `graph-link-ws-adapter.ts` | `tsWsAdapter` | none (already public) |
| `graph-link-ws-message-types.ts` | `tsWsMessageTypes` | none |
| `graph-link-subscription-handler.ts` | `tsSubscriptionHandler` | `_SubscriptionHandler` → `GraphLinkSubscriptionHandler` |
| `graph-link-default-ws-adapter.ts` | `tsDefaultWsAdapter` | none |
| `graph-link-uploads.ts` | `tsUploadsFile` | none |
| `graph-link-resolver-base.ts` | `_ResolverBase` in serializer | `_ResolverBase` → `GraphLinkResolverBase` |
| `graph-link-queries.ts` | `GraphLinkQueries` class | none |
| `graph-link-mutations.ts` | `GraphLinkMutations` class | none |
| `graph-link-subscriptions.ts` | `GraphLinkSubscriptions` class | none |
| `graph-link-client.ts` | `GraphLinkClient` class only | none |
| `graph-link-adapters.ts` | fetch/axios adapters | none (already separate) |

`tsCacheInfra` needs to be split into 4 separate constants in
`typescript_client_constants.dart` before new file generators can be added.

The `__GL_TAG_KEY_PREFIX__` TS constant lives in `graph-link-resolver-base.ts` (shared
by resolver base and tag entry).

---

### A5. Update `typescript_client_generator.dart`

Replace the single `generateClient()` call with calls to the per-file generators, emitting
each file to `client/` with its own imports. Mirror the structure of
`dart_client_generator.dart` after the Dart refactor.

Import graph between generated files:
```
graph-link-client.ts
  ├── graph-link-resolver-base.ts
  │     ├── graph-link-cache-entry.ts
  │     ├── graph-link-lock.ts
  │     ├── graph-link-tag-entry.ts
  │     ├── graph-link-partial-query.ts
  │     └── graph-link-cache-store.ts
  ├── graph-link-queries.ts  →  resolver-base + cache infra
  ├── graph-link-mutations.ts  →  resolver-base [+ uploads + upload-converter]
  └── graph-link-subscriptions.ts
        ├── graph-link-subscription-handler.ts
        │     ├── graph-link-ws-adapter.ts
        │     ├── graph-link-ws-message-types.ts
        │     └── graph-link-lock.ts  (for synchronized)
        └── graph-link-ws-adapter.ts
```

---

## Task B — Java: replace `safeLocalVar` with const strings

`JavaClientContext` initialises ~20 `sv*` fields by calling
`codeGenUtils.safeLocalVar(name)` at construction time. This should be replaced with
top-level `const` strings in a new file `java_client_vars.dart`, using the same
`__gl_${name}__` pattern currently produced by `JavaCodeGenUtils.safeLocalVar`.

Steps:
1. Create `lib/src/serializers/client_serializers/java_client_vars.dart` with one
   `const String sv* = '__gl_name__';` per variable.
2. Update `JavaClientContext` to assign fields from the consts instead of calling
   `codeGenUtils.safeLocalVar`.
3. Update `JavaClientSerializer`'s inline `_sv*` getters to use the consts directly.
4. Remove `JavaCodeGenUtils.safeLocalVar` once no callers remain.

---

## Task C — Kotlin: replace `safeLocalVar` with const strings

Same as Task B for Kotlin. `KotlinClientContext` has the same pattern.

Steps:
1. Create `lib/src/serializers/client_serializers/kotlin_client_vars.dart`.
2. Update `KotlinClientContext` to use the consts.
3. Remove `KotlinCodeGenUtils.safeLocalVar`.
