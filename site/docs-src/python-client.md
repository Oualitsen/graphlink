---
title: "Python GraphQL Client Generator"
description: "Generated Python GraphQL client: pydantic v2 models, asyncio methods with keyword-only arguments, AsyncIterator subscriptions, httpx and websockets adapters, caching, uploads and persisted queries."
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

## Errors

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

`progress` is reported through `on_progress(sent, total)`; the default httpx adapter reports the start and the end of
the request.

## Persisted queries

`persistedQueries: "apq"` (and optionally `persistedQueriesUseGet`) work as described in
[Persisted Queries](persisted-queries.md). With GET enabled, `GraphLinkClient.with_http` wires the GET adapter;
when building the client yourself pass `get_adapter=`.
