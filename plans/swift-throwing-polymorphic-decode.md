# Swift: throwing `fromJson` for interfaces and unions

Status: plan only, nothing implemented.

## Problem

Swift's generated `fromJson` is non-throwing. The interface/union dispatch ends in `fatalError(...)` when the wire data does not
pick a member, which terminates the app and cannot be caught (not even by XCTest).

Emitted today (`lib/src/serializers/swift/swift_serializer.dart`):

- `_dispatchFactory` default branch (line ~298): `fatalError("Unknown <T> __typename: ...")`, for GraphQL and REST.
- `_discriminated` default branch (line ~323): `fatalError("Cannot decode <T>: unknown or missing \"<field>\" value (...)")`, REST only.

Every other client throws a catchable error in the same cases (Kotlin, Java: `IllegalArgumentException`; TypeScript: `Error`;
Python: `ValueError`; Go: `error`; Dart: `ArgumentError`).

## Goal

The dispatch of an interface or union throws a Swift `Error` when:

- `__typename` is absent or not a known member (and, for REST, no discriminator rescues it),
- the REST discriminator is absent, null or not a known value.

Everything that decodes a value that can reach a dispatch becomes `throws` too. Everything else is unchanged.

Out of scope (separate step, same mechanism): the force casts for missing required fields (`map["barks"] as! Bool`).

## Rules for this change

- The decision "does decoding this type need to throw" is derived in the IR, not in the serializer.
- Serializers only read that answer. No schema walking in `swift_serializer.dart`.
- Build code through `SwiftCodeGenUtils` (`method`, `switchStatement`, ...). The `*_constants.dart` runtime templates are edited as
  text where they are templates (`swift_client_constants.dart`, `swift_rest_constants.dart`), nothing more.
- Port nothing to other languages: they already throw.

## Design

### 1. IR: which types decode with `throws`

New derived getter on `GLParser` in a `gl_grammar_*_extension.dart` file (suggested: `gl_grammar_extension.dart` or a small new
`gl_grammar_throwing_decode_extension.dart`):

`bool decodesWithThrows(String typeToken)`

- `true` for an interface or union that has at least one serializable implementation (it has a dispatch).
- `true` for an object type, input-free response type or projected type that has a field whose type (list/nullable unwrapped)
  is such an interface or union, or an object type for which this is `true`.
- `false` otherwise (scalars, enums, plain objects without polymorphic fields).
- Cycle-safe (visited set), cached per token.
- Covers projected types and the generated `*Response` / `*FullResponse` wrappers, because they are `GLTypeDefinition`s in
  `projectedTypes`.

This one getter drives every `throws` / `try` the serializers emit.

### 2. Swift serializer: types and dispatch

`swift_serializer.dart`, driven by the getter:

- `_dispatchFactory`: `public static func fromJson(_ map: ...) throws -> any <T>`; the default branch throws
  `GraphLinkDecodeError` instead of `fatalError`.
- `_discriminated`: same, with the discriminator message.
- Object/projected/response `fromJson`: add `throws` when `decodesWithThrows(token)`, and `try` on the calls that need it
  (field decoders that go through a dispatch, `fromJsonValueExpr` for polymorphic fields, list `map` becomes `try ... .map`).
- List/optional decoding of polymorphic elements: `try` inside the closure, and the outer `map` call prefixed with `try`.
- `toJson`: unchanged.

### 3. Runtime error type

Add `GraphLinkDecodeError: Error, CustomStringConvertible` to the Swift client runtime template
(`swift_client_constants.dart`), carrying the message. The REST runtime already has `RestDecodeError` in `swift_rest_constants.dart`;
decide in step 3a whether to reuse it or keep one shared type (see open questions).

### 4. Runtime templates and callers

`swift_client_constants.dart`:

- `executeFull` / `executeData` / cached-response helpers: `fromJson: ([String: Any?]) throws -> T`, call sites `try fromJson(...)`
  (lines ~323, 336, 349, 369, 380). The enclosing functions are already `async throws`, so no signature change for users.
- `GraphLinkCacheEntry.fromJson` / `GraphLinkTagEntry.fromJson` are not polymorphic: unchanged.

`swift_client_operation_serializer.dart` (13 mentions): subscription streams and cached paths that call a generated `fromJson`
get `try`; the stream decoding closure becomes `throws` and failures finish the stream with the error.

`swift_rest_operation_serializer.dart` / `RestDecode`: the decode expression (`fromJsonValueExpr`, line ~267) gets `try` when the
result type needs it; the generated REST method is already `async throws`.

### 5. Public API effect

Generated `fromJson` of an affected type becomes `throws`. Any app code calling `Pet.fromJson(...)` / `PetJson.fromJson(...)`
directly must add `try`. Client methods (`client.queries.x()`) are unchanged. This goes in the CHANGELOG as a behaviour change.

## Tests (IR first, TDD)

Unit tests, inline `const` schemas, written before the change:

1. IR (`test/...`, new file `swift_throwing_decode_test.dart` or next to the extension): `decodesWithThrows` is true for an
   interface, a union, a type with an interface field, a type with a list of unions, a type that reaches one through another
   object (depth 2), a response wrapper whose payload is polymorphic; false for scalar-only types, enums, plain nested objects;
   terminates on a cyclic schema.
2. Swift serializer output (`test/swift_serializer_tests` or the existing Swift tests): dispatch contains `throws` and
   `throw GraphLinkDecodeError`, no `fatalError`; a polymorphic-field type has `throws` and `try`; a plain type is unchanged.

Integration tests (real, as before; mock only if a hostile payload is needed):

3. REST (`swift_rest_client_tests_real`): restore the tests that could not exist: unknown discriminator (`petsUnknown`), absent
   (`petNoKind`), null (`petNullKind`), each asserting the thrown error names the parent and the key/value.
4. GraphQL (`swift_client_tests_real`): a hostile payload for an unknown `__typename` and an absent one. The Spring server cannot
   send them, so use the mock adapter in `integration_tests/mock/swift_client_tests` for these two cases.
5. Regression: the full Swift suites (`swift-real`, `swift-rest-real`, mock `swift`, `swift-rest`) pass unchanged except where tests
   called `fromJson` directly (`EnumsTest.swift` in the mock package; check each).
6. Update `integration-test-gaps.md`: remove the Swift exception notes for these cases.

## Steps

1. Unit tests 1 and 2 (failing).
2. IR getter.
3. Serializer changes (sections 2 and 4), generate the mock Swift package, fix compile errors it reports.
4. Runtime templates (sections 3 and 4).
5. Integration tests 3 and 4, run both Swift suites, then the mock suites.
6. CHANGELOG entry and a line in `rest-client-specs.md` section 9 / `client-specs.md` if they mention the Swift limitation.

## Open questions

1. One error type for both transports, or keep `RestDecodeError` for REST and add `GraphLinkDecodeError` for GraphQL?
2. On an unknown `__typename` from a newer server, throw (this plan) or return an `unknown` placeholder member? The placeholder would
   be a feature for all languages and is not part of this plan.
3. Is a breaking change to the public static `fromJson` of affected types acceptable for the next release?
4. Do the missing-field force casts (`as!`) follow in the same release, using the same getter?
