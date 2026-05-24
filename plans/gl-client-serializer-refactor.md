# Plan: GLClientSerializer Refactor

## Goal

Move schema-level decisions and operation-iteration logic into `GLClientSerializer` so that
adding a new target language requires only implementing syntax rendering, not re-deriving
schema facts that every language needs identically.

---

## What Changes

### 1. Concrete helpers on `GLClientSerializer` (schema-level decisions)

These are currently duplicated across all three concrete serializers. They query the parser —
no target-language knowledge needed.

| Method | Returns | Currently duplicated in |
|---|---|---|
| `getOperationsForType(GLQueryType)` | `List<GLQueryDefinition>` | all three |
| `getInvalidationInfo(GLQueryDefinition)` | `({bool invalidateAll, Set<String> tags})` | all three |
| `hasFragments(GLQueryDefinition)` | `bool` | all three |
| `getFragmentsForDef(GLQueryDefinition)` | `List<GLFragmentDefinition>` | all three |
| `isUploadMutation(GLQueryDefinition)` | `bool` | all three |
| `getUploadArgs(GLQueryDefinition)` | `List<GLFieldArgument>` | all three |
| `serializeQueryString(GLQueryDefinition)` | `String` | all three (via gqlSerializer) |
| `divideQuery(GLQueryDefinition)` | `List<DividedQuery>` | all three (via gqlSerializer) |

Also add a `protected late final GLGraphqSerializer gqlSerializer` field initialized in the
base constructor — all three create one themselves today.

### 2. Abstract methods for operation-level rendering

The base provides the iteration algorithm; subclasses provide the syntax.

```dart
// Called by the base for each query operation
String renderQueryMethod(GLQueryDefinition def);

// Called by the base for each mutation (non-upload)
String renderMutationMethod(GLQueryDefinition def);

// Called by the base for each upload mutation
String renderUploadMutationMethod(GLQueryDefinition def);

// Called by the base for each subscription
String renderSubscriptionMethod(GLQueryDefinition def);
```

The base gets a concrete `buildOperationMethods(GLQueryType type)` that calls the right
`render*` method per operation — today all three reimplement this dispatch loop.

### 3. `generateUploadsFile()` becomes abstract

Consistent across all three languages (each generates exactly one uploads file).
Makes it a compiler-enforced contract for new language implementors.

```dart
GLClassModel generateUploadsFile();
```

---

## What Does NOT Change

- `generateClient()` stays abstract — file layout and infrastructure bundling is too
  different between languages (Dart/TS inline everything; Java splits into many files).
- No abstract methods for cache infrastructure (`generateResolverBase`,
  `generateCacheInfrastructure`) — Java generates them as separate files, Dart/TS inline
  them; a shared signature would be a lie.
- No abstract method for `InMemoryGraphLinkCacheStore` — same reason, plus it's just a
  static string constant with no generation logic.
- `LanguageClientGenerator` (generator-level base class) — not needed; the value is here
  in the serializer layer.

---

## Files Affected

| File | Change |
|---|---|
| `lib/src/serializers/gl_client_serializer.dart` | Add concrete helpers + abstract render methods + gqlSerializer field |
| `lib/src/serializers/client_serializers/dart_client_serializer.dart` | Implement abstract render methods; remove duplicated helpers |
| `lib/src/serializers/client_serializers/typescript_client_serializer.dart` | Same |
| `lib/src/serializers/client_serializers/java_client_serializer.dart` | Same |
| `lib/src/serializers/client_serializers/java_client_operation_serializer.dart` | May need to expose render methods up to the serializer |

---

## What a New Language Implementor Needs to Write

After this refactor, adding Go (or any other language) requires:

1. Extend `GLSerializer` — type serialization (enums, inputs, projected types)
2. Extend `GLClientSerializer` — implement the four `render*` methods + `generateClient()` + `generateUploadsFile()`
3. Write a generator function (like the existing three) that calls `writeToFile` for each output

The schema parsing, operation filtering, fragment resolution, cache-tag decisions, upload-arg
detection — all inherited.
