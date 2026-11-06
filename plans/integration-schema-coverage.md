# Integration schema coverage gaps

Status: audit done, nothing implemented yet.

Scope: `integration_tests/real/schema_rest/rest.graphql` and `integration_tests/real/schema_real/schema.gql`.
Not read during the audit (check before implementing, some gaps may already be covered there):
`schema_real/custom_query.graphql`, `schema_real/upload.gql`, `integration_tests/mock/schema_mock/`,
`real/rest_server/server.py`, the Spring servers' payloads, and the per-language test packages.

Goal: make the shared schemas exhaustive. Every schema is consumed by every client target
(Dart, Java incl. Reactor/RxJava3/Mutiny, Kotlin, TypeScript, Python, Swift, Go), so each addition
must come with a test in **every** package that uses that schema, and a server route/resolver that
serves it. Where a language cannot support a case, record the exception in the test, don't skip silently.

## Progress (2026-11-06)

Real-only (no mock variants) decided. Batch 1 of section 1.2 (REST polymorphism) is implemented in `schema_rest/rest.graphql`
(`Kennel`, `Shelter`, `petsNullable`, `petsOptional`, `petsWrapped`, `petNoKind`, `petNullKind`, `petExtraKeys`,
`petMissingField`, `cachedPet`, `adoptPet`) and `rest_server/server.py` (`polymorphic()`), with a 14-case test in
Dart, TypeScript (fetch + axios), Kotlin, Python, Go (both variants), Swift (both variants, reduced) and Java blocking. All green.

Not done: Dart dio variant, Java reactive flavors (derived from the blocking package via `generate_reactor_tests.dart`),
the Kotlin/Java/TS/Python/Go/Swift variants of anything outside batch 1, all of section 1.1 (GraphQL), and sections 2 to 9.

Findings:

- **Swift crashes instead of throwing on a bad polymorphic payload.** `fromJson` is non-throwing. An unknown, absent or null
  discriminator ends in `fatalError("Cannot decode Pet: unknown or missing \"kind\" value ...")` (`Pet.swift`), and a missing
  non-null field in a force unwrap (`Dog.swift`). XCTest cannot catch either, so Swift has only the happy-path and
  unknown-extra-keys tests for these cases. A new server subtype would crash a shipped Swift app. Decision needed: leave as
  the documented Swift limitation, or make the polymorphic decode failable or throwing.
- XCTest and JUnit gotcha: JUnit 5 silently skips a Kotlin test whose expression body returns a value. Declare
  `runBlocking<Unit>` and check the test count in the report.

### GraphQL polymorphism, custom queries and subscriptions (2026-11-06)

Schema: union `Attachment`, interfaces `Node` and `Entity implements Node`, `Article` and `Comment` (`implements Entity & Node`),
in `schema_real/schema.gql` and the Spring `schema.graphqls`; `PolymorphismController`; subscriptions `attachmentAdded` and
`entityPublished`. 15 tests in each of the 7 real GraphQL packages (Java reactive derived), all green. Dart additionally has custom
queries (`fetchAttachment`, `fetchArticleAndAttachment`) and the two subscriptions. Not yet ported to the other six languages.

Fixed, each with a unit test that failed first:

1. Fragment set truncated through interface or union edges (`transitiveDependecies`, `gl_fragment.dart`);
   `test/fragment/transitive_fragment_dependencies_test.dart` and `all_fields_fragment_test.dart`.
2. Go emitted `GetId` twice for a type implementing `Entity & Node`; `go_serializer_test.dart`.
3. A hand-written named fragment on a union or interface failed to parse when an inline fragment selected a field only the member has
   (`Could not find field 'width' on type Attachment`); `handleFragmentDepenecy` in `gl_grammar_fragment_extension.dart` now looks the
   field up on the inline fragment's own type; `test/fragment/named_fragment_on_abstract_type_test.dart`.

Open, found by custom queries that were taken out of `custom_query.graphql` so the shared generation stays green:

4. **FIXED.** Fragment spread inside an inline fragment was not sent (`_getFragmentNamesByBlock` in `gl_query_element.dart` skipped inline-fragment projections); `test/fragment/fragment_spread_in_inline_fragment_test.dart`. Original report: **Fragment spread inside an inline fragment is not sent.** `GLQueryDefinition.fragmentNames` is `{}` for
   `query fetchFeed { feed { id ... on Article { title attachments { ...AttachmentParts } } ... on Comment { text } } }` with
   `fragment AttachmentParts on Attachment { ... on Photo { id width } ... on Video { id seconds } }`. The generated
   `glFragmentNames__` is empty, so the server rejects the query. Same blind spot as `getDependecies()` on inline-fragment projections.
5. **A projected type can take the name of a schema type.** The `fetchFeed` above (against the schema's `Article`, which has a `related`
   field the query does not select) produces `projectedTypes['Article']` with fields `[id, createdBy, title, cover, attachments]`
   and interfaces `[Node_1, Entity_1]`. The generated `article.dart` then replaces the real `Article`: no `related`, wrong interface,
   `attachments: List<SearchResult>`; `Entity.fromJson` no longer compiles.
6. **FIXED (IR level).** Fields selected through an interface fragment never reached the members: `_collectProjection` now applies an inline fragment to every possible type of its type condition (`possibleTypeTokens`, `gl_grammar_extension.dart`), and `validateProjection` accepts an inline or named fragment whose possible types overlap the parent's (a named fragment only reaches the members it applies to) (`... on Entity` inside a union, a supertype fragment inside an object); `test/projections/interface_fragment_projection_test.dart`. End to end, `fetchNode` is blocked by bug 5, so it is not in `custom_query.graphql` yet. Original report: **Fields selected through an interface fragment never reach the members.** `node(id: $id) { id ... on Entity { createdBy } ... on Article { title } }`
   generates `Article_IdTitle { id, title }` and `Comment_Id { id }`; `createdBy` is returned by the server and dropped by the client.
7. **A shared projected abstract type dispatches to one fixed projected member.** Found while checking bug 4 end to end.
   `attachment(id: $id) { ... on Photo { ...PhotoParts } ... on Video { id } }` (with `fragment PhotoParts on Photo { id url width }`) and
   `node(id: $id) { id ... on Article { attachments { ...AttachmentParts } } }` both project to an abstract type with only `id`, which
   the generator reuses as the existing `SearchResult { id }`. `SearchResult.fromJson` dispatches `Photo` / `Article` to the projected
   class registered first (`Photo_IdWidth`, `Article_CoverIdTitle`), so the fields the query selected for that member are lost or the
   decode throws (`type 'Null' is not a subtype of type 'String'`). The server side of both queries is correct.
   (The projected abstract type being named `SearchResult` is not a bug: it is structurally identical to the schema's `SearchResult { id }`
   and the generator reuses it.)

## Working method

- IR-first and TDD: reproduce each case as a failing generation or runtime test before touching a serializer.
- Add the schema element, the server route (`server.py` for REST, `spring_server` for GraphQL), the mock
  fixture, then one test per language. Edit the blocking Java test, not the derived reactive copies
  (`generate_reactor_tests.dart`).
- A case that exposes a bug is fixed in the IR/extension layer when it is a decision, in the serializer
  only when it is string building.
- Cases that must be rejected at generation time belong in `test/validation/` (inline `const` schema),
  not in the integration schemas.

---

## 1. Unions and interfaces (priority)

### 1.1 GraphQL (`schema_real`)

Current state: no `union` at all. `SearchResult` (2 implementations, only `id` shared) and `Vehicle`
(reached only through the nullable single `VehicleDriver.vehicle`).

Add:

- [ ] A `union` returned as a single non-null, a nullable single, a list, and a list with nullable elements.
- [ ] A union nested inside an object type (`Post.attachment: Attachment`) and inside a list field.
- [ ] A union returned by a mutation and by a subscription.
- [ ] A union whose members share a field name with **different types** (`Photo.size: Int`, `Video.size: String`).
- [ ] A union whose members share a field name with the **same type** (shared accessor vs. per-member).
- [ ] A type that is a member of two unions.
- [ ] An interface returned as single non-null, nullable, list, and nested inside an object.
- [ ] An interface that implements another interface (`interface Node`, `interface Entity implements Node`).
- [ ] A type implementing several interfaces (`implements A & B`).
- [ ] An interface with a field that itself returns an interface or union.
- [ ] An interface with field arguments.
- [ ] An interface with no implementing type selected by the query (projection yields only the base).
- [ ] A union with a single member.
- [ ] A union member that is a type also returned directly elsewhere (type reuse vs. projected copy).
- [ ] Cached (`@glCache`) query returning a union and returning an interface; invalidation by tag.
- [ ] `@glCaptureErrors` on an operation returning a union.
- [ ] Custom queries over polymorphic results:
  - inline fragments on concrete types only;
  - inline fragment on the interface itself (`... on SearchResult { id }`) mixed with concrete ones;
  - explicit `__typename` selection;
  - `_all_fields` on an interface and on a union;
  - named fragment on an interface, on a union member, and on the union itself;
  - nested polymorphism (union inside a fragment inside a union member);
  - the same field aliased on different members.
- [ ] Unknown `__typename` from a newer server: define and test the behaviour per language
  (throw, fallback member, or `unknown`), consistent with `strictEnums`.
- [ ] Missing `__typename` in the payload.
- [ ] A union/interface-typed field that is `null` inside a non-null list element (error path).

### 1.2 REST (`schema_rest`)

Current state: `Pet` (interface) and `Hit` (union), as list and nullable single, unknown discriminator
(`petsUnknown`), lenient/strict variants.

Add:

- [ ] A polymorphic value nested inside an object (`Owner { pet: Pet }`), inside a list field, and two levels deep.
- [ ] Nullable list elements of `Pet`/`Hit` (`[Pet]!`, `[Pet!]`, `[Pet]`).
- [ ] A polymorphic result reached through `responsePath`.
- [ ] Payload with the discriminator field **absent** (distinct from an unknown value).
- [ ] Discriminator with `null` value.
- [ ] Non-string discriminators (int, bool) if the directive allows them; otherwise a validation test.
- [ ] Discriminator value that differs from the type name only by case.
- [ ] Interface extending an interface, each with a discriminator.
- [ ] Union member that is itself an interface.
- [ ] A type that is a member of two unions with different discriminator values.
- [ ] A polymorphic result from a mutation, from a `@glCache` operation, and from a `Download`/`responsePath` combination.
- [ ] `@glRestNullable` over nested polymorphism (copy of members, discriminator keeps wire values).
- [ ] Extra unknown keys inside a polymorphic member.
- [ ] A polymorphic member with a missing required field: error names the field and the member.
- [ ] Union/interface without `@glRestDiscriminator` used by a REST operation: generation error (validation test).

---

## 2. Scalars

- [ ] Custom scalars in `schema_real`: `DateTime`, `Date`, `Long`, `BigDecimal`, `JSON`, and one unmapped custom scalar.
  Test default mapping, user-configured mapping, as field, list element, argument, input field, and default value.
- [ ] `Long` / integers beyond 32 bits and beyond 2^53 (TypeScript/JS number precision).
- [ ] `Float` served as a JSON integer (`1` instead of `1.0`): Dart `int` vs `double`, Swift, Go.
- [ ] `Float` special values if the server can emit them.
- [ ] `ID` served as a JSON number; `ID` sent from an `Int`-looking string.
- [ ] Empty string, very long string, unicode, emoji, RTL text in responses and arguments.
- [ ] Nullable vs. absent key vs. explicit `null` for every scalar kind (all three decode the same way).

## 3. Lists and nullability

- [ ] All list shapes as response fields: `[T!]!`, `[T!]`, `[T]!`, `[T]`, `[[T!]!]!`, `[[T]]`, with the server really sending `null` elements.
- [ ] The same shapes as arguments and as input fields.
- [ ] Empty list vs. `null` list.
- [ ] List of enums, list of custom scalars, list of unions, list of interfaces.
- [ ] Very large list (REST has `big`; add a GraphQL equivalent).

## 4. Identifiers and naming

`class` is the only keyword tested. Targets now include Python, Go and Swift.

- [ ] Field, argument, input-field, operation and type names that collide with reserved words:
  `type`, `default`, `in`, `is`, `var`, `val`, `fun`, `new`, `import`, `return`, `object`, `from`, `None`, `True`,
  `func`, `range`, `self`, `Self`, `init`, `Type`, `Protocol`, `async`, `await`, `package`, `interface`, `enum`, `null`.
- [ ] Enum values that are reserved words or look like literals: `null`, `true`, `false`, `default`, `class`.
- [ ] Type names that clash with runtime or stdlib names: `Error`, `Response`, `Request`, `List`, `Map`, `Object`,
  `Optional`, `Date`, `Result`, `Void`, `Upload`.
- [ ] Names that differ only by case, and names that become equal after normalisation (`user_id` vs `userId`).
- [ ] Leading underscore, trailing underscore, digits inside, all-caps acronyms (`URLValue`, `HTTPServer`).
- [ ] Non-canonical casing on the REST side: snake_case, kebab-case and `$`-prefixed JSON keys mapped to field names.
- [ ] Keyword names as REST path/query/header/form/part parameter names.
- [ ] Two fields whose generated accessors would clash (`isActive` and `active`, `getX` and `x`).

## 5. Literals, defaults and escaping

- [ ] String defaults and literals containing `$`, `${x}`, `"`, `'`, `\`, newline, tab, `%`, `{}`, `*/`, `//`,
  triple quotes, unicode escapes.
- [ ] Default values for every scalar, enum, list, nested list, nested input, `null` default.
- [ ] Default on an argument whose type is an input object with its own defaults.
- [ ] Descriptions (`"""..."""` and `"..."`) with `*/`, `$`, backticks, `@`, `<`, non-ASCII, very long lines.
- [ ] `@deprecated` with and without reason, on fields, arguments, enum values.
- [ ] Recursive input (`input Tree { children: [Tree!] }`) and mutually recursive inputs.
- [ ] `@oneOf` input objects.

## 6. Custom operations (`schema_real`)

- [ ] Named fragments: `fragment X on T`, fragment inside fragment, fragment reused across operations, fragment on interface/union.
- [ ] Variables: with defaults, list variables, enum variables, input-object variables, nullable vs. non-null, unused variable.
- [ ] `@include(if:)` / `@skip(if:)` with variable and literal.
- [ ] Aliases: same field twice with different arguments, alias colliding with a keyword, alias equal to another field name.
- [ ] Multiple root fields in one operation with a shared fragment.
- [ ] Operation name colliding with a type, with a keyword, or with another generated name.
- [ ] Field arguments on nested object fields (`Driver` covers two; add list, enum, input arguments).
- [ ] Literal arguments (new in 6.0.0): every scalar kind, enum, list, input object, mixed with variables.
- [ ] Subscription with a union result, with a list result, with arguments of every shape, error mid-stream, server-side completion.

## 7. Enums

- [ ] Unknown value from the server with `strictEnums` both `false` and `true`, in a field, a list element, a map-like position and a union member.
- [ ] Enum value spelled in every casing style (exists: `pending`, `in_progress`); add digits, double underscores, single letter.
- [ ] Enum with one value.
- [ ] Enum used only as an argument, only in a response, only in a REST path segment.
- [ ] Enum default on an argument and on an input field.

## 8. Errors and partial results

- [ ] GraphQL: `data` with partial `null` plus `errors` with `path`, `locations`, `extensions`.
- [ ] Null propagating through non-null fields up to the parent.
- [ ] Top-level `errors` with `data: null`; transport-level HTTP 4xx/5xx with and without a GraphQL body.
- [ ] Non-JSON body (HTML error page) on GraphQL (REST has `htmlError`).
- [ ] `@glCaptureErrors` with partial data, with a union result, with a list result.
- [ ] Network failure + `staleIfOffline` on a union result.

## 9. REST-specific gaps

Request side is already strong (parameter roles, encodings, multipart, headers, caching, status codes, bad payloads).
Gaps are on the data model and response side:

- [ ] Free-form JSON object / map result (`JSON` scalar) and a list of them.
- [ ] Dates and timestamps in paths, queries, bodies and responses.
- [ ] Enums as path segments and header values.
- [ ] Nullable list elements in query lists, forms, multipart and bodies.
- [ ] Pagination envelope (`{ data, next }`) with `responsePath` plus a sibling field the client ignores.
- [ ] Top-level JSON array of scalars; of arrays; of polymorphic values.
- [ ] Response with a BOM, with trailing whitespace, with duplicate keys, with deeply nested depth.
- [ ] Integer overflow in a JSON number; floats with exponent notation.
- [ ] `204` on a list-returning operation; `205`; `304`; `3xx` without `Location`.
- [ ] Error body shapes (JSON error object vs. plain text vs. empty) and how `RestError` exposes them.
- [ ] Response `Content-Type` mismatch (JSON served as `text/plain`, `charset` variants).
- [ ] Very long path/query values and percent-encoding of reserved characters, unicode and `+`/space in every position.
- [ ] Path parameter containing `/`, `..`, `%2F`.
- [ ] Duplicate query keys vs. `queryListStyle` variants, empty-string vs. absent vs. `null` for every encoding.
- [ ] Header names with mixed case; repeated headers in the response.
- [ ] Cookies and auth header flows (set per request vs. adapter-level).
- [ ] Cancellation and timeouts per language.
- [ ] `@glRestNullable` combined with `@glRestPrefix`, with `@glCache`, with lists of lists, with enums unknown to the client.

## 10. Per-language test matrix

Every item above is tested in each package below, using the same assertions where the language allows.

| Schema | Packages |
|---|---|
| `schema_real` | `dart_client_tests_real`, `java_client_tests_real` (+ reactor / rxjava3 / mutiny derived), `kotlin_client_tests_real`, `typescript_client_tests_real`, `python_client_tests_real`, `swift_client_tests_real`, `go_client_tests_real` |
| `schema_rest` | `dart_rest_client_tests_real`, `dart_rest_dio_client_tests_real`, `java_rest_client_tests_real` (+ reactor / rxjava3 / mutiny), `kotlin_rest_client_tests_real`, `typescript_rest_client_tests_real` (+ axios), `python_rest_client_tests_real` (+ comma), `swift_rest_client_tests_real` (+ comma), `go_rest_client_tests_real` (+ comma) |
| mock counterparts | `mock/*_client_tests` and `mock/*_rest_tests` for the same cases that need no server |

Also keep in mind:

- Swift strict types decode with force unwraps, so a missing non-null field traps instead of throwing:
  strict-twin tests for new cases are not possible there; note this per case.
- Go uses interfaces decoded from `__typename` / `UnmarshalJSON`; Python uses the pydantic dispatch validator.
  Polymorphism cases differ most between these, so write them first.
- Server-matrix (`server_integration_tests/`) is a separate suite for generated **servers**; add union/interface
  cases there too once the client side is green.

## 11. Suggested order

1. Polymorphism, REST (section 1.2): smallest surface, one server, all eight clients already wired.
2. Polymorphism, GraphQL (section 1.1): needs a union in `schema_real` and Spring resolvers.
3. Identifiers and escaping (sections 4, 5): cheap to add, high bug yield on Python, Go, Swift.
4. Scalars, lists and nullability (sections 2, 3).
5. Custom operations, enums, errors (sections 6 to 8).
6. Remaining REST gaps (section 9).
