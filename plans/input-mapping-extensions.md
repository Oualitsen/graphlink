# Input Mapping Extensions

Three extensions to the existing `@glMapsTo`/`@glMapField` implementation.

---

## Feature 1 — Method generation selection

### Design

Add a `generate` argument to `@glMapsTo`:

```graphql
input CreateUserInput @glMapsTo(type: "User", generate: TO) { ... }
input CreateUserInput @glMapsTo(type: "User", generate: FROM) { ... }
input CreateUserInput @glMapsTo(type: "User", generate: BOTH) { ... }  # default
```

Enum values: `TO`, `FROM`, `BOTH`. Default: `BOTH`.

### Implementation

- Add `glMapsToGenerate` constant to `built_in_dirctive_definitions.dart`
- Add `mapsToGenerate` getter to `GLInputDefinition`
- In `DartSerializer` and `JavaSerializer`: check `def.mapsToGenerate` before generating each method — skip `toXxx()` if `FROM`, skip `fromXxx()` if `TO`

### Status

Ready to implement. No open questions.

---

## Feature 2 — Mode-aware, repeatable directives

### Motivation

Client and server often need fundamentally different target types or field-level mappings:
- Client target: `UserDTO` with non-null fields
- Server target: `UserEntity` with all-nullable fields (DB layer)

Java makes this especially visible: server-side entities frequently have nullable fields everywhere, which produces a different (and often incompatible) mapping shape than the client-side DTO.

### Design

Both `@glMapsTo` and `@glMapField` become repeatable. Each occurrence carries a `mode` argument (`CLIENT`, `SERVER`, `BOTH`). Default: `BOTH`.

```graphql
input CreateUserInput
  @glMapsTo(type: "UserDTO", mode: CLIENT)
  @glMapsTo(type: "UserEntity", mode: SERVER) {

  fname: String!
    @glMapField(to: "firstName", mode: CLIENT)
    @glMapField(to: "first_name", mode: SERVER)
  email: String!
}
```

The serializer picks the directive occurrence whose `mode` matches the current generation pass. If no mode-specific occurrence exists for a field, falls back to the `BOTH` occurrence if present, otherwise treats the field as unmapped.

### Impact on existing implementation

- `getDirectiveByName` → needs a mode-aware variant (e.g. `getDirectiveForMode(name, mode)`) that filters by `mode` argument
- `GLInputDefinition.mapsToType` → becomes `mapsToTypeForMode(mode)`, returns the matching target name
- `GLField.mapFieldTo` → same, becomes mode-aware
- Validation: each `@glMapsTo` occurrence validated independently against its own target

### Status

Initially felt off (too much complexity), but the Java server-mode discussion made the use case clear. Included. Not yet fully designed — the fallback resolution logic and validation rules for multiple occurrences need to be nailed down before implementation starts.

---

## Feature 3 — Schema-level default values

### Motivation

`fromXxx()` generates required `defaultXxx` parameters when a target field is nullable but the input field is non-null (the generator can't guarantee a value). In practice, especially in server mode where all target type fields are nullable, this produces a flood of required parameters that callers must always supply — even when they don't care about the value.

The goal: allow specifying a default directly in the schema so the generator can make the parameter optional (or suppress it entirely).

### Proposed syntax

Extend `@glMapField` with an optional `default` argument. `to` becomes optional when only setting a default:

```graphql
input CreateUserInput @glMapsTo(type: "User") {
  role:   String  @glMapField(to: "role", default: "USER")  # real fallback
  name:   String  @glMapField(default: null)                 # opt out of safety param
  status: String  @glMapField(default: "ACTIVE")
}
```

### What we agree on

- `default` lives on `@glMapField`
- `to` becomes optional on `@glMapField` (you can set a default without renaming the field)
- `default: someValue` turns a required `defaultXxx` param into an optional one with that value as fallback
- `default: null` is the escape hatch: no param generated, developer owns the nullability contract

### Dart behavior (agreed, no controversy)

Named optional parameters handle both cases naturally:

```dart
// default: "USER" → optional named parameter with real value
static CreateUserInput fromUser(User user, {String defaultRole = "USER"}) {
  return CreateUserInput(role: user.role ?? defaultRole, ...);
}

// default: null → optional named nullable parameter
static CreateUserInput fromUser(User user, {String? defaultName}) {
  return CreateUserInput(name: user.name ?? defaultName, ...);
}
```

Multiple defaulted fields compose cleanly — each is just another named parameter.

### Java behavior (no consensus yet)

Java has no named parameters and no default parameter values. Options discussed:

**Option A — Method overloading per field**

For each field with a `default`, generate two overloads: one without the parameter (uses default), one with (caller overrides):

```java
// default: "USER"
public static CreateUserInput fromUser(User user) {
    return fromUser(user, "USER");
}
public static CreateUserInput fromUser(User user, String defaultRole) {
    return new CreateUserInput(..., user.getRole() != null ? user.getRole() : defaultRole);
}
```

Problem: with multiple defaulted fields this explodes. Three fields with defaults → 2³ = 8 overloads. Not tenable beyond one field.

**Option B — Single overload, use all defaults at once**

Only generate two overloads total: one with all defaultable params (caller can override all), one with none (all defaults baked in). Callers either supply all or none:

```java
// all defaults baked in
public static CreateUserInput fromUser(User user) {
    return fromUser(user, "USER", "ACTIVE");
}
// caller overrides everything
public static CreateUserInput fromUser(User user, String defaultRole, String defaultStatus) {
    return new CreateUserInput(...);
}
```

Problem: if you only want to override one of three defaults, you still have to pass all three. Slightly better than Option A combinatorially, but poor ergonomics.

**Option C — `default: null` special-cased, non-null defaults still required**

For `default: null`: omit the parameter entirely, use the target value directly (even if nullable). Developer accepts the nullability risk.

For `default: someValue`: still generate a required parameter, but change its type or naming to signal the default is "known" (e.g., a comment). Does not actually solve the ergonomics problem for non-null defaults in Java.

**Option D — Deferred (not yet discussed)**

Builder pattern, varargs map, or some other Java idiom. Not explored yet.

### Open questions — blocking consensus

1. **Java + multiple non-null defaults**: Is Option B (two overloads, all-or-nothing) acceptable? Or do we need a different approach entirely? What is the realistic maximum number of defaulted fields on a single input in practice?

2. **`default: null` exact contract in Java**: Does it mean "generate no parameter, use `user.getField()` directly even if it may return null" (Option C / D)? If the input field is declared non-null in the schema, the generated Java field is a primitive or `@NonNull` — what does assigning a potentially-null value look like and is that the developer's explicit responsibility?

3. **Interaction with Feature 2 (mode-aware repeatability)**: Should `default` be combinable with `mode`? E.g.:
   ```graphql
   role: String
     @glMapField(default: "USER",  mode: CLIENT)
     @glMapField(default: null,    mode: SERVER)
   ```
   Is this a real use case? If yes, it needs to be handled in the resolver. If no, should we validate against it?

4. **`default` argument type in GraphQL**: The directive argument must have a type. GraphQL has no universal literal. Options: always `String` (serializer interprets it by field type, strips quotes for ints/booleans), or use a custom `GraphQLScalar`. Always-`String` is simpler but fragile for numeric defaults. What is the right trade-off?

5. **`toXxx()` direction**: Currently `toXxx()` also generates `required defaultXxx` for nullable source → non-null target mismatches. Should `default` suppress those too, or is it only for `fromXxx()`? The mismatch semantics are symmetric — if we fix one direction it feels inconsistent not to fix the other.

### Status

**No consensus.** Dart behavior is clear and agreed. Java behavior for non-null `default` values is unresolved. The blocking question is whether Java overloading is acceptable (and in what form), or whether we need a different mechanism entirely. Do not implement Feature 3 for Java until this is resolved.
