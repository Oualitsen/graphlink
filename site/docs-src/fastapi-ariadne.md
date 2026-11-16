---
title: "FastAPI & Ariadne GraphQL Server Generator"
description: "Generate a FastAPI + Ariadne GraphQL server in Python: pydantic models, service Protocols, async resolvers, batch loaders, graphql-transport-ws subscriptions, REST and file uploads."
---

# FastAPI / Ariadne Server

GraphLink generates a FastAPI + Ariadne server from your schema: pydantic v2 models, `Protocol` service
interfaces, async resolvers, per-request batch loaders, subscriptions over WebSocket, `@glRest*` routes and
file uploads. You implement the services; GraphLink owns the wiring. It follows the same model as the
[Express / Apollo](express-apollo.md) target.

## Server mode config

```json title="glink.json"
{
  "schemaPaths": ["schema/*.graphql"],
  "mode": "server",
  "outputDir": "generated",
  "serverConfig": {
    "fastapiAriadne": {
      "port": 8000,
      "graphqlPath": "/graphql",
      "generateEntryPoint": true,
      "injectContext": false,
      "useResolveInfo": false
    }
  }
}
```

| Option | Default | Meaning |
|---|---|---|
| `port` | `8000` | Port recorded for the entry point |
| `graphqlPath` | `/graphql` | HTTP and WebSocket path |
| `generateEntryPoint` | `true` | Writes `app.py` with `GraphLinkServices` and `create_app` |
| `injectContext` | `false` | Every service method gets `context`; otherwise only `@glInjectContext` fields |
| `useResolveInfo` | `false` | Service and guard methods of resolver-backed fields get `info` (the interceptor gets it as its last parameter, `None` for subscriptions, batch mappings and REST) |

The output directory is a Python package. Install `fastapi`, `ariadne`, `uvicorn`, `pydantic`, and
`python-multipart` (forms and uploads). Keep `graphql-core` below 3.2.14: Ariadne's enum patch fails on it.

## What you implement

Each service is a `Protocol` of async methods in `services/`. Subscriptions return an async iterator:

```python
class ArticleService(Protocol):
    async def get_article(self, id: str, context: GraphLinkContext) -> Article: ...
    def article_created(self, context: GraphLinkContext) -> AsyncIterator[Article]: ...
```

```python
from generated.app import GraphLinkServices, create_app

app = create_app(GraphLinkServices(article_service=ArticleServiceImpl(), ...))
# uvicorn start:app
```

Services return the generated pydantic models. The resolvers hand `to_json()` dicts to Ariadne and keep the
model next to it, so a schema mapping receives the instance your service returned.

## Context

`GraphLinkContext` is a plain object: set attributes on it from an interceptor or a `context_factory`
(`GraphLinkServices(context_factory=lambda request: ...)`), and read them in services. `context.request` is the
Starlette request or WebSocket.

## Batch mappings, guards, interceptors

- `@glSkipOnServer(batch: true)` mappings resolve through one loader per request: the service receives all parents
  in a single call and returns a `dict` keyed by parent.
- `@glValidate` generates a guard `Protocol` (`validate_<operation>`), called before the service.
- `@glIntercept` requires `GraphLinkServices(interceptor=...)`; `run_before(tag, operation, args, context)` may
  raise to deny.

## HTTP behavior

Errors never carry stack traces. Queries nested deeper than `max_query_depth` (default 32) are refused with 400,
over HTTP and WebSocket. A bare `GET` does not serve an explorer page. Malformed WebSocket frames close the
socket with 4400.

## Uploads

A scalar marked `@glUpload` is served over the GraphQL multipart request spec; the service gets
`FileUpload` (`filename`, `mimetype`, `encoding`, `create_read_stream()` as an async iterator of `bytes`).
`@glRest*` operations use the same type for multipart parts and raw bodies, and `GraphLinkDownload` for downloads.
