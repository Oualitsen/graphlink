# Plan: @glCaptureErrors — Inline Error Handling

## Context

Currently all generated client methods follow a binary contract: either return typed data or throw on GraphQL errors. This forces callers to use try/catch. `@glCaptureErrors` changes this for opted-in queries and mutations: errors are returned inline alongside the data, the method never throws, and the caller checks `response.errors`.

A global config flag (`captureErrors: true`) applies the directive to all queries and mutations without annotating the schema.

---

## Design

### Directive

```graphql
type Query {
  getUser(id: ID!): User! @glCaptureErrors
}
```

- No arguments
- Applies to queries and mutations only — rejected on subscriptions at parse time
- Generated method name unchanged (`getUser`)

### Generated response class changes

A separate `{OperationName}FullResponse` class is generated alongside the existing `{OperationName}Response`. The original response class is **unchanged**. The full-response wrapper holds `data` (nullable) and `errors`:

```dart
class GetUserFullResponse {
  final GetUserResponse? data;
  final List<GraphLinkError>? errors;

  GetUserFullResponse({this.data, this.errors});

  Map<String, dynamic> toJson() => {
    'data': data?.toJson(),
    'errors': errors?.map((e) => e.toJson()).toList(),
  };

  static GetUserFullResponse fromJson(Map<String, dynamic> json) {
    return GetUserFullResponse(
      data: json['data'] == null
          ? null
          : GetUserResponse.fromJson(json['data'] as Map<String, dynamic>),
      errors: (json['errors'] as List?)
          ?.map((e) => GraphLinkError.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
```

Caller checks `response.errors` directly. No `hasErrors` getter.

### Generated method body

The method return type changes from `{OperationName}Response` to `{OperationName}FullResponse`.

**Mutation** — simplest case, becomes a single return:

```dart
// Before:
final result = jsonDecode(await glCallAdapter(payload));
if (result.containsKey('errors')) throw ...;
return GetUserResponse.fromJson(result['data']);

// After:
return GetUserFullResponse.fromJson(jsonDecode(await glCallAdapter(payload)));
```

**Query with caching** — cache path wraps the stored data map so the same `fromJson` is used everywhere:

```dart
// Cache hit:
return GetUserFullResponse.fromJson({'data': responseMap});

// Network path (no throw on errors):
return GetUserFullResponse.fromJson(jsonDecode(responseText));
```

### Caching

Error responses are **never cached** — same as today. Cache only holds successful responses. On a cache hit `errors` is implicitly null.

### Global config

`captureErrors: true` in `clientConfig.dart` / `clientConfig.java` / `clientConfig.typescript` is syntactic sugar — at grammar-extension time the generator sets `isCaptureErrors: true` on every query and mutation definition. No separate code path.

---

## Files to Change

### 1. `lib/src/model/built_in_dirctive_definitions.dart`
- Add `const glCaptureErrors = "@glCaptureErrors";`

### 2. `lib/src/model/new_parser/gl_parser.dart`
- Register `@glCaptureErrors` with scope `{GLDirectiveScope.FIELD_DEFINITION}` and no arguments

### 3. `lib/src/gl_validation_extension.dart`
- Add `checkGLCaptureErrorsDirectives()`:
  - `@glCaptureErrors` on a subscription field → `ParseException`
- Call in `validateSemantics()` inside the client mode block

### 4. `lib/src/model/gl_queries.dart`
- Add `final bool isCaptureErrors` to `GLQueryDefinition` (default `false`)
- Update constructor

### 5. `lib/src/gl_grammar_extension.dart`
- When building a `GLQueryDefinition`, set `isCaptureErrors: true` if field has `@glCaptureErrors`
- When global config `captureErrors: true`, set `isCaptureErrors: true` on all query/mutation definitions

### 6. `lib/src/config.dart`
- Add `bool get captureErrors => false;` to `ClientLanguageConfig`
- Override and parse in `DartClientConfig`, `JavaClientConfig`, `TypeScriptClientConfig`

### 7. Response class generation (Dart)
- When `isCaptureErrors`:
  - Generate a `{OperationName}FullResponse` class alongside the existing `{OperationName}Response` (leave the original unchanged)
  - `FullResponse` holds `final {OperationName}Response? data` and `final List<GraphLinkError>? errors`
  - `fromJson` takes the full response JSON, navigates `json['data']` for data and `json['errors']` for errors
  - Include `toJson` for symmetry

### 8. `lib/src/serializers/client_serializers/dart_client_serializer.dart`
- Mutation with `isCaptureErrors`: remove throw block, change return type to `{OperationName}FullResponse`, return `FullResponseType.fromJson(jsonDecode(await glCallAdapter(payload)))`
- Query with `isCaptureErrors`:
  - Change return type to `{OperationName}FullResponse`
  - Cache hit path: `return FullResponseType.fromJson({'data': responseMap});`
  - Network path: `return FullResponseType.fromJson(jsonDecode(responseText));`
  - No throw on errors

### 9. `lib/src/serializers/client_serializers/typescript_client_serializer.dart`
- Generate a `{OperationName}FullResponse` interface with `data?: {OperationName}Response` and `errors?: GraphLinkError[]`
- Leave the original response interface unchanged
- Remove `if (result.errors) throw` block
- Method return type changes to `{OperationName}FullResponse`
- Cache hit path: same wrapping pattern as Dart

### 10. `lib/src/serializers/client_serializers/java_client_serializer.dart`
- Generate a `{OperationName}FullResponse` class with `{OperationName}Response data` (nullable) and `List<GraphLinkError> errors` (nullable)
- Leave the original response class unchanged
- Remove `if (result.containsKey("errors")) throw` block
- `fromJson` of `FullResponse` takes full response map, navigates `data` internally
- Method return type changes to `{OperationName}FullResponse`
- Cache hit path: same wrapping pattern

---

## Verification

### A. Generated response class

For `getUser(id: ID!): User! @glCaptureErrors`:
- `GetUserResponse` is unchanged (non-null `getUser` field, no error awareness)
- `GetUserFullResponse` is generated with `data: GetUserResponse?` and `errors: List<GraphLinkError>?`
- `GetUserFullResponse.fromJson` navigates `json['data']` and `json['errors']`

### B. Generated method body

- Mutation: single-line return of `GetUserFullResponse`, no throw block present
- Query: return type is `GetUserFullResponse`, no throw on errors, cache hit wraps with `{'data': map}`

### C. Runtime behavior

| Server response | `response.data` | `response.errors` |
|---|---|---|
| `{ "data": { "getUser": {...} } }` | populated | null |
| `{ "errors": [...] }` | null | populated |
| `{ "data": { "getUser": null }, "errors": [...] }` | null (data parses but getUser is null) | populated |

### D. Caching interaction

- First call → success → cached; second call → cache hit, `errors` null
- First call → errors → NOT cached; second call → goes to server again

### E. Validation errors

| Schema | Expected |
|---|---|
| `@glCaptureErrors` on subscription field | ParseException |

### F. Global config

`captureErrors: true` with no `@glCaptureErrors` in schema → all query/mutation methods behave as if the directive is present.

### G. Non-annotated methods unaffected

An adjacent query without `@glCaptureErrors` still throws on errors and returns unwrapped data.
