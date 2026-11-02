# GraphLink — REST Operations Specification

How a generated client calls REST endpoints from the same schema, the same client object and the same cache as its
GraphQL operations. Reference implementation: Dart. Companion of `client-specs.md` (same MUST / SHOULD / MAY keywords).

The goal is adoption: a project can keep its REST services behind typed GraphLink methods today and move an operation
to GraphQL later by deleting its `@glRest*` directives. Call sites do not change.

All behaviour below is resolved in the IR. Generators and serializers consume resolved data and never look at
prefixes, extension blocks or parent declarations.

---

## 1. Principles

1. **Mixed by design.** An operation is REST when it carries `@glRest` or is declared inside an `extend type Query|Mutation`
   block carrying `@glRestPrefix`. Every other operation stays GraphQL. There is no `protocol` setting.
2. **One client.** REST and GraphQL operations are exposed on the same `queries` / `mutations` groups, share the cache store
   and the tag space, and are constructed together. Subscriptions are always GraphQL.
3. **Explicit roles.** Every argument of a REST operation has exactly one role, visible at the declaration (Retrofit style).
   The only implicit role is a path variable named like a `{placeholder}` of the URL.
4. **Defaults are filled by a pass**, not computed by consumers. After the pass every REST operation holds a resolved method,
   path, body kind and role per argument.
5. **Errors, not guesses.** Anything ambiguous is a generation error whose message states the fix.

## 2. Directives

| Directive | Location | Arguments | Role |
|---|---|---|---|
| `@glRest` | `Query` / `Mutation` field | `path: String!`, `method: RestMethod`, `contentType: String`, `accept: String`, `response: RestResponseKind`, `responsePath: String` | Marks the operation REST |
| `@glRestPrefix` | `extend type Query\|Mutation` | `path: String!`, `method: RestMethod` | Shared path start and method for the fields of the block |
| `@glRestPath` | argument | `name: String` | Path variable; `name` only to rename |
| `@glRestParam` | argument | `name: String`, `encoding: RestEncoding` | Query parameter, or an input object's fields as query parameters |
| `@glRestHeader` | argument, input definition | `name: String` | Header, or an input object's fields as headers |
| `@glRestBody` | argument | — | The request body: JSON for an input object or list of them, raw bytes for an `Upload` (the argument's type decides) |
| `@glRestField` | argument | `name: String`, `encoding: RestEncoding` | Form field (`application/x-www-form-urlencoded`) |
| `@glRestPart` | argument | `name: String`, `encoding: RestEncoding` | Multipart part (`multipart/form-data`) |
| `@glRestDiscriminator` | interface, union | `field: String!`, `values: {Type: "value"}` | Polymorphic response decoding (section 9) |
| `@glDownload` | scalar definition | — | Binary response (section 8) |
| `@glVoid` | scalar definition | — | Response whose body is ignored (section 7) |

Enums: `RestMethod { GET POST PUT PATCH DELETE }`, `RestEncoding { FLAT JSON SPREAD }`, `RestResponseKind { JSON TEXT BINARY }`.
All names are registered in `model/built_in_dirctive_definitions.dart`. GraphQL operations ignore every directive in this table.

`name` is optional wherever the argument name is already the wire name. `@glRestHeader` on a **scalar** argument requires `name`.

## 3. Operation resolution (the defaulting pass)

Runs once in the client branch of `validateSemantics()`, right after `checkGLExpandDirectives` and before
`forceCyclicEdgesNullable`, so cycles are relaxed whenever a REST operation exists.

0. **Prefix propagation happens at parse time.** Extension blocks are merged by type name, which loses which block a field came
   from. When a type definition carries `@glRestPrefix`, the parser copies it onto each field of that block and removes it from the
   type (`pushRestPrefixToFields`). Two blocks with different prefixes therefore never collide.

1. **Method:** the field's `@glRest(method:)`, else the prefix `method`, else `GET` for a query and `POST` for a mutation.
   `@glRest` may always override the prefix.
2. **Path:** prefix path joined to the field path with exactly one `/` (`/service/` + `/x` → `/service/x`). A field inside a
   prefix block without `@glRest` uses the prefix path alone. A field may not escape its prefix; use another block.
3. **Placeholders** of the joined path are collected. Each MUST bind to exactly one argument: an argument with the same name,
   or one carrying `@glRestPath(name: "<placeholder>")`. An unbound placeholder, or a path argument that is nullable, is an error.
   The pass **injects** `@glRestPath` into the IR on every argument whose name equals a placeholder, so later stages only see
   explicit roles. An explicit `@glRestPath` whose name (or `name:`) matches no placeholder is an error.
4. **Roles** are assigned to every remaining argument from its directive. An argument without a role is an error:
   "argument `limit` of `products` needs `@glRestParam`, `@glRestHeader`, `@glRestBody`, `@glRestField` or `@glRestPart`".
5. **Body kind** is inferred: `@glRestBody` → JSON (RAW when the argument is an `Upload`), `@glRestField` → FORM, `@glRestPart` → MULTIPART.
   Mixing kinds is an error. An upload argument MUST be `@glRestPart`, or `@glRestBody` for a raw-bytes body.
6. `GET` and `DELETE` reject `@glRestBody`, `@glRestField` and `@glRestPart`.
7. At most one `@glRestBody` per operation.
8. A route is `(method, path with every placeholder replaced by {})`. Two REST operations with the same route are an error.
9. `@glRest` on a `Subscription` field, and `@glCaptureErrors` (directive form) on a REST operation, are errors.
   The global `captureErrors` setting applies to GraphQL operations only.
10. `@glRest` on a field whose return type contains an upload, or an upload nested in an input object, is an error.
    Uploads are only top-level arguments, as a single value or a list (never a matrix).

Resolved data lives in `GLParser.restOperations` (`Map<GLOperationKey, GLRestOperation>`), a model separate from
`GLQueryDefinition` (which models GraphQL operation documents): `field`, `type`, `method`, `path`, `placeholders`, `bodyKind` and one
`GLRestArgument` per argument (`role`, `wireName`, `encoding`, `spreadFields`). Cache data is exposed as getters over the field's
directives (`cacheTtl`, `cacheTags`, `staleIfOffline`, `invalidateTags`, `invalidatesAll`). REST operations have no selection set
and are never added to `queries`.

## 4. Argument wire format

### 4.1 Scalar encoding

Every value is converted through its `toJson` form (enums → wire string, dates and custom scalars → their JSON string,
booleans → `true` / `false`), then percent-encoded where it lands in a URL. Null and absent optional values are **omitted**.
Defaults declared on arguments are applied by the generated method when the caller omits the value, and are sent (decided).

### 4.2 Path

`{placeholder}` is replaced by the percent-encoded value at call time. Segments are never re-encoded after substitution.

### 4.3 Query parameters (`@glRestParam`)

| Value | Encoding |
|---|---|
| scalar / enum | `name=value` |
| list of scalars | repeated key `name=a&name=b`; with `queryListStyle: COMMA` → `name=a,b` |
| input object | **SPREAD** by default: each field becomes its own key, the argument name is not sent |
| input object with `encoding: FLAT` | dotted keys prefixed by the argument/`name`: `filter.tag=a` |
| input object with `encoding: JSON` | one key whose value is the JSON text |
| list of objects, matrix | indexed keys, see 4.7 |

### 4.4 Headers (`@glRestHeader`)

Scalar argument: one header named `name`. Input-type argument: always spread, one header per field, named by the field's own
`@glRestHeader(name:)` or the field name verbatim. A list joins with commas. A null field is not sent. A nested object field is an
error. Placing `@glRestHeader` on an `input` definition makes every argument of that type a header group without annotating it.

### 4.5 JSON body (`@glRestBody`)

The argument's `toJson` is the entire body, unwrapped (never `{"argName": ...}`). Lists are plain JSON.

### 4.5.1 Raw-bytes body (`@glRestBody` on an `Upload`)

```graphql
uploadAvatar(id: ID!, file: Upload! @glRestBody): Void @glRest(path: "/users/{id}/avatar", method: PUT)
```

- The argument's type decides the body kind: an `Upload` can never be JSON, so `@glRestBody` on it means RAW. The body is the
  file's bytes and nothing else (no envelope, no boundary).
- The argument is the existing `GLUpload` (Dart `GLUpload`, Java `GLUpload`): a byte stream or bytes, optional `length`, optional
  `filename`, `mimeType` (default `application/octet-stream`). `fromBytes` takes `Uint8List` (Dart) / `byte[]` (Java).
- `Content-Type` is the upload's `mimeType`; `@glRest(contentType:)` overrides it. `Content-Length` is set when `length` is
  known, otherwise the request is chunked. The body is streamed, never buffered by the client.
- The filename is **not** sent. An API that needs it takes another argument (`@glRestHeader(name: "X-Filename")` or `@glRestParam`).
- A list of uploads as a raw body is an error (use `@glRestPart`). The `(sent, total)` progress callback applies.
- `POST` or `PUT`/`PATCH` only (section 3 rule 6); the response decodes by the normal rules (`201` with an object, `204`, …).

### 4.6 Form and multipart (`@glRestField`, `@glRestPart`)

Input objects take an `encoding`:

| Encoding | Default for | Result for `meta: {name, address:{city}}` |
|---|---|---|
| `FLAT` | `@glRestField`, `@glRestPart` | `meta.name`, `meta.address.city` (or `meta[name]`, `meta[address][city]` with `formNesting: BRACKET`) |
| `JSON` | — | one entry `meta` holding the JSON text; in multipart a part with `Content-Type: application/json` |
| `SPREAD` | — | `name`, `address.city`; an entry-name clash with another argument is an error |

Scalars are text entries; upload arguments are file parts named after the argument (a list repeats the name).
`FORM` entries are encoded `application/x-www-form-urlencoded`.
`@glRestParam` and `@glRestHeader` on an input default to SPREAD (map semantics); `@glRestField` and `@glRestPart` default to FLAT.

For SPREAD the IR resolves `spreadFields` (input field name → wire name). A field's own `@glRestParam(name:)`, `@glRestHeader(name:)`,
`@glRestField(name:)` or `@glRestPart(name:)` (the one matching the argument's role) renames its key; nested keys of FLAT objects always use
field names. Clashing wire names inside one operation (case-insensitive for headers) are an error.
`encoding` is accepted on input objects and on lists of any element type; `SPREAD` is not possible for a list; it is an error on scalars.

### 4.7 Lists in query strings, forms and multipart

- A list of scalars repeats the key.
- A list of objects and a list of lists use indexed keys: `items.0.name=x`, `m.0.1=3` (`items[0][name]`, `m[0][1]` in bracket mode).
- **At most two list levels** anywhere in a value, counting the argument's own list levels plus the deepest list levels of the
  input fields reached from it. Deeper is an error: "use `encoding: JSON` on this argument". A header allows one list level only.
- An empty list produces no key (empty and absent are indistinguishable); this is a documented limitation.

## 5. Request construction

- **Optional bodies.** `GLRestOperation.bodyIsOptional` is true when every argument feeding the body is nullable or has a default. A null
  or absent JSON or raw body means the request has no body and no `Content-Type` header; a JSON `null` literal is never sent. For
  forms and multipart, null entries are omitted, and when none remain the body is omitted as well.

- `Content-Type` is resolved in the IR (`GLRestOperation.contentType`): `application/json` for JSON bodies,
  `application/x-www-form-urlencoded` for forms, `multipart/form-data` for multipart (the adapter adds the boundary); null for a raw body
  (the upload's MIME type decides at runtime) and for requests without a body. `@glRest(contentType:)` overrides it for JSON and raw
  bodies only; on a form, a multipart or a bodyless request it is an error.
- `Accept` (`GLRestOperation.accept`): `application/json` by default, `text/plain` for `response: TEXT`, `*/*` for a download;
  `@glRest(accept:)` overrides it.
- Header arguments are merged over the defaults; an argument header wins.
- The URL is the resolved path plus the query string, relative to the base URL owned by the adapter.

## 6. Adapter contract

One function; the adapter owns base URL, auth, retries, timeouts, redirects and I/O. The generated client never inspects
transport details.

```
RestRequest  { method, path, query: List<(name,value)>, headers: Map<String,String>, body: RestBody?, onSendProgress? }
RestBody     = json(String) | form(List<(name,value)>) | multipart(List<RestPart>) | raw(GLUpload: stream, mime, length?)
RestPart     { name, value text | file(stream/bytes, filename?, mime, length?) , mime? }
RestResponse { status, headers, body: byte stream }
adapter      : RestRequest -> RestResponse        (async in the language's native model)
```

Dart: `Future<RestResponse> Function(RestRequest)`. `RestResponse` exposes `bytes()` / `text()` / `json()` helpers that buffer;
a download keeps the stream. The default adapter is generated (`restHttpAdapter`, default same library as `httpAdapter`; `none`
disables it). The adapter is injectable and may be absent when the schema has no REST operation. `withHttp(graphqlUrl:, restBaseUrl:)`
builds both default adapters.

## 7. Responses

| Return type | Decoding |
|---|---|
| object / list of objects | JSON, `fromJson` of the projected type; `responsePath: "data.items"` selects a nested value first |
| scalar / enum / list of scalars | JSON value |
| `String` with `response: TEXT` | body text as-is |
| `Void` (`scalar Void @glVoid`) | body ignored, any 2xx succeeds, no decoding; the method returns unit/void |
| nullable | empty body, `204` or a JSON `null` → `null` |
| `@glDownload` scalar | binary (section 8) |

- `Void` is valid only as the non-list return type of a REST operation (same placement rules as `Download`). Any use in a GraphQL
  operation fires an exception: a non-REST field returning it, a GraphQL document variable typed with it, or a document selecting a REST
  field that returns it. `Download` follows the same rule. takes no `response:` or
  `responsePath:`, and cannot be cached. Its response kind is `none` and `Accept` is `*/*`. Any non-2xx still raises `RestError`.
- `allowsEmptyBody` is true when the return type is nullable (always true for `Void`); a non-2xx status is never turned into `null`. A non-null return with an empty body is a decode error.
- `response:` is inferred: JSON by default, BINARY for a `@glDownload` return, TEXT only by declaration and only on a plain `String`.
  Declaring BINARY without a download, or JSON/TEXT on a download, is an error. `responsePath` is dot-separated keys, JSON responses only.
- A **non-2xx** status raises `RestError { status, headers, body (text), }`, catchable by type. Transport failures propagate unwrapped.
- Unknown JSON keys are ignored. A missing non-null field is a decode error naming the type and field.
- Enums follow `strictEnums` / `unknownValue__` exactly as in `client-specs.md` §6.

## 8. Files

`@glDownload` is valid only on a scalar, and a download is valid only as the non-list return type of a REST operation (not an argument,
not a field of a type or input, not a GraphQL operation). Returning an `@glUpload` scalar is rejected by the existing upload rules.

**Uploads.** `@glUpload` scalar unchanged. Single or list (never a matrix) as `@glRestPart` (file part, list repeats the name) or
`@glRestBody` (raw bytes). The mutation accepts the optional `(sent, total)` progress callback.

**Downloads.** `scalar Download @glDownload`. `Download` is the mirror of `GLUpload`: byte stream, `bytes()` helper, `filename`
(from `Content-Disposition`), `contentType`, `length?`. The response is never buffered by the client, never cached, and decoded
without JSON. The operation accepts an optional `(received, total)` progress callback. `@glCache` on a `Download` return is an error.

## 9. Interfaces and unions

```graphql
interface Pet @glRestDiscriminator(field: "kind") { id: ID! }
union SearchHit @glRestDiscriminator(field: "type", values: {Dog: "dog", Cat: "cat"}) = Dog | Cat | Owner
```

- The value belongs to the pair (parent, member): `values` lives on the parent; a member missing from `values` uses its type name;
  two members with the same value are an error.
- `fromJson` order: (1) `__typename`, when present and a known member; (2) the discriminator key, looked up in the parent's map;
  (3) failure naming the parent and the value (or the missing key). The discriminator branch is emitted **only** for parents that
  declare the directive, so GraphQL-only output is unchanged.
- The discriminator is read from a top-level key of the object. If it is also a schema field it stays a normal field.
- Resolved discriminators live in `GLParser.restDiscriminators`, keyed by the parent's name (`field`, `valueByType`, derived
  `typeByValue`). A union is resolved from its own directive, so `convertUnionsToInterfaces` needs no change and the converted
  interface is found under the same name.
- A REST operation whose return type reaches (through fields, at any depth, and through the implementors of reached interfaces) an
  interface or union without `@glRestDiscriminator` is a generation error naming it.
- `@glRestDiscriminator` on anything other than an interface or union is an error.

## 10. Types in the IR

REST return types are registered in `projectedTypes` after validation, by **blind registration** (the all-fields path of
`createProjectedTypes`), not rebuilt:

1. The declared type is registered under its bare name, together with everything reachable from it (nested objects, enums,
   interfaces and their implementors), taking every non-`@glSkipOnClient` field.
2. Registration is memoised by type name: two REST operations returning the same type, or a REST operation and an auto-generated
   GraphQL operation, share one generated type.
3. A bare name always means the full declared shape. A hand-written GraphQL operation with a partial selection gets a generated
   name (`Product_Name`), so a collision is impossible.
4. Cyclic edges MUST already be nullable. `forceCyclicEdgesNullable` runs when `generateAllFieldsFragments` is on **or** the schema has
   a REST operation.
5. REST operations are not in `queries`, so the GraphQL-only passes (fragment refs, projection validation, hoisted arguments,
   query text, APQ) never see them. `autoGenerateQueries` skips REST fields explicitly, and a hand-written GraphQL document that
   selects a REST field is an error.
6. Registration is `registerRestResponseTypes()`, run right after `createProjectedTypes()`, using the blind registration of the
   projection extension (`registerDeclaredTypeAsProjected`).

## 11. Caching

`@glCache`, `@glNoCache`, `@glCacheInvalidate` work on REST operations. The existing global checks (ttl as seconds or duration string,
tag syntax, an invalidated tag must be declared by some `@glCache`) already cover them because they run over all parsed directive
values; this is what makes the tag space shared across both transports. REST adds placement rules: only `GET` queries can be
cached, `@glNoCache` and `@glCache` are rejected on mutations, `@glCacheInvalidate` only on mutations, `@glCache` with `@glNoCache` is a
conflict. `defaultCacheTTL` applies to `GET` queries that declare neither directive; `disableCache` strips them.

- Key: `fnv1a32("<fieldName>:<json of all arguments sorted by name>")`, same function and format as `client-specs.md` §12.
- Entry: `{"data": <JSON text of the decoded response value>, "expiry": <epoch ms>}`; `ttl` in seconds.
- Store, tags (`__tag__` prefix, per-tag lock) and invalidation are the same objects as the GraphQL path, so a GraphQL mutation
  can invalidate a tag held by a REST query and the reverse.
- A REST query is one root field: no query division. Cache hit → no request. Miss → request, store only on 2xx with non-null data.
- `staleIfOffline`: only a **transport failure** serves stale data. A `RestError` is a response and is never masked.
- Mutation invalidation runs after a 2xx response.

## 12. Client surface

1. Same groups and method names as GraphQL (`queries.product(...)`, `mutations.deleteProduct(...)`); the transport is not visible
   in the signature.
2. Arguments: required = non-null without default; defaulted and nullable are optional. Upload and download operations add the
   optional progress callback.
3. Return value is the decoded value directly (`Future<T>`); `void` operations return unit.
4. Constructor takes the GraphQL adapter and the REST adapter, each required only when the schema contains that kind of operation.

## 13. Configuration

| Key | Default | Effect |
|---|---|---|
| `restHttpAdapter` | language default | `none` disables the generated default REST adapter |
| `queryListStyle` | `REPEAT` | `COMMA` joins list query parameters |
| `formNesting` | `DOT` | `BRACKET` uses `a[b]` instead of `a.b` |

There is no setting that turns REST on: directives do.

## 14. Validation summary (all generation errors, with the fix in the message)

unbound placeholder · nullable path argument · argument without role · mixed body kinds · more than one `@glRestBody` ·
body role on GET / DELETE · duplicate route · `@glRest` on a subscription · `@glCaptureErrors` on a REST operation ·
upload outside a top-level argument or as a matrix · more than two list levels in form / query / multipart · SPREAD name clash ·
nested object in a header group · duplicate discriminator value · `@glCache` on a download or a non-GET operation.

## 15. Tests (each feature ships with its proof)

Every row needs: an inline-schema generator test under `test/rest/` asserting IR and generated output, a mock-adapter test in
`integration_tests/mock/<lang>_client_tests/`, and a real-server test against a hand-written server for the areas marked ★.

| Area | Must be proven |
|---|---|
| Resolution | method defaults; prefix + field path join; field method overrides prefix; fields without `@glRest` in a prefix block; unbound placeholder; duplicate route |
| Path | substitution, percent-encoding, renamed placeholder via `@glRestPath`, prefix placeholders, nullable path error ★ |
| Query | scalar, list repeat / comma, input SPREAD / FLAT / JSON, null omitted, default applied, matrix indexed, three levels rejected ★ |
| Headers | scalar header, input group, `@glRestHeader` on an input definition, list join, null omitted ★ |
| JSON body | unwrapped input, list body, content-type override ★ |
| Raw body | `Upload` as `@glRestBody`: bytes and stream, MIME as `Content-Type`, `Content-Length` when known and chunked otherwise, filename not sent, list of uploads rejected, progress callback ★ |
| Form | FLAT dot / bracket, SPREAD clash, JSON, repeated list keys, indexed list of objects ★ |
| Multipart | file part, list of files, FLAT / JSON / SPREAD objects, text parts, progress callback, upload nested in input rejected ★ |
| Downloads | stream, `filename` / `contentType`, progress, not cached, `@glCache` rejected ★ |
| Responses | object, list, `responsePath`, `TEXT`, `void` + 204, empty body on non-null, RestError with status, transport error unwrapped ★ |
| Types | blind registration shares types with GraphQL ops, transitive copy, cycles nullable without `generateAllFieldsFragments`, partial selection gets a generated name |
| Polymorphism | `__typename` first, discriminator fallback, `values` map, default value = type name, duplicate value rejected, unknown value error, union directive carried through conversion, GraphQL-only output byte-identical |
| Cache | hit, miss, expiry, tags, cross-transport invalidation (GraphQL mutation → REST query and back), `staleIfOffline` on transport failure only, key stability ★ |
| Mixed | one client with both adapters; absent adapter when the schema has no such operations; subscriptions untouched |
| Errors | each entry of section 14 has a test asserting the message |

## 16. Documentation

`site/docs-src/rest-client.md` (directives, roles, encodings, adapter contract, Known limitations), rows in `configuration.md` and
`index.md`, `llms` headers, `CHANGELOG.md`, `ARCHITECTURE.md`/`CLAUDE.md` map entries (`parser_extensions/gl_grammar_rest_extension.dart`),
`plans/rest-client.md`.

**Known limitations to document:** empty lists are indistinguishable from absent in forms and query strings; two list levels
maximum outside JSON encoding; scalar or raw-string JSON bodies are not expressible; discriminator is a top-level key; indexed
notation depends on server conventions (e.g. array index limits in some parsers).

## 17. Open points

1. `@glRestParam` / `@glRestHeader` on an input default to SPREAD while `@glRestField` / `@glRestPart` default to FLAT (confirmed).
2. The `void` scalar is assumed to be the existing `scalar void @glExternal(glClass: "void")`; verify it maps cleanly in Dart.
