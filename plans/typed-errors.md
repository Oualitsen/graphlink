# Typed domain errors (`@glError`, `@glThrows`)

Status: phases 1 and 2 done (IR, exception classes, `@glThrows`, matching and throwing for GraphQL in every client). REST
and the server side are later phases. Target: v7 (breaking changes allowed).

## Goal

An operation returns its result or throws one of a few declared business errors, and every generated client lets the
caller catch them by type:

```python
try:
    article = (await client.queries.article(id="1")).article
except ArticleNotFound as e:
    show_missing(e.id)
```

The errors are declared once in the schema; nobody writes the exception classes by hand.

The client and the server are **two independent features** that meet only through a wire convention. The client works
against any GraphQL or REST server (GraphLink or not); a GraphLink server, added later, simply emits that convention.
GraphQL and REST work the same way, so moving an operation from one to the other changes no caller code.

## Phases

| Phase | Content | State |
|---|---|---|
| 1 | `@glError` IR + validation + exception classes and the `GraphLinkDomainError` base in every client | done |
| 2 | `@glThrows`, matching and throwing for GraphQL (client) | done: `integration_tests/real/*_client_errors_tests_real` |
| 3 | Matching and throwing for REST (client) | later |
| 4 | OpenAPI responses, docs page, `llms.txt` | later |
| 5 | Server side | later, own plan |

Everything below that describes matching or throwing is phase 2 or 3.

## Non-goals (first version)

- Server side (see §6).
- Errors on nested fields. Only root fields (GraphQL) and REST operations.
- Subscriptions.
- The "payload with a `userErrors` list" style (Shopify). See "Later".
- Result unions (`union ArticleResult = Article | ArticleNotFound`). They already work today as typed data and are
  untouched by this feature.

## Vocabulary

| Kind | Example | Handled by |
|---|---|---|
| **Domain error** | `ArticleNotFound`, `TitleTaken` | this plan: declared in the schema, matched, thrown by type |
| Other GraphQL error | validation error, resolver crash, unmatched entry | today's `GraphLinkException` |
| Transport / HTTP error | timeout, 502 from a proxy, unmatched 4xx/5xx | today's exceptions (`RestError`, …) |

---

## 1. Schema

### Declaring an error

```graphql
type ArticleNotFound @glError { id: ID! }
type TitleTaken      @glError { title: String! }
```

- `@glError` goes on an object type. Its fields are the exception's typed fields.
- An error type is not a GraphQL type of the API: it is never used as a field type, argument, input, interface
  implementer or union member (parse error), and a GraphLink server does not serve it.
- Fields may be empty (`type Forbidden @glError { }`): the exception then carries only the base members.

### Matching arguments

| Argument | Default | Meaning |
|---|---|---|
| `field` | GraphQL: `"extensions.code"`; REST: `"code"` | dotted path of the discriminator, relative to the GraphQL error entry (GraphQL) or the JSON body (REST) |
| `value` | the type name | string the discriminator must equal |
| `status` | none | REST only: HTTP status the response must have |

```graphql
type ArticleNotFound @glError { id: ID! }                              # GraphLink convention: extensions.code == "ArticleNotFound"
type NotFound        @glError(value: "NOT_FOUND") { id: ID }           # Apollo style: extensions.code == "NOT_FOUND"
type RepoNotFound    @glError(field: "type", value: "NOT_FOUND") { }   # GitHub style: the discriminator is on the entry
type Gone            @glError(status: 410) { }                         # REST: status only
```

The type is always chosen by the discriminator (and status), never by the shape of the fields. Fields are decoded only
after the type is chosen.

### Declaring which operations throw it (phase 2)

```graphql
type Query {
  article(id: ID!): Article @glThrows(errors: [ArticleNotFound])
  author(id: ID!):  Author  @glThrows(errors: [AuthorNotFound])
}
type Mutation {
  createArticle(input: ArticleInput!): Article @glThrows(errors: [TitleTaken])
}
```

- `@glThrows` goes on root fields of `Query` / `Mutation` and on `@glRest` operations.
- It is the developer's choice and limits the candidates: an error is matched only against the errors of its own
  operation. Two errors may therefore share a discriminator as long as no single operation throws both.
- It also feeds the generated doc comment of the method (the errors it can throw).

---

## 2. Wire format

### GraphQL

Standard GraphQL: the error is an entry of the `errors` array, its data lives in `extensions`.

```json
{
  "data": { "article": null },
  "errors": [{
    "message": "Article 42 not found",
    "path": ["article"],
    "extensions": { "code": "ArticleNotFound", "id": "42" }
  }]
}
```

| Entry piece | Used for |
|---|---|
| `path[0]` | the root field the error belongs to (selects its `@glThrows` list) |
| discriminator (`field`, default `extensions.code`) | which declared error it is |
| `extensions.*` | the error's typed fields |
| `message` | the base exception's `message` |

Consequences (accepted):

- The errors do not appear in introspection; non-GraphLink clients learn them from documentation (as with Apollo).
- The failed field is `null`. If it is non-null, GraphQL nulls the parent, for a root field the whole `data`.

### REST

A non-2xx response. The same matching idea, with the JSON body playing the role of the entry:

| Piece | Used for |
|---|---|
| HTTP status | `status` condition (if the error sets one) |
| body, `field` (default top-level `code`) | which declared error it is |
| body | the error's typed fields |
| body `message` (if any) | the base exception's `message` |

---

## 3. IR

Model `model/gl_error.dart`, extension `parser_extensions/gl_grammar_error_extension.dart`, directive declared in
`internal_directive_declarations.dart`.

```dart
class GLErrorDefinition {
  final GLTypeDefinition type;
  final List<String> field;   // discriminator path, default ["extensions", "code"]
  final String value;         // default type.token
  final int? status;          // REST only
}

// on GLParser
final Map<String, GLErrorDefinition> errors;   // not under `types`
```

`@glError` types are moved out of `parser.types` right after the directives are validated, so no existing pass, generator
or serializer that iterates `types` ever sees them. Serializers read `parser.errors`.

Serializers only read the IR; every decision (defaults, matching order, which operations throw) lives in the IR.

### Validation (parse time)

1. `@glError` only on object types (the directive scope).
2. An `@glError` type is never referenced as a field type, argument, input field, interface implementer or union member.
3. Field names of an error type must not clash with the base exception's members in any target
   (`message`, `path`, `extensions`, `cause`, `stack`, `args`, …).
4. `field` is a non-empty dotted path; `value` a non-empty string; `status` a valid HTTP status (100 to 599).
5. *(phase 2)* `@glThrows(errors:)` names only `@glError` types, without duplicates.
6. *(phase 2)* `@glThrows` only on `Query` / `Mutation` root fields and `@glRest` operations.
7. *(phase 2)* Ambiguity: within one `@glThrows` list, two errors with the same `field`, `value` and `status` are rejected.

Tests: `test/errors/`, inline schemas, written before the extension (TDD).

---

## 4. Client side

### Generated surface (phase 1)

- One exception class per `@glError` type, in its own file, subclassing the runtime base `GraphLinkDomainError`
  (generated into every client's runtime, not configurable for now). It is named so because Python already has a built-in
  `BaseException`.
- The base is tiny: the language's plain exception plus a `message`. It does not depend on `GraphLinkError` (which only
  exists in client mode), so the same classes can be generated on a backend with no extra types.
- Fields are the type's fields. `fromJson(map, message)` decodes them from the `extensions` map (GraphQL; the body for
  REST later). The constructor takes the fields and an optional message, so a service can `throw new X(...)` and the
  client creates it from a response.
- A caught typed error does not carry the entry's `path` or raw `extensions`; unmatched errors keep `GraphLinkException`
  and `@glCaptureErrors` keeps the whole response.

| Target | Base extends | Caller code | Notes |
|---|---|---|---|
| Python | `Exception` | `except ArticleNotFound as e:` | plain class, not pydantic |
| Dart | `implements Exception` | `on ArticleNotFound catch (e)` | |
| TypeScript | `Error` | `catch (e) { if (e instanceof ArticleNotFound) … }` | `Object.setPrototypeOf(this, X.prototype)` so `instanceof` works on ES5 |
| Kotlin | `RuntimeException` | `catch (e: ArticleNotFound)` | not a data class |
| Java | `RuntimeException` | `catch (ArticleNotFound e)` | **unchecked** (decided), Java 8 compatible |
| Swift | `Error` | `catch let e as ArticleNotFound` | plain class |
| Go | `error` | `var nf *ArticleNotFound; if errors.As(err, &nf) { … }` | error values |

### GraphQL: what the client does (phase 2)

Inserted before today's `GraphLinkException`, only when the response has `errors`:

1. For each entry, take `path[0]`; if that root field has `@glThrows`, test its declared errors in order.
2. Match (discriminator equals `value`) → decode `extensions` with the error's `fromJson` and throw it.
3. No match, a missing required field, or no `path` → today's `GraphLinkException`, unchanged. This is also the
   fallback for errors the client does not know (version skew); no extra "unknown error" type is needed.
4. **Combined queries**: a typed error is thrown only when the operation has a single root field. With several root
   fields the client keeps `GraphLinkException`, which carries every entry, so nothing is lost. `@glCaptureErrors` is the
   way to get partial data.
5. `@glCaptureErrors`: nothing is thrown; entries stay in the full response as today. A typed shape for it is "Later".
6. `@glCache`: errors are never cached.

### REST: what the client does (phase 3)

Today every non-2xx becomes `RestError(status, headers, body)`. The new step sits just before:

1. Non-2xx → for each error in the operation's `@glThrows`: `status` (if set) AND the discriminator (if set) must hold.
   The default discriminator is the body's top-level `code` equal to the type name. `status` without `field` or `value`
   means status only.
2. Match → decode the body with the error's `fromJson` and throw it.
3. No match or a body that does not decode (HTML from a proxy, missing field) → today's `RestError`.

Reuses the decoding approach of `@glRestDiscriminator` and the path idea of `responsePath`.

If one type is used by both a GraphQL and a REST operation and carries a custom `field`, that `field` is resolved against
both the entry and the body. Unsolved on purpose: use two types.

---

## 5. Version skew

- A server adding a new error: old clients do not match it → `GraphLinkException` / `RestError`, as today.
- A client declaring an error the server never sends: dead code, harmless.

---

## 6. Server side (later, separate feature)

Sketch only:

- The service throws the generated exception (`throw ArticleNotFound(id)`).
- The generated server catches the base class and writes the GraphQL error entry (`extensions.code` = `value`,
  fields in `extensions`) or, for REST, `status` and the JSON body.
- `@glError` types are not served in the schema.

The only contract with the client is the wire convention of §2.

---

## 7. Rollout

1. **IR + validation** (phase 1), TDD in `test/errors/`.
2. **Exception classes + `GraphLinkDomainError`** in all seven clients (phase 1), a generation test per target and a mock
   check that the generated class imports and decodes an `extensions` map.
3. **Python client, GraphQL matching and throwing** (phase 2): `integration_tests/mock/` canned responses for success, each
   declared error, an unmatched code, an entry with a missing field, a combined query, `@glCaptureErrors`.
4. Study the result, adjust; fan out to the other clients.
5. **REST matching** (phase 3): same cases plus an HTML error body; the fault suite gains "error status with HTML body"
   and "error status with a body missing a field".
6. OpenAPI: each REST error becomes a response (`status` + schema); docs page, `llms.txt` sync.
7. Server side (§6) as its own plan.

---

## Decided

- Runtime base: `GraphLinkDomainError`, generated per client, idiomatic parent per language, no rename option for now.
- Combined queries: typed error only for single-root-field operations; otherwise `GraphLinkException`.
- REST behaves like GraphQL (same declarations, same `catch`); per-operation `status` override dropped.
- `code:` argument dropped in favor of `field` / `value`.

## Open questions

1. Several matching conditions on one error (`extensions.code` and `extensions.entity`) for servers that reuse one code
   inside one operation. Not needed until someone asks.
2. Non-string discriminators (numeric codes).
3. A type used by both GraphQL and REST with a custom `field` (see §4).

## Later

- `@glCaptureErrors`: expose matched entries as typed objects next to the raw `errors`.
- Third-party mutation payloads with `userErrors: [UserError!]!`: a rule such as `@glThrowIf(field: "userErrors")`.
- Optional `errorStyle: result` per client target (sealed result instead of throwing).
- Errors on nested fields and in subscriptions.

## Related plans

- `capture-errors.md` (`@glCaptureErrors`): the no-throw mode, must coexist (§4).
- `domain-actions.md`, `input-mapping-extensions.md`: the v7 schema-driven model work. Errors are independent of them.
