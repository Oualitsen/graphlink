---
title: "REST Operations in a GraphQL Client"
description: "Serve some Query and Mutation fields over plain HTTP/JSON from the same schema and the same generated client: @glRest, argument roles, encodings, responses, caching and the adapter contract."
---

# REST Operations

Annotate a root field with `@glRest` and the generated client calls it over HTTP/JSON instead of GraphQL. The schema, the
types and the client are the same, so you can move an API from REST to GraphQL one field at a time: remove the directive
and the call site does not change.

!!! note
    REST operations are generated for the **Dart**, **TypeScript**, **Java** (blocking and reactive), **Kotlin**, **Python**, **Swift** and **Go** clients. Other client targets ignore them for now.

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
- Downloads return a `GLDownload` whose `stream` is a web `ReadableStream`. The fetch adapter streams uploads and downloads. The axios
  adapter buffers responses but streams uploads on Node (a `Readable` body); in the browser XHR cannot stream, so it passes a `Blob`
  or `FormData` through and a `ReadableStream` upload throws. Upload progress is only reported when the total size is known.
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

## Java

Methods are plain positional methods; pass `null` for an omitted optional argument (a declared default is applied when it is `null`).
Operations that upload get an overload with a trailing `UploadProgressCallback`, and downloads one with a `DownloadProgressCallback`:

```java
GraphLinkClient client = new GraphLinkClient(
    "https://api.example.com/graphql",
    "https://api.example.com",
    () -> Map.of("Authorization", "Bearer " + token),
    encoder, decoder);
Product product = client.queries.product("p1", null);
client.mutations.avatar("p1", GLUpload.fromFile(new File("p1.png")), (sent, total) -> {});
```

- The generated `DefaultGraphLinkRestAdapter` uses the JDK `HttpClient` (`restHttpAdapter: "none"` skips it and the factories take a
  `GLRestAdapter`). It streams uploads and downloads; a `GLUpload` with a negative `length` is sent chunked and reports no progress.
- Errors: `RestError` (`getStatus()`, `getHeaders()`, `getBody()`); an empty body for a non-null result is an `IllegalStateException`,
  a missing non-null field an `IllegalArgumentException` naming the type and field. A transport failure is never a `RestError`.
- `void` operations (`Void`) return nothing. `GLDownload` wraps an `InputStream`; close it or call `bytes()`.
- JSON goes through your `GraphLinkJsonEncoder` / `GraphLinkJsonDecoder` (the Jackson codec is generated with `jsonCodec: "jackson"`).
- Nested object keys in a query string come out in alphabetical order (`groups.0.ids` before `groups.0.name`).

### Reactive

With `asyncStyle` set (see [Java client](java-client.md#reactive-client-v500)), REST operations return the library's deferred
type instead and `GLRestAdapter.execute` returns the same type wrapping `RestResponse`. The request is built identically to the
blocking client.

| `asyncStyle` | Result | Nullable result | `Void` result |
|---|---|---|---|
| `"reactor"` | `Mono<T>` | `Mono<T>`, empty when there is no value | `Mono<Void>` |
| `"rxjava3"` | `Single<T>` | `Maybe<T>` | `Completable` |
| `"mutiny"` | `Uni<T>` | `Uni<T>`, `null` item when there is no value | `Uni<Void>` |

- Nothing is sent until you subscribe.
- A nullable result that comes back empty (`204`, or an empty body) completes without a value (`null` with Mutiny); for a non-null
  result it is an `IllegalStateException` error signal. `RestError` is an error signal too, and `staleIfOffline` is served on a
  transport error signal only. A cached nullable query that comes back empty is not cached.
- By default the generated adapter uses the JDK `HttpClient.sendAsync`, for every `asyncStyle`.
- With `reactiveHttpClient: "webclient"` (`asyncStyle: "reactor"` only) the REST adapter uses Spring `WebClient` too. It streams
  uploads (a `GLUpload` with a negative `length` is sent chunked) and downloads, follows redirects and decodes `gzip` and `deflate`
  like the JDK adapter. It needs `spring-webflux` and `reactor-netty-http` on the classpath. Pass your own `WebClient` to the
  three-argument constructor to configure timeouts, a proxy or another connector (then redirects are up to that `WebClient`).

## Python

Methods are `async` with keyword-only arguments:

```python
client = GraphLinkClient.with_http(
    url="https://api.example.com/graphql",
    rest_base_url="https://api.example.com",
    headers_provider=lambda: {"Authorization": f"Bearer {token}"},
)
product = await client.queries.product(id="p1")
await client.mutations.avatar(id="p1", file=GLUpload.from_file("p1.png"), on_progress=lambda sent, total: None)
```

- The generated `GraphLinkRestHttpxAdapter` uses `httpx` and follows redirects (`restHttpAdapter: "none"` skips it and `with_http`
  takes a `rest_adapter`). The adapter is any `async (RestRequest) -> RestResponse` callable. A schema with only REST operations
  needs no GraphQL adapter: `GraphLinkClient(rest_adapter=...)`.
- Errors: `RestError` (`status`, `headers`, `body`); an empty body for a non-null result is a `ValueError`, a missing non-null field
  a pydantic `ValidationError` naming the model and field, an unknown discriminator a `ValidationError` naming the parent and value.
- Uploads stream in 64 KB chunks: `GLUpload.from_file(path)` reads from disk as it sends and `GLUpload.from_stream(source, length=...)` takes any
  (async) iterable of bytes. With a known length the request carries `Content-Length`; without one it is sent chunked and no progress is reported.
  Raw and multipart REST bodies stream, and so do GraphQL multipart uploads.
  A `GLDownload` exposes an async `stream` of chunks and `bytes()`.

## Swift

Methods are `async throws` with labelled, defaulted parameters:

```swift
let client = GraphLinkClient.create(
    url: URL(string: "https://api.example.com/graphql")!,
    restBaseUrl: URL(string: "https://api.example.com")!,
    headersProvider: { ["Authorization": "Bearer \(token)"] }
)
let product = try await client.queries.product(id: "p1")
try await client.mutations.avatar(id: "p1", file: GLUpload(data: data, mimeType: "image/png"), onProgress: { sent, total in })
```

- The generated `DefaultGraphLinkRestAdapter` uses `URLSession` (`restHttpAdapter: "none"` skips it and `create` takes a
  `restAdapter: GLRestAdapter`). A schema with only REST operations needs no GraphQL adapter: `GraphLinkClient(restAdapter: ...)`.
- Errors: `RestError` (`status`, `headers`, `body`); an empty body for a non-null result is a `RestDecodeError`. Decoding uses the
  regular generated `fromJson`, so a response that breaks the schema (a missing non-null field, an unknown discriminator value) traps,
  exactly as it does for GraphQL: declare a field nullable if the server may omit it.
- A `GLUpload` pulls its bytes lazily (`init(data:)`, `init(fileURL:)`, or `init(length:chunks:)` over any async sequence) and is streamed;
  `length: nil` is sent chunked and reports no progress. A `GLDownload` exposes an `AsyncThrowingStream<Data, Error>`.
- Keys of nested objects in query strings, forms and multipart parts are written in alphabetical order, and floats print as `3.0`.

## Go

Methods take a `context.Context`, the required arguments, and an optional `...<Operation>Options` struct holding the optional
arguments and the progress callbacks:

```go
client, _ := generated.NewGraphLinkClientWithHttp(generated.GraphLinkHttpOptions{
    URL:         "https://api.example.com/graphql",
    RestBaseURL: "https://api.example.com",
    HeadersProvider: func(ctx context.Context) (map[string]string, error) {
        return map[string]string{"Authorization": "Bearer " + token}, nil
    },
})
product, err := client.Queries.Product(ctx, "p1")
err = client.Mutations.Avatar(ctx, "p1", generated.GLUploadFromBytes(data, "p1.png", "image/png"),
    generated.AvatarOptions{OnProgress: func(sent, total int64) {}})
```

- The generated `GraphLinkRestHttpAdapter` uses `net/http` (`restHttpAdapter: "none"` skips it and `GraphLinkHttpOptions` takes a
  `RestAdapter`). A schema with only REST operations needs no GraphQL adapter.
- Errors are returned, never panicked: `*RestError` (`Status`, `Headers`, `Body`) for non-2xx; an empty body for a non-null result is a
  plain error, and a missing non-null field is an error from the type's `UnmarshalJSON` (`Type.field is missing or null in the response`).
- A `GLUpload` is an `io.Reader`; `Length: -1` streams chunked and reports no progress. A `*GLDownload` wraps the response body: read it or call `Close()`.
- Floats print as Go does (`3`, not `3.0`); `nil` results are returned as nil pointers or nil slices.

## Known limitations

- Dart, TypeScript, Java, Kotlin, Python, Swift and Go clients only.
- An empty list and an absent list are indistinguishable on the wire.
- Subscriptions are always GraphQL.
- Void is not yet supported by the server generators.
