# Input Mapping Generation (`@glMapsTo` / `@glMapField`)

## Context

GraphLink generates Spring Boot service interfaces that users implement. A recurring pain point is manually mapping GraphQL input types to the entities/types they represent. This is pure boilerplate — the schema already encodes the structural relationship, GraphLink just doesn't exploit it yet.

This plan introduces two new directives:
- `@glMapsTo(type: "TargetType")` — declared on an input type, names the target type or input to map to
- `@glMapField(to: "targetFieldName")` — declared on an input field, explicitly aliases it to a differently-named field on the target

GraphLink generates two methods on the input class (Dart and Java):
- `toTargetType()` — instance method, converts the input to the target type
- `fromTargetType(TargetType t)` — static factory, builds the input from an existing target type instance

Both methods are generated on the **input** only. The target type class is never modified.

This feature is **opt-in**: it is only triggered when `@glMapsTo` is explicitly declared on an input. Auto-detection based on naming is intentionally not supported — explicit is better than implicit.

---

## Design

### Directives

```graphql
input CreateUserInput @glMapsTo(type: "User") {
  fname: String!  @glMapField(to: "firstName")
  email: String!
  password: String!   # not in User — becomes a required parameter
}

type User {
  id: ID!             # not in input — becomes a required parameter
  firstName: String!
  email: String!
  hashedPassword: String!  # not in input — becomes a required parameter
}
```

### Resolution algorithm

For each field on the **target** type:

| Source field found? | Nullability | Result |
|---|---|---|
| Yes (name or `@glMapField` alias) | same, or `String!` → `String?` | **auto-map** |
| Yes (name or `@glMapField` alias) | `String?` → `String!` | **`defaultFieldName` parameter** |
| No | — | **required parameter** |

Fields on the source input that have no counterpart on the target are simply ignored in the mapping method (they remain accessible as input fields).

### One input → one target

Multiple `@glMapsTo` on the same input is not supported. If you need one input shape to construct two different types, that is service logic.

### Target must be a type

`@glMapsTo` may only target declared `type` definitions (`grammar.types`). Targeting another `input` or a projected type is not allowed — input-to-input conversion is service logic, and projected types are internal auto-generated constructs that users never reference by name.

### Generated method name

`to{TargetType}()` — e.g. `toUser()`, `toAuditLog()`.

---

## Generated output

### Schema

```graphql
input CreateUserInput @glMapsTo(type: "User") {
  fname: String!  @glMapField(to: "firstName")
  email: String!
  role: String    # nullable in input, non-null in User → defaultRole param
}

type User {
  id: ID!
  firstName: String!
  email: String!
  role: String!
}
```

### Dart

```dart
// Input → Type
User toUser({
  required String id,          // missing in source
  required String defaultRole, // nullable → non-null mismatch
}) {
  return User(
    id: id,
    firstName: fname,           // @glMapField alias
    email: email,               // name match
    role: role ?? defaultRole,  // nullable → non-null: use default
  );
}

// Type → Input (static factory)
static CreateUserInput fromUser(User user) {
  return CreateUserInput(
    fname: user.firstName,  // @glMapField alias (reversed)
    email: user.email,
    // fields only on input (e.g. password) are omitted — caller sets them
  );
}
```

### Java

```java
// Input → Type
public User toUser(String id, String defaultRole) {
    return User.builder()
        .id(id)
        .firstName(getFname())          // @glMapField alias
        .email(getEmail())              // name match
        .role(role != null ? role : defaultRole) // nullable → non-null
        .build();
}

// Type → Input (static factory)
public static CreateUserInput fromUser(User user) {
    return new CreateUserInput(
        user.getFirstName(),  // @glMapField alias (reversed)
        user.getEmail()
        // fields only on input (e.g. password) are omitted — caller sets them
    );
}
```

---

## Step 1 — Register new directive constants

**File:** `lib/src/model/built_in_dirctive_definitions.dart`

Add:

```dart
/// Maps an input type to a target type or input, generating a toXxx() method.
const glMapsTo = "@glMapsTo";
const glMapsToType = "type";

/// Aliases an input field to a differently-named field on the mapping target.
const glMapField = "@glMapField";
const glMapFieldTo = "to";
```

---

## Step 2 — Add helpers to `GLInputDefinition`

**File:** `lib/src/model/gl_input_definition.dart`

Add a getter that reads the `@glMapsTo` directive:

```dart
/// Returns the target type name from @glMapsTo, or null if not declared.
String? get mapsToType =>
    getDirectiveByName(glMapsTo)?.getArgValueAsString(glMapsToType);
```

---

## Step 3 — Add helper to `GLField`

**File:** `lib/src/model/gl_field.dart`

Add a getter that reads the `@glMapField` directive:

```dart
/// Returns the target field name from @glMapField, or null if not declared.
String? get mapFieldTo =>
    getDirectiveByName(glMapField)?.getArgValueAsString(glMapFieldTo);
```

---

## Step 4 — Add validation

**File:** `lib/src/gl_validation_extension.dart`

After existing input validation, add a pass over all inputs that declare `@glMapsTo`:

1. Resolve the target name against `grammar.types` only (inputs and projectedTypes are not valid targets).
2. If not found → `ParseException("@glMapsTo target '${input.mapsToType}' does not exist or is not a type")`.
3. For each field on the input with `@glMapField(to: X)`, check that a field named `X` exists on the target → `ParseException` if not.
4. Warn (or throw) if the resulting mapping has **zero** auto-mapped fields — the directive adds no value in that case (optional strictness, can be a warning).

---

## Step 5 — Implement the mapping resolution algorithm

**File:** `lib/src/serializers/gl_serializer.dart` (or a new `mapping_resolver.dart`)

Create a pure helper class/function `InputMappingResolver` that encodes the algorithm independently of language. Takes `GLInputDefinition source` and `GLTokenWithFields target` (could be a type or input), returns a `MappingPlan`:

```dart
class MappedField {
  final GLField targetField;
  final GLField? sourceField;   // null → required param (missing in source)
  // isNullabilityMismatch: computed as sourceField.type.nullable && !targetField.type.nullable
  // sourceAccessor: computed as sourceField?.name.token ?? targetField.name.token
}

class MappingPlan {
  final List<MappedField> autoMapped;
  final List<MappedField> defaultParams;   // nullability mismatch
  final List<MappedField> requiredParams;  // missing in source
}
```

Resolution logic per **target** field:
1. Find source field where `sourceField.mapFieldTo == targetField.name` → alias match
2. Else find source field where `sourceField.name == targetField.name` → name match
3. If found and `sourceField.type.nullable && !targetField.type.nullable` → `defaultParams`
4. If found and types otherwise compatible → `autoMapped`
5. If not found → `requiredParams`

### Nested mapped input list rule

When a source field is a list whose element type is itself a mapped input (`@glMapsTo`), auto-mapping via `.map((e) => e.toXxx()).toList()` is only valid if `toXxx()` can be called with **zero arguments** — i.e., the nested input's `MappingPlan` has no `requiredParams` and no `defaultParams`.

If the nested `toXxx()` requires any parameters, the field is **promoted to `requiredParams`** in the parent plan. The caller receives `required List<TargetType> fieldName` and is responsible for the conversion.

This rule applies to `toXxx()` only. For `fromXxx()`, nested `fromXxx()` calls always have optional default parameters (`= const []`), so the lambda can always call them with zero extra arguments.

### List copy rule

For list fields with the same element type (scalars, enums, or compatible types), the generated code always copies the list via `.toList()` rather than assigning the reference directly. Nullable source uses `?.toList()`.

### `fromXxx()` nullable list default parameter rule

When a target type field is a nullable list (`[T!]?`) but the corresponding input field is non-null (`[T!]!`), `fromXxx()` cannot guarantee a non-null value from the target instance. In this case:
- A named optional parameter `List<T> defaultFieldName = const []` is added to `fromXxx()`
- The assignment uses `targetInstance.field?.toList() ?? defaultFieldName`

This mirrors how `toXxx()` handles nullable→non-null scalar mismatches with `required defaultFieldName` params, but uses an optional parameter with `const []` as the default since an empty list is always a safe fallback for collections.

---

## Step 6 — Generate mapping method in `DartSerializer`

**File:** `lib/src/serializers/dart_serializer.dart`

In `doSerializeInputDefinition`, after the existing class body, check `def.mapsToType`. If set, resolve the target via `grammar`, build a `MappingPlan`, then generate:

```dart
String _generateDartMappingMethod(GLInputDefinition def, MappingPlan plan, String targetType) {
  // named parameters: defaultXxx (required) for mismatch, plain name (required) for missing
  final params = [
    ...plan.defaultParams.map((f) => 'required ${serializeType(f.targetField.type, false)} default${f.targetField.name.firstUp}'),
    ...plan.requiredParams.map((f) => 'required ${serializeType(f.targetField.type, false)} ${f.targetField.name}'),
  ];

  final assignments = [
    ...plan.autoMapped.map((f) => '${f.targetField.name}: ${f.sourceAccessor}'),
    ...plan.defaultParams.map((f) => '${f.targetField.name}: ${f.sourceAccessor} ?? default${f.targetField.name.firstUp}'),
    ...plan.requiredParams.map((f) => '${f.targetField.name}: ${f.targetField.name}'),
  ];

  return codeGenUtils.createMethod(
    returnType: targetType,
    methodName: 'to${targetType.firstUp}',
    namedArguments: true,
    arguments: params,
    statements: ['return $targetType(${assignments.join(', ')});'],
  );
}
```

Append the method inside the input class statements.

---

## Step 7 — Generate mapping method in `JavaSerializer`

**File:** `lib/src/serializers/java_serializer.dart`

In `doSerializeInputDefinition`, after existing statements, check `def.mapsToType`. If set, resolve and generate:

```dart
String _generateJavaMappingMethod(GLInputDefinition def, MappingPlan plan, String targetType) {
  final params = [
    ...plan.requiredParams.map((f) => '${serializeType(f.targetField.type, false)} ${f.targetField.name}'),
    ...plan.defaultParams.map((f) => '${serializeType(f.targetField.type, false)} default${f.targetField.name.firstUp}'),
  ];

  final builderCalls = [
    ...plan.autoMapped.map((f) => '.${f.targetField.name}(${_getterCall(f.sourceAccessor)})'),
    ...plan.defaultParams.map((f) => '.${f.targetField.name}(${f.sourceAccessor} != null ? ${_getterCall(f.sourceAccessor)} : default${f.targetField.name.firstUp})'),
    ...plan.requiredParams.map((f) => '.${f.targetField.name}(${f.targetField.name})'),
  ];

  return codeGenUtils.createMethod(
    returnType: 'public $targetType',
    methodName: 'to${targetType.firstUp}',
    arguments: params,
    statements: [
      'return $targetType.builder()',
      ...builderCalls,
      '.build();'
    ],
  );
}
```

Add the method to the input class statements list.

---

## Step 8 — Handle target resolution

Both Step 6 and Step 7 need to resolve the target name to a `GLTypeDefinition`. Lookup is `grammar.types[targetName]` only — inputs and projected types are not valid targets.

This is already guaranteed by Step 4 validation, so by generation time the target is always a `GLTypeDefinition`. Extract a small helper `_resolveTarget(String name)` in `GLSerializer` base or directly in each serializer.

---

## Step 9 — Generate `fromTargetType()` static factory in `DartSerializer` and `JavaSerializer`

**Files:** `lib/src/serializers/dart_serializer.dart`, `lib/src/serializers/java_serializer.dart`

After generating `toTargetType()`, generate the reverse static factory. Only fields that exist on **both** the input and the target are mapped (fields exclusive to the input, like `password`, are silently skipped — the caller is responsible for filling them in).

`@glMapField` aliases are reversed: if `fname` maps to `firstName`, then `fromUser` reads `user.firstName` and assigns to `fname`.

Fields on the target that have no counterpart in the input are simply ignored.

---

## Step 11 — Skip `@glMapsTo` and `@glMapField` from decorator output

**File:** `lib/src/serializers/gl_serializer.dart`

`serializeDecorators` must skip `@glMapsTo` and `@glMapField` — these are GraphLink-internal directives and must not appear in the generated code as annotations.

Add both to the existing set of filtered directives (alongside `@glSkipOnServer`, `@glSkipOnClient`, etc.).

---

## Execution Order

| Step | File | Depends On |
|---|---|---|
| 1 — constants | `built_in_dirctive_definitions.dart` | — |
| 2 — `GLInputDefinition.mapsToType` | `gl_input_definition.dart` | 1 |
| 3 — `GLField.mapFieldTo` | `gl_field.dart` | 1 |
| 4 — validation | `gl_validation_extension.dart` | 1, 2, 3 |
| 5 — `MappingPlan` resolver | `mapping_resolver.dart` | 2, 3 |
| 6 — Dart `toTargetType()` | `dart_serializer.dart` | 4, 5 |
| 7 — Java `toTargetType()` | `java_serializer.dart` | 4, 5 |
| 8 — target resolution helper | `gl_serializer.dart` | 1 |
| 9 — Dart & Java `fromTargetType()` static factory | `dart_serializer.dart`, `java_serializer.dart` | 6, 7 |
| 11 — filter directives from output | `gl_serializer.dart` | 1 |
