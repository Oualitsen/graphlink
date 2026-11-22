# Mapper classes for `@glExternal` types (hexagonal persistence boundary)

Status: implemented. Builds on `maps-to-v7.md`.

## Goal

Domain types are generated; persistence classes (JPA entities, Mongo documents) are hand-written and declared
in the schema as `@glExternal`. GraphLink generates the mapping between them, as a separate class
callable from anywhere (`UserMapper`), not only as a method on the source.

## What exists today (checked)

- `@glExternal(glClass, glImport)` on `type`/`input`: no class generated, fields declared, import known.
- `@glMapsTo` already accepts an external target: `User @glMapsTo(type: "UserEntity")` generates
  `User.toUserEntity()` (verified with a Java server run).

## Gaps

1. External **source** (`UserEntity → User`): nothing generates it, since an external type has no class to hold a method.
2. No mapper-class style: v7 plan left `inline | class` out of scope.
3. Is the external import emitted in the file that uses it? To verify per language.

## Design

- `@glMapsTo` stays the only directive. It is allowed on an external type (source) as well as on a generated one.
- Rule: a source that is external, or that targets an external type, is emitted in a mapper class (an external type has no class to hold a method, and GraphLink cannot know how to build it).
- Mapping with a generated source: inline method (today) by default; mapper class when configured:
  `"mapperStyle": "inline" | "class"` (default `inline`; external sources ignore it and are always class) in the server config (and client with `generateMappers`).
- Mapper class: one per generated source/external source, named `<Source>Mapper`, in the models package,
  one method per `@glMapsTo`: `UserMapper.toUserEntity(User)`, `UserEntityMapper.toUser(UserEntity)`.
  Static/object/namespace/free functions per language, no instance state.
- Both sides must be `type` or `input` (validation already rejects others).
- Field access on an external source uses the declared fields (getter in Java/Kotlin/Dart/Swift, property in TS/Python/Go).
  The declared fields are the contract; the developer's class must expose them.
- Both mapper classes may reference each other: same cyclic-import cases as in v7 (Python local import).

## Steps

1. Test: external source today, to pin the failure (`test/maps_to/maps_to_external_test.dart`, inline schema).
2. Validation: allow `@glMapsTo` on an external source; keep the rest.
3. `resolveMappings`: do not drop mappings whose source is external; flag them `classOnly`.
4. `GLMappingSerializer`: add `mapperClass(source, plans)`; per-language implementation through the `*CodeGenUtils` builders.
5. Generators: emit mapper files (and barrel entries) for sources that are external or when `mapperStyle` asks for it.
6. Config: `mapperStyle` in `config.dart`.
7. Languages in order: Java, Kotlin, Dart, then TypeScript, Python, Go, Swift.
8. Docs page + CHANGELOG.

## Tests

External source; external target; both directions with a nested type; list fields; `@glMapField` rename across the
external boundary; `mapperStyle` inline/class; external import present in the mapper file; validation errors.
