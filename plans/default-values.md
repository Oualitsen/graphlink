# Default Values — Implementation Plan

## Goal

Support GraphQL default values (`= value`) on input fields, type field arguments, and
operation variables, across all 4 client languages (Dart, Kotlin, TypeScript, Java)
in both client and server mode.

---

## What already works

- Parser already captures `initialValue` (`Object?`) on `GLField` and
  `GLArgumentDefinition` for all contexts (input fields, type field arguments, operation
  variables). Value types: `int`, `double`, `bool`, `null`, `String` (with surrounding
  quotes for string literals, bare for enum identifiers), `List<Object?>`, `Map<String,
  Object?>`.
- `serializeArgumentDefinition` in `gl_graphql_serializer.dart` already emits `= value`
  for argument defaults (field args, directive args, operation variables).
- `serializeField` in `gl_graphql_serializer.dart` now emits `= value` for input field
  defaults (fixed as step 0).

---

## Key constraints

- **Both modes.** Default value literals are emitted in both client and server codegen.
- **Do not mutate `type.nullable` on the core model.** `gl_graphql_serializer` reads
  `type.nullable` directly to build `__gl_query__` strings and schema SDL. Mutating it
  would corrupt the type declarations sent to the server (e.g. `Role!` → `Role`).
- **Do not change `toJson()`.** It always includes all fields, even null ones. Default
  values must therefore be baked into the generated constructor/method signature
  client-side — not relied upon via server-side default application.
- **Preserve nullability as-is.** A field's GraphQL nullability is emitted verbatim in
  all languages. Default values are additive — they only add `= literal` to the
  constructor/method parameter. A non-null field with a default stays non-null in the
  generated type; we do NOT widen it to nullable.
- **No `isOptionalInCodegen`.** The getter has been removed from `GLField`. Dart uses
  an inline check to drop `required`; all other languages use `field.type.nullable` and
  `field.initialValue != null` directly.

---

## Per-language default literal helper

Each language serializer needs a private helper:

```
_defaultLiteral(GLType type, Object? value) → String
```

Converts the raw parsed `initialValue` to a target-language literal expression.

| Value type | Dart | Kotlin | TypeScript | Java |
|---|---|---|---|---|
| `int` | `18` | `18` | `18` | `18` |
| `double` | `4.5` | `4.5` | `4.5` | `4.5` |
| `bool` | `true` / `false` | `true` / `false` | `true` / `false` | `true` / `false` |
| `String` (quoted, e.g. `"anonymous"`) | `'anonymous'` | `"anonymous"` | `"anonymous"` | `"anonymous"` |
| `String` (identifier/enum, e.g. `USER`) | `Role.user` | `Role.USER` | `Role.USER` | `Role.USER` |
| `List<Object?>` | `['dart', 'graphql']` | `listOf("dart", "graphql")` | `['dart', 'graphql']` | `List.of(...)` |
| `null` | `null` | `null` | `null` | `null` |

Enum identifiers are distinguished from quoted strings by checking whether the GLType
resolves to a known enum in `parser.enums` — if yes, format as enum reference; if no,
strip the surrounding quotes and format as a string literal.

---

## Steps

### Step 0 — SDL serialization ✅ DONE
`serializeField` now emits `= value` for input fields with defaults. Foundation for
everything else. Branch: `fix/graphql-field-default-value-serialization`.

---

### Step 1 — Core model getter ✅ DONE
`isOptionalInCodegen` has been removed from `GLField`. The inline expression
`!field.type.nullable && (mode != CodeGenerationMode.client || field.initialValue == null)`
is used directly in Dart serializer to decide whether `required` is emitted.
All other serializers use `field.type.nullable` and `field.initialValue != null` directly.

---

### Step 2 — Dart input type defaults
**File:** `lib/src/serializers/dart_serializer.dart`

- `isOptionalInCodegen` is already used correctly at line 326 to drop `required`.
- Add `serializeDefaultLiteral(GLType, Object?)` helper (or confirm it exists).
- Constructor params for fields with defaults emit the literal: `this.priority = Priority.MEDIUM`.
- Type nullability is unchanged — a `Priority!` field stays `Priority`, not `Priority?`.

**Test schema must include a non-null field with a default** (e.g. `priority: Priority! = MEDIUM`)
to verify non-null is preserved. Assert:
```dart
required this.title,           // non-null, no default → required
this.priority = Priority.MEDIUM, // non-null, has default → not required, not nullable
Priority? score,               // nullable, no default → not required, nullable, no literal
this.done = false,             // nullable, has default → not required, literal
```

---

### Step 3 — Kotlin input type defaults
**File:** `lib/src/serializers/kotlin_serializer.dart`

- Do NOT use `isOptionalInCodegen`. It must not widen non-null to nullable.
- If `f.initialValue != null`: emit `= serializeDefaultLiteral(...)` after the type.
- Type nullability comes only from `f.type.nullable`.
- Result: `priority: Priority = Priority.MEDIUM` (non-null field with default stays `Priority`)
  vs `score: Int? = 10` (nullable field with default stays `Int?`).

**Test schema must include a non-null field with a default.** Assert:
```kotlin
val title: String,                       // non-null, no default
val priority: Priority = Priority.MEDIUM, // non-null, has default — NOT Priority?
val score: Int? = 10,                    // nullable, has default
val done: Boolean? = false,
val label: String? = "untitled"
```

---

### Step 4 — TypeScript input type defaults
**File:** `lib/src/serializers/typescript_serializer.dart`

- Do NOT use `isOptionalInCodegen` to add `?`. The `?` modifier comes only from
  `type.nullable` (or `optionalNullableInputFields` config).
- Fields with `initialValue` still populate the companion const alongside the interface.
- A non-null field `priority: Priority! = MEDIUM` → interface field `priority: Priority`
  (no `?`), companion const `priority: Priority.MEDIUM`.

**Test schema must include a non-null field with a default.** Assert:
```typescript
title: string;          // no ?
priority: Priority;     // non-null with default — NO ?
score?: number;         // nullable with default → ?
// companion const:
export const defaultCreateTaskInput: Partial<CreateTaskInput> = {
  priority: Priority.MEDIUM,
  score: 10,
  ...
};
```

---

### Step 5 — Java input type defaults
**File:** `lib/src/serializers/java_serializer.dart`

- `isOptionalInCodegen` is not used for nullability here — Java field types are already
  emitted directly from `field.type`.
- If `initialValue != null`: emit `= serializeDefaultLiteral(...)` as a field initializer.
- Java has no `required` concept — no change to method signatures.

**Test schema must include a non-null field with a default.** Assert:
```java
private String title;                   // no initializer
private Priority priority = Priority.MEDIUM;  // non-null, default
private Integer score = 10;            // nullable mapped to boxed type, default
private Boolean done = false;
private String label = "untitled";
```

---

### Step 6 — Operation variable defaults (Dart, Kotlin, TypeScript)
**Files:** `dart_client_serializer.dart`, `kotlin_client_serializer.dart`,
`typescript_client_serializer.dart`

Generated operation method signatures use optional params with literal defaults.
Nullability of variables follows the same rule: preserve as-is, only add `= literal`.

```dart
// Dart — non-null var with default: not required, not nullable
Future<User> createUser({required String name, Role role = Role.user, int? age = 18})

// Kotlin — non-null var with default stays non-null
suspend fun createUser(name: String, role: Role = Role.USER, age: Int? = 18)

// TypeScript — non-null var with default stays non-null
createUser(name: string, role: Role = Role.USER, age?: number)
```

Also fix `serializeArgumentDefinition` in `gl_graphql_serializer` for string-typed
variable defaults (strip surrounding quotes and re-emit with proper GraphQL quoting so
the `__gl_query__` string is valid).

**Test:** operation with variable defaults generates correct method signatures in all 3
languages. Include a non-null variable with a default to verify no nullable widening.

---

### Step 7 — Operation variable defaults (Java)
**File:** `java_client_serializer.dart` / `java_client_operation_serializer.dart`

No method signature change. Resolve default inside method body before building the
variables map:
```java
if (role == null) role = Role.USER;
if (age == null) age = 18;
```

**Test:** assert generated Java client method body contains null-coalesce for defaulted
variables.

---

### Step 8 — Server field argument defaults (Spring)
Verify that graphql-java applies SDL-declared argument defaults automatically during
execution (now that Step 0 fixed schema emission). If yes — no codegen change needed.
If no — add the same null-coalesce pattern to generated Spring service method bodies.

**Test:** integration test confirming server applies the correct default when argument is
omitted from the client request.

---

## Out of scope (deferred)

- **Output type field defaults** (`type X { name: String = "default" }`): non-standard
  GraphQL SDL, SDL emission semantics unclear. Deferred until a decision is made on
  whether these are client-only annotations or need to appear in server schema.
- **Nested object/list defaults for input fields**: significantly more complex literal
  generation (nested constructor calls per language). Separate scoping after steps 1–7
  are done.

---

## Test file

All assertions live in `test/initial_values/initial_values_test.dart` (inline schema,
one file). Each step adds assertions to this file and passes before the next step begins.

The test schema **must include at least one non-null field with a default** (e.g.
`priority: Priority! = MEDIUM`) alongside nullable-with-default fields, to prove that
nullability is preserved and not widened.
