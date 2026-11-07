# Integration test gaps

Audit of `integration_tests/` on 2026-11-07, after #516. It replaces `integration-schema-coverage.md`, which had stopped tracking
what was shipped.

## How this was measured (and what it cannot tell)

- Every schema operation and every custom query is **named in at least one test of every language**, with three exceptions listed in
  section 1. So "is this operation touched" is not the question any more; the gaps are **behaviours**.
- The behaviour gaps below come from a keyword search over each language's test sources (`real/*_client_tests_real`,
  `real/*_rest_client_tests_real`). A cell with no match is written as **no evidence**, not "untested": a test may exist under
  other words. Check the named file before writing a new test.
- Nothing was executed for this audit. It says what the tests contain, not whether they pass.
- Not audited: `server_integration_tests/` (generated servers), the Flutter UI generators, `examples/`.

## 0. Suite sizes (test cases, counted by annotation or function pattern)

| Language | GraphQL real | REST real | GraphQL mock | REST mock | Persisted mock / real | Upload real |
|---|---|---|---|---|---|---|
| Dart | 325 | 149 (+ dio: reuses these) | 187 | 24 | 30 / 8 | 8 (+ dio package: 0 own) |
| Java | 343 | 87 | 221 | 10 | 31 / 8 | 11 |
| Kotlin | 341 | 86 | 225 | 10 | 30 / 8 | 11 |
| TypeScript | 330 | 149 | 186 | 24 | 30 / 8 | 11 |
| Swift | 338 | 125 | 224 | 23 | 30 / 8 | 11 |
| Python | 179 | 136 | 70 | 23 | 26 / 8 | 11 |
| Go | 163 | 54 | 58 | 7 | 23 / 8 | 12 |

**The smaller Python and Go counts are not missing coverage.** They write fewer, wider test cases: for the TypeScript topic files
(enums, inputs, lists, nested types, nullability, scalars, normalization, cycle, gl_expand, literal arguments, error capture, cache),
every operation used by TypeScript is used in the Python and Go tests, and every expected value TypeScript asserts is asserted there
too (one exception each, in section 1.1). Compare behaviour, not counts.

## 1. Parity gaps (the same behaviour tested in some languages, not in others)

### 1.1 GraphQL real

Closed on 2026-11-07:

- `createUserOrErrors` (captured mutation error and success) in Python.
- `getCachedConfig` (a cached query with no shared tag survives `transferPost` and is served after `resetAll`) in Python and Go.
- The keyword `class` query, argument and input field (`class_` / `makeClass`) in Java, Kotlin and TypeScript (`KeywordTest`,
  `keyword.test.ts`); Dart, Go, Python and Swift already had it.

Still open:

- `getCachedConfig` in the Dart, Java and Kotlin real packages (their cache tests count calls on a mock adapter; the Dart mock suite
  has it, check the Java and Kotlin mock suites).
- `counterTickRestart` (the server restarts itself after tick N) is used only by Swift.
- `enum_spellings` has its own file only in Dart and Go; the other languages test the spellings inside `identifiers`/`list_shapes`.
- Python `subscription_reconnect` has 1 case against 3 (Go 3, Dart/Java/Kotlin/TypeScript 3); Python and Go upload have 3 GraphQL
  cases against 6.
- Python and Go: `inputs` echo (name, email, country `UK`) and Go `scalars` nullable float `2.718` are the only TypeScript values
  not asserted.

### 1.2 REST real

- Go REST (54 cases against 149) was compared behaviour by behaviour against the TypeScript suite on 2026-11-07: it covers the same
  operations, cache rules, uploads, downloads, headers, forms and edge cases in fewer, wider tests. The one missing behaviour, a raw
  upload stream that fails mid-way, now has a test (`TestRawBodyStreamThatFailsMidWay...`, passing).
- `dart_rest_dio_client_tests_real` has no tests of its own; it runs the http package's tests with `REST_VARIANT=dio`.
- Timeout: no evidence in Python, Swift, Go. Cancellation: only Swift.

### 1.3 Mock suites

- `mock/go_rest_tests` 7, `mock/java_rest_tests` 10, `mock/kotlin_rest_tests` 10 against 23 to 24 for Dart, TypeScript, Swift, Python.
- `mock/python_client_tests` 70 and `mock/go_client_tests` 58 against 186 to 225: not compared operation by operation yet.

## 2. Behaviours with **no evidence in any language** (GraphQL)

| Gap | What to build |
|---|---|
| Null propagation: a null in a non-null field makes the parent null and the error carries the path | Spring resolver returning null for a non-null field; assert `data` shape, `errors[0].path` |
| Response that is not JSON (HTML 502 page) | Fault-injection route on the real server or a recording proxy; assert a clear exception, not a parse crash |
| `strictEnums: true` (second generated output per language) | Second config per package; unknown value must fail with a named error |
| Very long string (1 MB) in a field and an argument | Echo operation |
| `ID` served as a JSON number | Hand-written resolver returning an int for `ID` |
| `getCachedConfig`, `counterTickRestart` | See 1.1 |
| `@glCaptureErrors` with partial data / union result / list result | Operations that return data and errors together |
| `staleIfOffline` on a union result; network failure while a cached union exists | Cached union query, then stop the server |
| `Float` served as a JSON integer (`1` for `1.0`) | Weak evidence (Python, Go, Swift 1 to 2 hits, none elsewhere); check Dart, TypeScript and Kotlin decoding |

Weak evidence (a few hits, check the file): partial `data` plus `errors` (3 to 5 hits in Dart, Java, TypeScript, Go; 1 in Python),
`extensions`/`locations`/`path` on errors (1 hit each, none in Python and Go), HTTP 4xx/5xx (2 to 6 hits), offline (none in Go and Python).

## 3. Behaviours with no evidence in any language (REST)

The request side is strong; the gaps are on the response and transport side:

- BOM, trailing whitespace, duplicate keys in a JSON response.
- JSON number overflow, exponent notation (`1e3`) for an integer field.
- Status `205`, `304`, `3xx` without `Location`.
- Content-Type mismatch: JSON served as `text/plain` (only Java, Swift, Go mention a charset).
- Very long path or query value.
- Header names with mixed case; repeated response headers; cookies.
- Enum as a path segment or a header value.
- Top-level JSON array of scalars, of arrays, of polymorphic values.
- Timeout (only Dart, Java, Kotlin, TypeScript mention it) and cancellation (Swift only).
- `@glRestNullable` combined with `@glRestPrefix` (2 to 3 hits per language, but only one combination each).
- Dates and timestamps in paths, bodies and responses: 1 to 6 hits in each language except Swift; no dedicated case.
- Pagination envelope with a sibling field (Dart and TypeScript, Python 1 each; none in Java, Kotlin, Go).

Still open from section 1.2 of the old plan (not seen in the Dart test names, unverified elsewhere): non-string discriminators,
discriminator differing only by case, interface extending interface with discriminators, union member that is an interface,
a type in two unions with different discriminator values, `@glRestNullable` over nested polymorphism, a REST operation using a
union or interface without `@glRestDiscriminator` (belongs in `test/validation/`).

## 4. Known defects that tests cannot cover yet

- **Swift `fromJson` is not throwing.** An unknown or missing `__typename` or discriminator ends in `fatalError`; a missing
  non-null field in a force unwrap. Plan only: `plans/swift-throwing-polymorphic-decode.md`. Swift therefore has no test for
  those cases, in GraphQL and in REST.
- **Dart `subscription_reconnect` and Java `subscription_reconnect`** fail under plain `make test` and need the harness that
  restarts the server (`reconnect-test` targets). Never compared against `main`.
- **Java `JSON` and `BigDecimal`** are plain `Object` (decided fine), so the Java scalar test asserts shape, not type.

## 5. CI state after the refactors

CI and Persisted Queries on the merge of #516 (`6ffc83dd`): 88 of 88 and 22 of 22 jobs green, none skipped. #514 and #515 were green too.
The failures on #511 to #513 were the missing scalar type mappings in the reactive and persisted-queries configs, fixed by #513 and #514.
The jobs cover the unit tests, the GraphQL mock and real suites of all seven languages (Java reactive included), the REST mock and
real suites (Java reactive and Dart dio included), uploads, persisted queries (mock and real) and the server matrix.

Not confirmed from the workflow files: whether the `subscription_reconnect` tests run in CI (see section 4).

## 6. Hardening ideas beyond filling the table

1. **A CI job that regenerates every integration package and fails on a diff** with no test run, so a generator refactor shows its
   effect on all languages at once (what the byte-identical checks did by hand for #515).
2. **Large real-world schemas as compile checks**: GitHub and GitLab already exist as fixtures; generate all seven languages from
   them and compile (not run) in CI.
3. **Round-trip property tests per language**: generate random values for a schema's inputs and types, `toJson` then `fromJson`,
   compare. Catches the codec and nullability bugs the hand-written cases keep finding.
4. **Fault-injection server** (HTML body, truncated JSON, slow response, wrong content type, 5xx with and without a GraphQL body)
   shared by GraphQL and REST suites: closes most of sections 2 and 3 with one server and one test per language.
5. **Cross-language golden payloads**: one JSON corpus of requests the client must send for a fixed operation set, compared
   byte-for-byte in all seven languages (argument encoding differs most in Go and Swift).
6. **Operation and value parity check for Go REST and the Python/Go mock suites**, done the way section 0 was for GraphQL real.

## 7. Suggested order

1. Fault-injection server (idea 4) with the GraphQL and REST response-side gaps of sections 2 and 3.
2. Go REST and the Python/Go mock suites: compare by operation and value (section 1.2, 1.3).
3. `strictEnums: true`, null propagation, `staleIfOffline` on unions.
4. Swift throwing decode (section 4), which also unlocks the Swift tests missing from every polymorphism case.
