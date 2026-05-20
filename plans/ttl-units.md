# TTL Duration Strings — Feature Plan ✓ Implemented in v4.7.0

## Overview

Allow `@glCache` to accept human-readable duration strings for the `ttl` argument instead of raw integers (seconds). The generator parses the string at build time and emits the integer seconds internally — zero runtime impact.

---

## Goals

- Improve ergonomics for developers writing `@glCache` directives
- Keep all runtime generated code using integers (no change to serializers or generated client logic)
- Validate duration strings at generation time with a clear error on bad input

## Non-Goals

- Runtime duration parsing
- Support for duration strings anywhere other than `ttl`
- Sub-second precision

---

## Directive Change

`ttl` changes from `Int` to `String` in the directive definition.

```graphql
# Before
getUser(id: ID!): User! @glCache(ttl: 120)

# After
getUser(id: ID!): User! @glCache(ttl: "2m")
```

---

## Supported Formats

| Format | Meaning | Example |
|--------|---------|---------|
| `"<n>s"` | seconds | `"90s"` → 90 |
| `"<n>m"` | minutes | `"4m"` → 240 |
| `"<n>h"` | hours | `"2h"` → 7200 |
| `"<n>d"` | days | `"1d"` → 86400 |
| `"<n>"` | bare integer — treated as seconds | `"300"` → 300 |

Suffixes are case-insensitive (`"4M"` = `"4m"`).

---

## Breaking Change

Changing `ttl` from `Int` to `String` is a **breaking change** for existing schemas. Migration is a mechanical find-and-replace:

```
ttl: 120  →  ttl: "120"   # or ttl: "2m"
```

The generator should emit a **clear error** if it encounters an unquoted integer, guiding the user to migrate:

```
Error: @glCache ttl must be a String (e.g. "120", "2m", "1h").
       Found bare integer: ttl: 120
       Hint: change to ttl: "120" or ttl: "2m"
```

---

## Generator Changes

Only the **directive parser / validator** changes. No serializer logic changes.

### Parsing logic

```
parse(value: String) → Int (seconds):
  strip whitespace
  if ends with 'd' → parseInt(prefix) * 86400
  if ends with 'h' → parseInt(prefix) * 3600
  if ends with 'm' → parseInt(prefix) * 60
  if ends with 's' → parseInt(prefix)
  if all digits    → parseInt(value)
  else             → generation error
```

### Validation

- Value must be a positive integer after unit conversion
- `ttl: "0s"` is a generation error — zero TTL is meaningless
- `ttl: "-1m"` is a generation error — negative TTL is meaningless

---

## Escaping `$` in Tag Strings

Not directly related, but since TTL strings introduce the first quoted directive argument, document clearly that `$` in tag strings is a generator-level interpolation marker (see `dynamic-tags-caching.md`) and is not affected by this change.

---

## Affected Files

- Directive definition (wherever `@glCache` is declared)
- Generator directive parser / validator
- Documentation (`site/docs-src/caching.md`, `site/docs-src/directives.md`)

Serializers (Dart, Java, TypeScript) are **not affected** — they consume the already-resolved integer.

---

## Example

```graphql
type Query {
  getUser(id: ID!): User!             @glCache(ttl: "1m",  tags: ["users", "user-detail-$id"])
  listUsers: [User!]!                 @glCache(ttl: "5m",  tags: ["users"])
  getConfig: AppConfig!               @glCache(ttl: "1d")
  getLivePrice: Price!                @glCacheSkip
}
```
