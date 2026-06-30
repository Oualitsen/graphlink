# Identifier normalization — generated code casing

## Problem

GraphQL field names are not constrained to any casing convention. A real-world
schema can legally declare:

```graphql
type Company { User: User }            # PascalCase field → Dart compile error
type Query   { search_users: [User] }  # snake_case field → un-idiomatic in Dart/Java/TS/Kotlin
enum Status  { active inactive }       # lowerCase values → wrong in Java (SCREAMING expected)
```

Each target language has a canonical identifier casing. When the schema violates
it the generated code either fails to compile (Dart: `User User;` → name
collision with the class) or produces a poor developer experience.

## Key invariant (already upheld by keyword-safe)

Every GraphQL name has two distinct roles:

| Role | Name | Usage |
|---|---|---|
| **Wire name** | original schema token | GraphQL query string, JSON key in `toJson`/`fromJson` |
| **Code name** | normalized identifier | class property, constructor param, enum value constant |

The `codeName` field on `GLField` / `GLEnumValue` / `GLArgumentDefinition`
already carries this split for keyword-safe. Normalization extends the same
mechanism — it is not a parallel system.

## Decisions

| # | Question | Decision |
|---|---|---|
| 1 | Target languages for Stage 1 | Dart, Java, Kotlin, TypeScript |
| 2 | Scope | Fields + enum values (query arguments deferred to Stage 2) |
| 3 | Opt-in vs always-on | Always-on per target language |
| 4 | Collision strategy | Index suffix (`user`, `user2`, `user3`) — matches existing query collision logic |
| 5 | Breaking change | Intentional; ships in a major release |

### Conventions per language

| Language | Field identifier | Enum value identifier |
|---|---|---|
| Dart       | `lowerCamelCase` | `lowerCamelCase`      |
| Java       | `lowerCamelCase` | `SCREAMING_SNAKE_CASE` |
| Kotlin     | `lowerCamelCase` | `SCREAMING_SNAKE_CASE` |
| TypeScript | `lowerCamelCase` | `PascalCase`           |

## Composition order inside `assignCodeNames()`

For every identifier:

```
1. Apply NamingConvention.field(rawName)   → normalized
2. If normalized ∈ reservedWords → append "_"
3. If normalized collides with a sibling on the same type → append index (2, 3 …)
4. Assign to codeName only if it differs from rawName (same optimization as today)
```

Example:
```
Return → lowerCamelCase → return → reserved → return_
User   → lowerCamelCase → user   → not reserved → no sibling collision → user
user   → lowerCamelCase → user   → not reserved → collision with prev  → user2
```

---

## Implementation plan

### Step 1 — Extend `lib/src/extensions.dart`

Add a private word-splitter that handles all incoming cases, then three
assemblers built on top of it.

```dart
/// Splits any identifier into lowercase word tokens.
/// Handles: PascalCase, camelCase, SCREAMING_SNAKE, snake_case, kebab-case,
/// and mixed forms (e.g. HTMLParser → [html, parser]).
List<String> _splitWords(String s) {
  return s
      // Replace separators with spaces
      .replaceAll(RegExp(r'[-_]+'), ' ')
      // Insert space before an uppercase letter preceded by a lowercase/digit
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      // Insert space before the last uppercase in a run (HTMLParser → HTML Parser)
      .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
}

extension StringExt on String {
  // … existing helpers …

  /// myField / MY_FIELD / MyField / my_field  →  myField
  String toLowerCamelCase() {
    final words = _splitWords(this);
    if (words.isEmpty) return this;
    return words.first +
        words.skip(1).map((w) => w.firstUp).join();
  }

  /// myField / MY_FIELD / my_field  →  MyField
  String toPascalCase() {
    final words = _splitWords(this);
    if (words.isEmpty) return this;
    return words.map((w) => w.firstUp).join();
  }

  /// myField / MyField / my_field  →  MY_FIELD
  String toScreamingSnakeCase() {
    final words = _splitWords(this);
    if (words.isEmpty) return this;
    return words.join('_').toUpperCase();
  }
}
```

Keep the existing `toSnakeCase()` and `toKebabCase()` unchanged (used
elsewhere).

---

### Step 2 — `lib/src/naming_convention.dart` (new file)

```dart
/// Defines how raw GraphQL identifiers are transformed into target-language
/// identifiers. Two separate transforms are required because field casing and
/// enum-value casing follow different conventions in some languages
/// (e.g. Java: lowerCamelCase fields, SCREAMING_SNAKE enum values).
///
/// Use the pre-built static instances ([dart], [java], [kotlin], [typescript])
/// rather than constructing ad-hoc lambdas in generators.
class NamingConvention {
  final String Function(String) field;
  final String Function(String) enumValue;

  const NamingConvention._({required this.field, required this.enumValue});

  static final NamingConvention dart = NamingConvention._(
    field:      (s) => s.toLowerCamelCase(),
    enumValue:  (s) => s.toLowerCamelCase(),
  );

  static final NamingConvention java = NamingConvention._(
    field:      (s) => s.toLowerCamelCase(),
    enumValue:  (s) => s.toScreamingSnakeCase(),
  );

  static final NamingConvention kotlin = NamingConvention._(
    field:      (s) => s.toLowerCamelCase(),
    enumValue:  (s) => s.toScreamingSnakeCase(),
  );

  static final NamingConvention typescript = NamingConvention._(
    field:      (s) => s.toLowerCamelCase(),
    enumValue:  (s) => s.toPascalCase(),
  );
}
```

`NamingConvention._` is a private constructor so callers always use the
pre-built instances. Adding a new target language means adding one more static
`final` here — no changes elsewhere.

---

### Step 3 — `GLParser`: add `naming` parameter

In `lib/src/model/new_parser/gl_parser.dart`, add alongside `reservedWords`:

```dart
/// Naming convention applied to field and enum-value identifiers before
/// keyword-safe sanitization. `null` means no transformation (identity).
/// Each language generator supplies the appropriate instance.
final NamingConvention? naming;
```

Add to the constructor parameter list and the initializer. No other parser
logic changes — normalization is entirely in `assignCodeNames()`.

---

### Step 4 — Extend `gl_grammar_keyword_extension.dart`

Replace the current guard (`if (reservedWords.isNotEmpty)`) with a combined
guard so normalization runs even when `reservedWords` is empty:

```dart
void assignCodeNames() {
  final hasKeywords   = reservedWords.isNotEmpty;
  final hasNaming     = naming != null;
  if (!hasKeywords && !hasNaming) return;   // nothing to do

  if (hasKeywords || hasNaming) {
    for (final t    in types.values)              { t.assignCodeNames(reservedWords, naming); }
    for (final i    in inputs.values)             { i.assignCodeNames(reservedWords, naming); }
    for (final iface in interfaces.values)        { iface.assignCodeNames(reservedWords, naming); }
    for (final t    in projectedTypes.values)     { t.assignCodeNames(reservedWords, naming); }
    for (final iface in projectedInterfaces.values) { iface.assignCodeNames(reservedWords, naming); }
    for (final e    in enums.values)              { e.assignCodeNames(reservedWords, naming); }
    for (final c    in controllers.values)        { c.assignCodeNames(reservedWords, naming); }
    _assignQueryCodeNames(queries.values);
  }

  if (parameterReservedWords.isNotEmpty) {
    // argument normalization unchanged for now (Stage 2)
    …
  }
}
```

Each container's `assignCodeNames()` signature becomes:

```dart
void assignCodeNames(Set<String> reserved, NamingConvention? naming)
```

Inside each container, the per-field loop:

```dart
void assignCodeNames(Set<String> reserved, NamingConvention? naming) {
  final taken = <String>{};
  // Seed taken with the wire names that won't be normalized (keeps collision
  // detection honest about names that stay unchanged).
  for (final f in fields) {
    taken.add(f.name.token);
  }

  for (final f in fields) {
    final raw = f.name.token;

    // 1. Apply naming convention.
    var code = naming?.field(raw) ?? raw;

    // 2. Keyword-safe.
    if (reserved.contains(code)) code = '${code}_';

    // 3. Collision with siblings (index suffix).
    if (taken.contains(code) && code != raw) {
      var counter = 2;
      while (taken.contains('$code$counter')) counter++;
      code = '$code$counter';
    }

    // 4. Assign only if different from wire name.
    if (code != raw) {
      f.codeName = code;
      taken.add(code);
    }
  }
}
```

Same pattern for `GLEnumDefinition.assignCodeNames()` using `naming?.enumValue`.

---

### Step 5 — Wire into generators

Each generator constructs `GLParser` with the appropriate convention.
No other generator changes are needed.

| Generator file | Change |
|---|---|
| `dart_client_generator.dart` | pass `naming: NamingConvention.dart` |
| `java_client_generator.dart` | pass `naming: NamingConvention.java` |
| `kotlin_client_generator.dart` | pass `naming: NamingConvention.kotlin` |
| `typescript_client_generator.dart` | pass `naming: NamingConvention.typescript` |
| `server_generator.dart` | Spring: `NamingConvention.java`; Express: `NamingConvention.typescript` |

---

### Step 6 — Tests

One test file per language under the existing per-language directories.
Each covers:

1. PascalCase field on a type (`User: User` → `user`)
2. SCREAMING_SNAKE field (`MY_FIELD: String` → `myField` / `my_field` etc.)
3. Enum values per language convention
4. Collision pair on same type (`user` + `User` → `user` + `user2`)
5. Reserved word after normalization (`Return: String` → `return_`)

All schemas inline as `const String`.

---

## Out of scope (Stage 2)

- Operation argument normalization (query `$userId`, resolver params)
- Type/class name normalization (PascalCase is the GraphQL convention; real
  schemas follow it; high blast radius for marginal gain)
- Python / Rust / Swift — `NamingConvention` is ready to accept new instances
  when those targets are added; no further architecture changes needed
