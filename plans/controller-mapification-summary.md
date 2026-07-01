# Controller Layer Map-ification — Implementation Summary

## What this feature does

Controllers now return `Map`/`List<Map>` (from `toJson()`) instead of typed objects.
**Service layer is untouched** — it still returns typed objects. Always-on, no config
flag. Applies to all server targets: Java Spring, Kotlin Spring, Express/Apollo TS.

## Type mapping rules

| GraphQL type | Controller returns |
|---|---|
| Custom type / interface / input | `Map<String, Object>` (Java) / `Map<String, Any?>` (Kotlin) / `Record<string, unknown>` (TS) |
| Enum | `String` |
| Scalar (Int, String, Boolean, Float, ID) | unchanged (pass-through) |
| List of projectable | `List<Map<...>>` (recursive) |
| List of scalar | `List<String>` etc. (unchanged) |

## What was done

### `lib/src/serializers/java_spring_controller_serializer.dart`

**Added helpers:**
- `_mapifyType(GLType, GLToken)` — converts GLType → map-ified Java type string.
  Returns `Map<String, Object>` for projectable types, `String` for enums, recurses
  into `GLListType`. Imports `JavaImports.map` as needed.
- `_wrapWithToJson(GLType, String, GLToken, [int depth])` — wraps expression with
  `.toJson()` calls. Uses `JavaCodeGenUtils.safeCall` (null-safe ternary `x == null ?
  null : x.toJson()`) and `JavaCodeGenUtils.streamMapCollect` (`.stream().map().collect()`).
  Returns expression unchanged for scalars.

**Modified `serializehandlerMethod`:**
- Subscription: `Flux<mapified>` return type, body `.map(__gl_result__ -> toJsonExpr)`.
  Skips `.map()` when toJsonExpr == resultVar (scalar case — no-op otherwise).
- Reactive: Mono for single types, Flux for GLListType. Service call wrapped via
  `.map(resultVar -> toJsonExpr)`. Handles validation chaining via `.then()`.
- Non-reactive (CompletableFuture): Uses temp var for nullable types to avoid
  double-evaluation of the service call. `innerStatements` list with optional temp var
  declaration before the toJson expression.

**Modified `serializeMappingMethod`:**
- Added `mapping.isBatch` guard: batch mappings skip body wrapping (they return
  `Map<K,V>`, not the bare field type — calling `.stream()` on a Map is wrong).
- Non-batch: nullable types use temp var pattern to avoid double-evaluation.

**Split return type computation:**
- `_getReturnType` — restored original, used for service headers (NOT mapified).
- `_getControllerReturnType` — new, mapified version used for controller headers only.

### `lib/src/serializers/kotlin_spring_controller_serializer.dart`

**Added helpers:**
- `_mapifyType(GLType)` — returns `Map<String, Any?>` for projectable, `String` for
  enums, recurses into lists. No context param (Kotlin has no explicit import for
  Map/String).
- `_wrapWithToJson(GLType, String, [int depth])` — uses `KotlinCodeGenUtils.safeCall`
  and `KotlinCodeGenUtils.mapCall`.

**Modified `serializehandlerMethod`:**
- Subscription: `Flow<mapified>`. Body: `.map { __gl_result__ -> toJsonExpr }`.
- Suspend fun: service call wrapped with `_wrapWithToJson`, passed through `_wrapBody`.

**Split return type computation:**
- `_serializeReturnType` — restored original, used for service declarations.
- `_serializeControllerReturnType` — new, mapified, used for controller headers.
- `_getReturnType` — restored original (service mapping headers).
- `_getControllerReturnType` — new, mapified (controller mapping headers).

**Modified `serializeMappingMethod`:**
- Added `mapping.isBatch` guard — same fix as Java: batch mappings return `Map<K,V>`
  and skip body wrapping.

### `lib/src/serializers/express_apollo_server_serializer.dart`

**Added:** `import 'package:graphlink/src/gl_validation_extension.dart'` (needed for
`isEnum` / `isProjectableType`).

**Added:** `returnType: GLType` field to `_RootEntry` class.

**Modified `_writeRootBlock`:**
- Populated `returnType: field.type` in `_RootEntry`.
- Wraps `$serviceCall` with `.then((_r) => callToJson('_r', e.returnType))` when the
  type needs mapification (list, enum, or projectable). Skips `.then()` for scalars.

**Modified `_writeSubscriptionBlock`:**
- Populated `returnType`; changed resolve from `payload` to
  `callToJson('payload', e.returnType)`.

**Modified `_writeTypeMappings`:**
- Regular: `.then((_r) => callToJson('_r', m.field.type))`.
- Batch (DataLoader): `.load(parent).then((_r) => callToJson('_r', m.field.type))`.
- Identity/forwarded/forbid unchanged. Service interfaces unchanged.

### `jvm_spring_controller_serializer_base.dart`
No structural changes. `getServiceReturnType` and `createListTypeOnSubscription`
remain — they resolve the service's typed return type, which `_mapifyType` then converts.

## What does NOT change

- Service interfaces — stay typed.
- Type/input/enum serializers — `toJson`/`fromJson` already exist.
- Config — no new flags, always-on.
- Identity/forwarded/forbid mappings — no service layer involved, unchanged.

## Bugs found and fixed during implementation

1. **Nullable type double-evaluation:** `safeCall('userService.getUser()', 'toJson()',
   true)` called the service twice (once for the null check, once for the actual call).
   Fixed by emitting a temp variable assignment for nullable types before the null-safe
   toJson expression.

2. **Shared return type methods:** `_getReturnType` / `_serializeReturnType` were called
   by both controller and service header generation. Split into two: original
   (un-mapified) for service, new mapified version for controller. Applied to both Java
   and Kotlin.

3. **Reactive always used Mono:** Lists in reactive mode should use `Flux<T>`, but my
   code always produced `Mono<T>`. Fixed with `is GLListType` check.

4. **No-op `.map(x -> x)` for scalars:** For scalar types, unnecessary `.map()` was
   emitted. Fixed by checking `toJsonExpr == resultVar` and skipping `.map()`.

5. **Batch mapping `.stream()` on Map:** Batch mappings return `Map<K,V>` from the
   service, but `_wrapWithToJson` was treating the field type as the return type and
   calling `.stream()` on the Map. Fixed with `mapping.isBatch` guard in both Java and
   Kotlin — batch bodies pass through unchanged.

6. **Express missing import:** `isEnum` and `isProjectableType` not available. Fixed by
   adding import of `gl_validation_extension.dart`.

## Tests updated

All affected tests updated with mapified return types and toJson body expectations:
- `test/serializers/java/backend/spring_server_serializer_test.dart`
- `test/serializers/java/backend/spring_server_serializer_reactive_test.dart`
- `test/serializers/java/backend/gl_validate_test.dart`
- `test/upload/upload_spring_serializer_test.dart`
- `test/batch_mappging/batch_mappging_test.dart`
- `test/batch_mappging/schema_mapping_with_args_test.dart`
- `test/serializers/java/annotations/type_serialization_annotations_test.dart`

**All 356 tests pass** across the affected test suites.

## Remaining work (NOT done)

- **Express server tests** (`test/server/`) — need to be updated and run.
- **Server integration tests** (`server_integration_tests/`) — regenerate servers and
  run `make ci` to validate generated code works end-to-end.
- **Examples** — regenerate all server examples and verify they compile.
- **Kotlin tests** — verify Kotlin-specific tests pass.
