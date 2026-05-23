# Java @glCaptureErrors — Implementation Handoff

## What is already done

### Foundation (shared with Dart & TypeScript)
- `glCaptureErrors` is registered in the parser and validated (rejects subscriptions and list returns)
- `glCaptureErrors` is in `inheritedDirectives` in `gl_grammar_extension.dart` → it propagates to `GLQueryElement`
- `glCaptureErrors` is in `_skippedDirectives` in `graphq_serializer.dart` → it never leaks into sent GQL queries
- `getFullResponseTypeDefinition(GLParser)` on `GLQueryDefinition` builds the `XxxFullResponse` type model (with `data: XxxResponse?` and `errors: List<GraphLinkError>?`) — registered unconditionally in projected types when `GraphLinkError` is present
- `capture_errors_utils.dart` provides `def.isCaptureErrors(parser)` extension — returns `true` when the element has `@glCaptureErrors` OR `parser.captureErrors` is globally set
- `captureErrors: true` config parses correctly in `JavaClientConfig`
- The Java `FullResponse` classes are already generated as Java files (they go through `projectedTypes` → Java serializer → file output), same as regular response classes — the Java serializer already knows how to serialize `GLTypeDefinition` into a Java class with `fromJson`, `toJson`, builder, getters

### What the FullResponse Java class looks like (already generated)
The existing Java type serializer will produce something like:

```java
public class GetUserFullResponse {
    private final GetUserResponse data;
    private final List<GraphLinkError> errors;

    // builder, getters, fromJson, toJson ...

    public static GetUserFullResponse fromJson(Map<String, Object> json) {
        return GetUserFullResponse.builder()
            .data(json.get("data") == null ? null : GetUserResponse.fromJson(...))
            .errors(json.get("errors") == null ? null : ...)
            .build();
    }
}
```

---

## Files to change

Only **one file**: `lib/src/serializers/client_serializers/java_client_serializer.dart`

---

## What needs to change

### 1. Add import and `_hasFullResponseSupport` getter

At the top of the file, import `capture_errors_utils.dart`:
```dart
import 'package:graphlink/src/capture_errors_utils.dart';
```

Add a getter (same pattern as Dart and TypeScript serializers):
```dart
bool get _hasFullResponseSupport =>
    _grammar.getTypeByName('GraphLinkError') != null;
```

### 2. `returnTypeByQueryType` — return `XxxFullResponse` for captureErrors

Current:
```dart
String returnTypeByQueryType(GLQueryDefinition def) {
  if (def.type == GLQueryType.subscription) return "void";
  return def.getGeneratedTypeDefinition().tokenInfo.token;
}
```

New:
```dart
String returnTypeByQueryType(GLQueryDefinition def) {
  if (def.type == GLQueryType.subscription) return "void";
  if (def.isCaptureErrors(_grammar) && _hasFullResponseSupport) {
    return def.getFullResponseTypeDefinition(_grammar).tokenInfo.token;
  }
  return def.getGeneratedTypeDefinition().tokenInfo.token;
}
```

### 3. `parseToObjectAndCache` — add `captureErrors` parameter

This method is generated in `generateGraphLinkResolverBaseFile`. It currently throws on errors. Add a `boolean captureErrors` parameter and branch:

```java
protected <T> T parseToObjectAndCache(
    String data,
    Map<String, Object> cachedResponse,
    Function<Map<String, Object>, T> parser,
    List<GraphLinkPartialQuery> remainingQueries,
    boolean captureErrors           // ← NEW
) {
    Map<String, Object> result = decoder.decode(data);
    boolean hasErrors = result.containsKey("errors") && result.get("errors") != null;
    if (hasErrors) {
        if (!captureErrors) throw GraphLinkException.of((List) result.get("errors"));
        return parser.apply(result);           // captureErrors: pass full result to parser
    }
    Map<String, Object> dataMap = (Map<String, Object>) result.get("data");
    // ... cache logic unchanged ...
    dataMap.putAll(cachedResponse);
    if (captureErrors) return parser.apply(Collections.singletonMap("data", dataMap));
    return parser.apply(dataMap);
}
```

Also keep the old 4-arg overload delegating to the new one (for non-captureErrors callers that don't pass the flag):
```java
protected <T> T parseToObjectAndCache(String data, Map<String, Object> cachedResponse,
    Function<Map<String, Object>, T> parser, List<GraphLinkPartialQuery> remainingQueries) {
    return parseToObjectAndCache(data, cachedResponse, parser, remainingQueries, false);
}
```

### 4. `queryToMethod` — captureErrors cache-hit and `parseToObjectAndCache` call

In `queryToMethod`, compute `isCE` once:
```dart
final isCE = def.isCaptureErrors(_grammar) && _hasFullResponseSupport;
final fullResponseToken = isCE
    ? def.getFullResponseTypeDefinition(_grammar).tokenInfo.token
    : returnType;
```

**Cache-hit path** (line ~564):
- non-captureErrors (current): `return $returnType.fromJson($_svResponseMap);`
- captureErrors: `return $fullResponseToken.fromJson(Collections.singletonMap("data", $_svResponseMap));`

**`parseToObjectAndCache` call** (line ~570):
- non-captureErrors (current): `return parseToObjectAndCache($_svResponseText, $_svResponseMap, $returnType::fromJson, $_svRemaining);`
- captureErrors: `return parseToObjectAndCache($_svResponseText, $_svResponseMap, $fullResponseToken::fromJson, $_svRemaining, true);`

**Stale fallback** (line ~580):
- non-captureErrors (current): `return $returnType.fromJson($_svResponseMap);`
- captureErrors: `return $fullResponseToken.fromJson(Collections.singletonMap("data", $_svResponseMap));`

Note: `Collections.singletonMap` requires `java.util.Collections` — add to the container imports when `isCE`.

### 5. `_serializeMutationAdapterCall` — captureErrors branch

Current (non-captureErrors):
```java
String responseText = glCallAdapter(payload);
Map<String, Object> decodedResponse = decoder.decode(responseText);
if (decodedResponse.containsKey("errors")) {
    throw GraphLinkException.of((List) decodedResponse.get("errors"));
}
Map<String, Object> data = (Map<String, Object>) decodedResponse.get("data");
// invalidate
return XxxResponse.fromJson(data);
```

New for captureErrors:
```java
String responseText = glCallAdapter(payload);
Map<String, Object> decodedResponse = decoder.decode(responseText);
XxxFullResponse result = XxxFullResponse.fromJson(decodedResponse);
if (result.getErrors() == null) {
    // invalidate (only on success)
}
return result;
```

New for non-captureErrors (route through FullResponse then unwrap — same as Dart):
```java
String responseText = glCallAdapter(payload);
Map<String, Object> decodedResponse = decoder.decode(responseText);
XxxFullResponse result = XxxFullResponse.fromJson(decodedResponse);
if (result.getErrors() != null) {
    throw GraphLinkException.of(result.getErrors());
}
// invalidate
return result.getData();
```

Note: `result.getData()` returns `XxxResponse` (the regular response). The method return type is `XxxResponse` for non-captureErrors.

---

## Nullable return for non-captureErrors

Java doesn't have built-in nullable method signatures like Dart (`Future<XxxResponse?>`).
For a nullable schema return type (`getUser: User` without `!`), the regular Java behaviour 
is that `XxxResponse.getUser()` may return `null`. No changes needed at the method signature 
level for Java — the Java method always returns `XxxResponse` (never null wrapper), 
so no equivalent of Dart's `?` suffix is required.

---

## Tests

The test file already exists: `test/serializers/java/capture_errors_java_test.dart`

It has the right preamble (`getClientObjects` + Java built-in objects), the right schema, 
and the right group structure. All tests currently fail because the Java serializer is not 
yet updated. Once the serializer is done, update the test assertions to match the new design 
(FullResponse approach, not inline errors) — following the same pattern as the Dart and 
TypeScript test files.

---

## Verification checklist

| Scenario | Expected |
|---|---|
| `getUser @glCaptureErrors` method return type | `GetUserFullResponse` |
| `listUsers` (plain) method return type | `ListUsersResponse` |
| `deleteUser @glCaptureErrors` mutation return | `DeleteUserFullResponse` directly |
| `createUser` (plain) mutation return | `CreateUserResponse` (unwrapped from `.getData()`) |
| Cache hit for `getUser` | `GetUserFullResponse.fromJson(Collections.singletonMap("data", responseMap))` |
| `parseToObjectAndCache` captureErrors path | Called with `true`, parser gets `{"data": mergedMap}` |
| Invalidation for captureErrors mutation | Only when `result.getErrors() == null` |
| `@glCaptureErrors` NOT in sent GQL query strings | Already handled by `_skippedDirectives` ✓ |
| `captureErrors: true` global config | All query/mutation methods return FullResponse |
