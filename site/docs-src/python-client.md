---
title: "Python GraphQL Client Generator"
description: "Generated Python GraphQL and REST client: pydantic v2 models, asyncio methods, AsyncIterator subscriptions, httpx and websockets adapters, caching."
---

# Python Client

A fully typed GraphQL client generated from your schema. Types, inputs and enums are
[pydantic](https://docs.pydantic.dev) v2 models, every operation is an `async` method, and the
transport is a single injectable `async` function, so you can use `httpx` (generated for you), `aiohttp`,
or a test double.

Requires Python 3.10+ and `pydantic >= 2.10`. The default adapters need `httpx >= 0.27` and
`websockets >= 14`; they are only imported by the generated adapter files, so with
`"httpAdapter": "none"` and `"wsAdapter": "none"` pydantic is the only dependency.

## Configuration

Set `"mode": "client"` and add a `"python"` key under `clientConfig`:

=== "JSON"

    ```json title="glink.json"
    {
      "schemaPaths": ["schema/*.graphql"],
      "mode": "client",
      "outputDir": "myapp/graphql",
      "clientConfig": {
        "python": {
          "generateAllFieldsFragments": true,
          "autoGenerateQueries": true,
          "immutableTypeFields": true,
          "httpAdapter": "httpx",
          "wsAdapter": "websockets"
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml"
    schemaPaths:
      - schema/*.graphql
    mode: client
    outputDir: myapp/graphql
    clientConfig:
      python:
        generateAllFieldsFragments: true
        autoGenerateQueries: true
        immutableTypeFields: true
        httpAdapter: httpx
        wsAdapter: websockets
    ```

The output directory is a Python package (`__init__.py` re-exports everything). All options are listed in the
[configuration reference](configuration.md#clientconfigpython).

## Using the client

```python
import asyncio
from myapp.graphql import GraphLinkClient

async def main() -> None:
    client = GraphLinkClient.with_http(
        url="https://api.example.com/graphql",
        ws_url="wss://api.example.com/graphql",
        headers_provider=lambda: {"Authorization": "Bearer token"},  # sync or async
    )
    res = await client.queries.get_user(id="user-1")
    print(res.get_user.name)

asyncio.run(main())
```

Operation methods take keyword-only arguments named like the schema arguments in `snake_case`
(`client.mutations.update_user(id="1", input=UpdateUserInput(name="x"))`). The result object is named after
the operation and exposes each root field as an attribute (`res.get_user`).

### Bring your own adapter

The client only needs a coroutine that takes the JSON payload and returns the response body:

```python
async def adapter(payload: str) -> str:
    async with aiohttp.ClientSession() as session:
        async with session.post(URL, data=payload, headers={"Content-Type": "application/json"}) as r:
            return await r.text()

client = GraphLinkClient(adapter=adapter, ws_adapter=my_ws_adapter)
```

With `operationNameAsParameter: true` the adapter also receives the operation name as a second argument.
`ws_adapter` is required when the schema has subscriptions (subclass `GraphLinkWebSocketAdapter`, or use the
generated `DefaultGraphLinkWebSocketAdapter`).

## Models

- Fields are `snake_case`; the GraphQL name is kept as the pydantic alias, so `model_dump(by_alias=True)` /
  `to_json()` produce the wire format and `Model(first_name=...)` and `Model.from_json({"firstName": ...})` both work.
- Models are frozen unless `immutableTypeFields` is `false`.
- Nullable fields default to `None`, unless `nullableFieldsRequired` is `true`. Schema defaults become pydantic defaults.
- Interfaces and unions are base models: validating a dict that carries `__typename` returns the concrete class,
  and an unknown `__typename` raises `ValueError`.
- Python keywords and pydantic attribute names are escaped with a trailing underscore (`class` → `class_`).

## Enums

Enums are `str`-backed `Enum`s with `SCREAMING_SNAKE` members that keep the wire value. Unless `strictEnums` is
`true`, a value the schema does not declare decodes to `unknownValue__` instead of raising, and
encoding that member raises `ValueError`.

## Subscriptions

Subscriptions are async generators:

```python
async for event in client.subscriptions.user_status_changed(user_id="user-1"):
    print(event.user_status_changed.status)
```

Breaking out of the loop (or cancelling the task) completes the subscription. All subscriptions share one
WebSocket connection; the default adapter reconnects with exponential backoff and re-subscribes.

## Custom scalar codecs

A scalar can map to a Python type with `fromJson` and `toJson` expressions, where `{}` stands for the value:

```json
"typeMappings": {
  "Opaque": {
    "type": "str",
    "jsonType": "String",
    "fromJson": "\"opaque:\" + {}",
    "toJson": "{}[7:]"
  }
}
```

`jsonType` names the JSON type the server sends: `String`, `Int`, `Double`, `Bool`, `Map` or `List`. It is
different from `type`, which is the Python type your code uses. With `jsonType`, the generated decoder checks the field with `graph_link_json.expect_str`, `expect_int`, `expect_float`, `expect_bool`, `expect_dict` or `expect_list` and passes a value of the matching type to `fromJson`.
A `null`, missing or wrong-typed value is raised as an error naming the field and the expression never runs; on a
nullable field `null` stays `null`.

Without `jsonType`, `{}` is whatever the JSON parser produced, and an expression such as `{}[7:]` fails with an arbitrary exception on a value of another type. The check raises a `TypeError`.

`jsonType` only checks the value that arrives; an expression that can fail on a valid wire value still has to
handle that itself. A codec with no `fromJson` is a plain type alias and ignores `jsonType`.

## Errors

!!! danger "Behavior change in v6.0.0"
    A GraphQL call whose response has no `data` and no `errors`, or whose HTTP status is not 2xx and carries no
    GraphQL body (a gateway page, `{"error": "unauthorized"}`), now raises `GraphLinkException`, like a server-side
    GraphQL error. It used to return `None`. `GraphLinkError` has two new optional fields, `status` and `body`. A
    response with `"errors": []` is a success, and a leading UTF-8 byte order mark is ignored.

Operations raise `GraphLinkException` (its `.errors` is the list of `GraphLinkError`) when the response contains GraphQL
errors. Mark an operation with `@glCaptureErrors` (or set `captureErrors: true`) to get a `…FullResponse` with `data` and
`errors` instead.

## Caching

`@glCache` and `@glCacheInvalidate` behave as in the other clients (see [Caching](caching.md)). The default store is
in-memory; implement `GraphLinkCacheStore` (four `async` methods) and pass `store=` to persist it.

## File uploads

Upload arguments take `GLUpload` objects; the multipart request uses the GraphQL multipart request spec:

```python
from myapp.graphql import GLUpload

await client.mutations.upload_avatar(user_id="1", file=GLUpload.from_file("avatar.png"))
```

The default httpx adapter streams the multipart body (`gl_multipart_stream` in `graph_link_uploads.py`) instead of reading
each file into memory, and accepts async-iterable uploads. Progress is reported through `on_progress(sent, total)` and
is not called when the total size is unknown; an upload of unknown length is sent chunked.

## Persisted queries

`persistedQueries: "apq"` (and optionally `persistedQueriesUseGet`) work as described in
[Persisted Queries](persisted-queries.md). With GET enabled, `GraphLinkClient.with_http` wires the GET adapter;
when building the client yourself pass `get_adapter=`.

## REST operations

Fields of `Query` and `Mutation` annotated with `@glRest` are served over HTTP/JSON through this same client, with the same call syntax as GraphQL operations. See [REST operations](rest-client.md#python) for the directive, argument roles, responses, caching and the adapter.
