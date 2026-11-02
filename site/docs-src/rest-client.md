---
title: "REST Operations in a GraphQL Client"
description: "Serve some Query and Mutation fields over plain HTTP/JSON from the same schema and the same generated client: @glRest, argument roles, encodings, responses, caching and the adapter contract."
---

# REST Operations

Annotate a root field with `@glRest` and the generated client calls it over HTTP/JSON instead of GraphQL. The schema, the
types and the client are the same, so you can move an API from REST to GraphQL one field at a time: remove the directive
and the call site does not change.

!!! note
    REST operations are generated for the **Dart**, **TypeScript** and **Kotlin** clients. Other client targets ignore them for now.

```graphql
scalar Void @glVoid

type Query {
  ping: String
}

extend type Query @glRestPrefix(path: "/products") {
  products(filter: Filter @glRestParam, page: Int = 1 @glRestParam): [Product!]! @glRest(path: "")
  product(id: ID!): Product @glRest(path: "/{id}")
}

extend type Mutation @glRestPrefix(path: "/products") {
  createProduct(input: ProductIn! @glRestBody): Product! @glRest(path: "", method: POST)
  deleteProduct(id: ID!): Void @glRest(path: "/{id}", method: DELETE)
}
```

```dart
final product = await client.queries.product(id: 'p1');
await client.mutations.createProduct(input: ProductIn(name: 'Pen'));
```

`method` defaults to `GET` for queries and `POST` for mutations. `@glRestPrefix(path:, method:)` on an `extend type` block
prefixes every field of the block; a field's own `path` is appended and its own `method` wins.

## Argument roles

Every argument that is not a `{placeholder}` of the path needs a role. A missing role is a generation error that names the
argument.

| Directive | Sent as |
|---|---|
| `@glRestPath(name?)` | Path segment. Added automatically when the argument name matches a `{placeholder}`. Must be a non-null scalar or enum. |
| `@glRestParam(name?, encoding?)` | Query string |
| `@glRestHeader(name?)` | Header. A scalar needs `name`; an input object spreads one header per field. Put it on the `input` definition to make every argument of that type a header group without annotating it. |
| `@glRestBody` | The whole JSON body, unwrapped. On an `Upload` it is the raw file bytes. |
| `@glRestField(name?, encoding?)` | Entry of an `application/x-www-form-urlencoded` body |
| `@glRestPart(name?, encoding?)` | Part of a `multipart/form-data` body; `Upload` arguments are file parts |

The body kind follows from the roles: `@glRestBody` is JSON (or raw for an `Upload`), `@glRestField` is a form,
`@glRestPart` is multipart. Mixing them, or using a body role on `GET` or `DELETE`, is an error.

### Encodings

An input object argument takes an `encoding`:

| Encoding | Default for | Result for `meta: {name, address: {city}}` |
|---|---|---|
| `SPREAD` | `@glRestParam`, `@glRestHeader` | `name=…&address.city=…` (the argument name is not sent) |
| `FLAT` | `@glRestField`, `@glRestPart` | `meta.name=…&meta.address.city=…` |
| `JSON` | — | `meta={"name":…}` (a `application/json` part in multipart) |

A list of scalars repeats the key (`tag=a&tag=b`, or `tag=a,b` with `queryListStyle: "COMMA"`). A list of objects or of lists
uses indexed keys (`items.0.name=x`); with `formNesting: "BRACKET"` the keys read `items[0][name]`. At most two list levels
are allowed in one value; use `encoding: JSON` beyond that. An empty list sends nothing. `null` and omitted arguments are not
sent, defaults are.

## Responses

| Return type | Decoding |
|---|---|
| object, list, scalar, enum | JSON; `responsePath: "data.items"` selects a nested value first |
| `String` with `response: TEXT` | The body as is |
| `Void` (`scalar Void @glVoid`) | Any 2xx, body ignored; the method returns `Future<void>` |
| `Download` (`scalar Download @glDownload`) | A streamed `GLDownload` (`stream`, `bytes()`, `filename`, `contentType`, `length`); takes an `onReceiveProgress` callback |

A nullable return type becomes `null` on an empty body or `204`; a non-null one throws a `FormatException`. A non-2xx status
always throws `RestError` (`status`, `headers`, `body`) and is never turned into `null`. Transport failures propagate as they are.

Interfaces and unions returned by a REST operation need a discriminator, because REST has no `__typename`:

```graphql
interface Pet @glRestDiscriminator(field: "kind") { id: ID! }
union Hit @glRestDiscriminator(field: "type", values: {Dog: "dog", Cat: "cat"}) = Dog | Cat
```

`Void` and `Download` are valid only as the return type of a REST operation.

## Caching

`@glCache`, `@glNoCache` and `@glCacheInvalidate` work on REST operations and share the cache store and the tag space with
GraphQL operations, so a GraphQL mutation can invalidate a tag held by a REST query and the reverse.

- Only `GET` queries are cached; `@glCacheInvalidate` is for mutations and runs after a 2xx response.
- `staleIfOffline` serves stale data on a **transport failure** only; a `RestError` is a response and is never masked.
- `defaultCacheTTL` applies to `GET` REST queries; `disableCache` strips the directives.

## The adapter

The client never touches the network. It builds a `RestRequest` (method, path, query, headers, body, upload progress) and
calls one function you provide:

```dart
typedef GLRestAdapter = Future<RestResponse> Function(RestRequest request);
```

`RestResponse` is `status`, `headers` and a byte `stream` with `bytes()`, `text()` and `json()` helpers. The adapter owns the
base URL, authentication, retries and timeouts.

`GraphLinkClient.withHttp(url: …, restBaseUrl: …)` builds the generated `package:http` (or Dio) adapters for you. Choose with
`restHttpAdapter`, or set it to `"none"` and pass `restAdapter:` yourself. A schema with only REST operations needs no GraphQL
`url` or `adapter`.

| Option | Default | |
|---|---|---|
| `restHttpAdapter` | same as `httpAdapter` | `"http"`, `"dio"` or `"none"` |
| `queryListStyle` | `"REPEAT"` | `"COMMA"` joins list values |
| `formNesting` | `"DOT"` | `"BRACKET"` uses `a[b]` |

## TypeScript

Same schema, same directives. Methods take the usual single `args` object and return promises (or `Observable`s with
`observables: true`):

```typescript
const client = new GraphLinkClient(
  createFetchAdapter('https://api.example.com/graphql'),
  createRestFetchAdapter('https://api.example.com', { headers: async () => ({ Authorization: `Bearer ${token}` }) }),
);
const product = await client.queries.product({ id: 'p1' });
await client.mutations.avatar({ id: 'p1', file: glUploadFromBlob(blob) }, (sent, total) => {});
```

- The adapter is `GLRestAdapter = (request: RestRequest) => Promise<RestResponse>`. `restHttpAdapter` picks the generated one
  (`createRestFetchAdapter` or `createRestAxiosAdapter(baseUrl, axios)`), or `"none"` to supply your own. A schema with only
  REST operations takes just the REST adapter: `new GraphLinkClient(restAdapter)`.
- Errors: `RestError` (`status`, `headers`, `body`); a missing non-null field or an empty body for a non-null result is a plain `Error`.
- Downloads return a `GLDownload` whose `stream` is a web `ReadableStream`. The axios adapter buffers request and response bodies,
  so it reports upload progress but does not stream; the fetch adapter streams.
- Floats are formatted by JavaScript (`3`, not `3.0`).

## Kotlin

Methods are `suspend` functions with named, defaulted parameters:

```kotlin
val client = GraphLinkClient.create(
    url = "https://api.example.com/graphql",
    restBaseUrl = "https://api.example.com",
    headersProvider = { mapOf("Authorization" to "Bearer $token") },
    encoder, decoder,
)
val product = client.queries.product(id = "p1")
client.mutations.avatar(id = "p1", file = GLUpload(stream, "image/png", length, "p1.png"))
```

- The generated `DefaultGraphLinkRestAdapter` uses OkHttp (`restHttpAdapter: "none"` skips it and the `create` factories take a
  `restAdapter: GLRestAdapter`). A `GLUpload` with `length = -1` is streamed chunked.
- Errors: `RestError` (`status`, `headers`, `body`); an empty body for a non-null result is an `IllegalStateException`, a missing
  non-null field an `IllegalArgumentException` naming the type and field.
- `GLDownload` wraps an `InputStream`; close it or call `bytes()`.
- JSON goes through your `GraphLinkJsonEncoder` / `GraphLinkJsonDecoder`, so they must handle nested maps and lists.

## Known limitations

- Dart, TypeScript and Kotlin clients only.
- An empty list and an absent list are indistinguishable on the wire.
- Subscriptions are always GraphQL.
- Void is not yet supported by the server generators.
