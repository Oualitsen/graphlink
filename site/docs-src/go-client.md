---
title: "Go GraphQL Client Generator"
description: "Generated Go GraphQL client: plain structs with json tags, context-aware methods returning (value, error), channel subscriptions, net/http and coder/websocket adapters, caching, uploads and persisted queries."
---

# Go Client

A fully typed GraphQL client generated from your schema. Types, inputs and enums are plain Go structs and string
types, every operation is a method taking a `context.Context` and returning `(value, error)`, and the transport is a
single injectable function, so you can use the generated `net/http` adapter, your own, or a test double.

Requires Go 1.22+. The generated package has no dependency beyond the standard library, except the default
WebSocket adapter, which uses [`github.com/coder/websocket`](https://github.com/coder/websocket). With
`"wsAdapter": "none"` nothing outside the standard library is imported.

## Configuration

Set `"mode": "client"` and add a `"go"` key under `clientConfig`:

=== "JSON"

    ```json title="glink.json"
    {
      "schemaPaths": ["schema/*.graphql"],
      "mode": "client",
      "outputDir": "internal/graphql",
      "clientConfig": {
        "go": {
          "packageName": "graphql",
          "generateAllFieldsFragments": true,
          "autoGenerateQueries": true,
          "httpAdapter": "nethttp",
          "wsAdapter": "coder"
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml"
    schemaPaths:
      - schema/*.graphql
    mode: client
    outputDir: internal/graphql
    clientConfig:
      go:
        packageName: graphql
        generateAllFieldsFragments: true
        autoGenerateQueries: true
        httpAdapter: nethttp
        wsAdapter: coder
    ```

Everything is generated into **one Go package** (`packageName`), flat in `outputDir`: GraphQL types may reference each
other in cycles, and Go does not allow import cycles between packages. All options are listed in the
[configuration reference](configuration.md#clientconfiggo).

## Using the client

```go
client, err := graphql.NewGraphLinkClientWithHttp(graphql.GraphLinkHttpOptions{
    URL:   "https://api.example.com/graphql",
    WsURL: "wss://api.example.com/graphql",
    HeadersProvider: func(ctx context.Context) (map[string]string, error) {
        return map[string]string{"Authorization": "Bearer token"}, nil
    },
})
if err != nil {
    return err
}

res, err := client.Queries.GetUser(ctx, "user-1")
if err != nil {
    return err
}
fmt.Println(res.GetUser.Name)
```

Operations live on `client.Queries`, `client.Mutations` and `client.Subscriptions`, named after the schema field in
`PascalCase`. Required arguments are positional; **optional arguments and arguments with a default** go in a trailing
`<Operation>Options` struct, which you can leave out:

```go
client.Queries.Greet(ctx)                                                   // defaults apply
client.Queries.Greet(ctx, graphql.GreetOptions{Name: graphql.Ptr("Bob")})   // override one
```

### Bring your own adapter

The client only needs a function that takes the JSON payload and returns the response body:

```go
adapter := func(ctx context.Context, payload string) (string, error) {
    request, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(payload))
    request.Header.Set("Content-Type", "application/json")
    response, err := myHTTPClient.Do(request)
    if err != nil {
        return "", err
    }
    defer response.Body.Close()
    body, err := io.ReadAll(response.Body)
    return string(body), err
}

client, err := graphql.NewGraphLinkClient(graphql.GraphLinkClientOptions{Adapter: adapter, WsAdapter: myWsAdapter})
```

With `operationNameAsParameter: true` the adapter also receives the operation name as a third argument.
`WsAdapter` is required when the schema has subscriptions (implement `GraphLinkWebSocketAdapter`, or use the generated
`DefaultGraphLinkWebSocketAdapter`).

## Types

- Fields are exported `PascalCase`; the GraphQL name lives in the `json` tag, so `encoding/json` produces and reads the wire format.
- **Nullable scalars, enums and objects are pointers** (`*string`, `*Address`); nullable lists and maps stay slices
  and maps (`nil` means `null`). Use `graphql.Ptr(value)` to build a pointer inline.
- Go struct literals have no default values. For an input with schema defaults the generator emits
  `NewConfigInput()`, which returns the struct with its defaults applied; a plain `ConfigInput{}` sends zero values.
  Defaults on **operation arguments** are applied by the method when the option is omitted.
- Interfaces and unions are Go interfaces (with an `Is<Name>()` marker). Decoding picks the concrete struct from
  `__typename` and returns it **by value**, so use a type switch: `switch m := item.(type) { case graphql.Photo: ... }`.
  An unknown `__typename` is a decoding error.
- A getter (`GetId()`) is generated for every interface field.
- Types with identity fields (`@glEqualsHashcode` or `identityFields`) get an `Equals` method.
- `nullableFieldsRequired` and `immutableTypeFields` have no effect in Go.

## Enums

Enums are `string` types with constants prefixed by the enum name (`graphql.UserStatusActive`). Unless `strictEnums`
is `true`, a value the schema does not declare decodes to `<Enum>UnknownValue__` instead of failing, and
encoding that value is an error.

## Subscriptions

A subscription returns a channel of events:

```go
events := client.Subscriptions.UserStatusChanged(ctx, "user-1")
for event := range events {
    if event.Err != nil {
        log.Println(event.Err) // does not close the channel; the adapter may reconnect
        continue
    }
    fmt.Println(event.Data.UserStatusChanged.Status)
}
```

Cancel the `ctx` to stop: the client tells the server and closes the channel. The channel also closes when the server
completes the subscription. All subscriptions share one WebSocket connection; the default adapter reconnects with
exponential backoff and re-subscribes. Use `AddReconnectListener` on it to observe reconnects.

## Errors

Operations return a `*GraphLinkException` (its `Errors` field is a `[]GraphLinkError`) when the response contains
GraphQL errors; use `errors.As` to read it. Mark an operation with `@glCaptureErrors` (or set `captureErrors: true`) to
get a `…FullResponse` with `Data` and `Errors` instead.

## Caching

`@glCache` and `@glCacheInvalidate` behave as in the other clients (see [Caching](caching.md)). The default store is
in-memory; implement `GraphLinkCacheStore` (four methods) and pass it as `Store` to persist it. Stores and the tag locks
are safe for concurrent use.

## File uploads

Upload arguments take `GLUpload` values; the multipart request follows the GraphQL multipart request spec:

```go
file, err := graphql.GLUploadFromFile("avatar.png", "image/png")
res, err := client.Mutations.UploadAvatar(ctx, "user-1", file, graphql.UploadAvatarOptions{
    OnProgress: func(sent, total int64) { fmt.Printf("%d/%d\n", sent, total) },
})
```

`GLUploadFromBytes` builds one from memory. The default adapter buffers the request body to know its total size, so
progress is exact; for very large files provide your own `GLMultipartAdapter`.

## Persisted queries

`persistedQueries: "apq"` (and optionally `persistedQueriesUseGet`) work as described in
[Persisted Queries](persisted-queries.md). With GET enabled, `NewGraphLinkClientWithHttp` wires the GET adapter; when
building the client yourself set `GetAdapter` in `GraphLinkClientOptions`.
