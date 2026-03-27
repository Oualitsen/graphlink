# Field Arguments Enforcement & Mapping Generation

## Context

GraphLink parses GraphQL schemas and generates Spring Boot Java code (controllers, services, batch/schema mappings).

A non-root type field with arguments (e.g. `cars(filter: String): [Car!]!`) always requires a dedicated resolver — it can never be a simple property fetch. Currently:
- No validation enforces that such fields have `@glSkipOnServer`
- When generating batch/schema mappings, field arguments are ignored — the resolver only receives the parent object (`value`), never the field's filter arguments
- `cars(): [Car!]!` (empty argument list) is silently treated the same as `cars: [Car!]!`

## Goals

1. Make `GLField.arguments` presence-aware (`null` vs `[]` vs `[...]`)
2. Forbid empty argument lists with a `ParseException`
3. Enforce that non-root type fields with arguments must have `@glSkipOnServer`
4. Pass field arguments through to generated batch/schema mapping method signatures

---

## Step 1 — Make `GLField.arguments` presence-aware

**File:** `lib/src/model/gl_field.dart`

Add a private `_hasExplicitArgumentList` boolean to record whether parentheses were written in the source. Change the constructor parameter `arguments` from `List<GLArgumentDefinition>` to `List<GLArgumentDefinition>?`:
- `null` → no parentheses written (`cars: [Car!]!`)
- `[]` → parentheses written but empty (`cars(): [Car!]!`)
- `[...]` → parentheses with arguments (`cars(filter: String): [Car!]!`)

Change the public getter return type to `List<GLArgumentDefinition>?` — return `null` when `_hasExplicitArgumentList` is false, otherwise `_arguments.values.toList()`.

Update `checkMerge` to handle nullable: use `(arguments ?? []).length` for length comparisons.

---

## Step 2 — Remove `?? []` coercion in the grammar parser

**File:** `lib/src/gl_grammar.dart`

In the `field()` method, change:
```dart
arguments: fieldArguments ?? [],
```
to:
```dart
arguments: fieldArguments,
```

When `acceptsArguments` is true but no `()` is written, `fieldArguments` is `null` from `.optional()` — this now flows through to the model correctly. When `acceptsArguments` is false (input fields), `fieldArguments` is `null` unconditionally — also correct.

---

## Step 3 — Fix all call sites

**Files:** `gl_grammar_extension.dart`, `gl_token_with_fields.dart`, `gl_service.dart`, `java_serializer.dart`, `spring_server_serializer.dart`, `graphq_serializer.dart`, `flutter_type_widget_serializer.dart`

Every existing `field.arguments` access now receives `List<GLArgumentDefinition>?`. Update all call sites to `field.arguments ?? []` except where the nullable value is needed for validation logic (Steps 4 and 5).

---

## Step 4 — Validate empty argument lists

**File:** `lib/src/gl_validation_extension.dart`
**Where:** `_validateTypeRef`, inside the `for (var field in def.fields)` loop

```dart
if (field.arguments != null && field.arguments!.isEmpty) {
  throw ParseException(
    "Field '${field.name}' has an empty argument list — either add arguments or remove the parentheses",
    info: field.name,
  );
}
```

Fires only when `()` was explicitly written with nothing inside.

---

## Step 5 — Validate arguments require `@glSkipOnServer`

**File:** `lib/src/gl_validation_extension.dart`
**Where:** `_validateTypeRef`, same field loop, after Step 4 check

```dart
if (field.arguments != null && field.arguments!.isNotEmpty) {
  final isRootType = GLQueryType.values
      .map((t) => schema.getByQueryType(t))
      .contains(def.token);
  if (!isRootType && field.getDirectiveByName(glSkipOnServer) == null) {
    throw ParseException(
      "Field '${field.name}' has arguments but is missing @glSkipOnServer — add @glSkipOnServer or remove the arguments",
      info: field.name,
    );
  }
}
```

Root types (Query/Mutation/Subscription) are excluded — their fields go through controllers which already handle arguments correctly.

---

## Step 6 — Append field arguments in `_getMappingArgument`

**File:** `lib/src/serializers/spring_server_serializer.dart`

Add a `bool skipAnnotation` parameter (defaulting to `false`). After building the base `value` parameter string, serialize `mapping.field.arguments` and append them:

- `skipAnnotation: false` (controller) → prefix each arg with `@Argument`, add `SpringImports.gqlArgument` import to context
- `skipAnnotation: true` (service interface) → emit bare `Type name`

Expected output for `cars(filter: String): [Car!]! @glSkipOnServer` on type `Person`:

**Controller (BatchMapping):**
```java
@BatchMapping(typeName="Person", field="cars")
public Map<Person, List<Car>> personCars(List<Person> value, @Argument String filter) {
    return service.personCars(value, filter);
}
```

**Service interface:**
```java
Map<Person, List<Car>> personCars(List<Person> value, String filter);
```

---

## Step 7 — Thread `skipAnnotation` through `serializeMappingImplMethodHeader`

**File:** `lib/src/serializers/spring_server_serializer.dart`

`serializeMappingImplMethodHeader` already has `skipAnnotation` as a parameter. Pass it down to `_getMappingArgument`:

```dart
buffer.write("${_getReturnType(mapping, context)} ${mapping.key}(${_getMappingArgument(mapping, context, skipAnnotation: skipAnnotation)}");
```

---

## Step 8 — Forward argument names in the service call

**File:** `lib/src/serializers/spring_server_serializer.dart`
**Where:** `serializeMappingMethod`, around the `return serviceInstance...` statement

Extend the statement to forward field argument names after `value`:

```dart
final statement = StringBuffer('return $serviceInstanceName.${mapping.key}(value');
var fieldArgs = mapping.field.arguments ?? [];
if (fieldArgs.isNotEmpty) {
  statement.write(', ');
  statement.write(fieldArgs.map((a) => a.tokenInfo.token).join(', '));
}
if (injectDataFetching) {
  statement.write(', dataFetchingEnvironment');
}
statement.write(');');
```

---

## Step 9 — Verify `serializeIdentityMapping` needs no changes

Identity mappings are simple pass-throughs (receive `value`, return `value`). They don't involve filter arguments. Confirm and leave untouched.

---

## Execution Order

| Step | File | Depends On |
|------|------|-----------|
| 1 — nullable `GLField.arguments` | `gl_field.dart` | — |
| 2 — remove `?? []` in grammar | `gl_grammar.dart` | 1 |
| 3 — fix all call sites | multiple | 1, 2 |
| 4 — empty args validation | `gl_validation_extension.dart` | 1, 2 |
| 5 — requires `@glSkipOnServer` validation | `gl_validation_extension.dart` | 1, 2 |
| 6 — `_getMappingArgument` with args | `spring_server_serializer.dart` | 3 |
| 7 — thread `skipAnnotation` | `spring_server_serializer.dart` | 6 |
| 8 — forward args in service call | `spring_server_serializer.dart` | 6 |
| 9 — verify identity mapping | `spring_server_serializer.dart` | — |
