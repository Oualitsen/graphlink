---
title: "Django & Ariadne GraphQL Server Generator"
description: "Generate a Django + Ariadne GraphQL server in Python: pydantic models, async service Protocols, a GraphQL view, Django REST views and file uploads."
---

# Django / Ariadne Server

GraphLink generates a server that lives inside a Django project: a GraphQL view and the `@glRest*` operations are
plain async Django views that receive the Django `HttpRequest`, so your middleware, sessions and `request.user`
apply. The services, models, resolvers, loaders and guards are the same as in the
[FastAPI / Ariadne](fastapi-ariadne.md) target. Services are async, so run the project under an ASGI server such as
uvicorn.

## Server mode config

```json title="glink.json"
{
  "schemaPaths": ["schema/*.graphql"],
  "mode": "server",
  "outputDir": "generated",
  "serverConfig": {
    "djangoAriadne": {
      "graphqlPath": "/graphql",
      "generateEntryPoint": true,
      "injectContext": false,
      "useResolveInfo": false
    }
  }
}
```

The options are the ones of `fastapiAriadne`. Install `django`, `ariadne`, `uvicorn`, `pydantic` and `starlette`
(Ariadne's WebSocket handler uses it); keep `graphql-core` below 3.2.14. A schema with only GraphQL operations,
only `@glRest*` operations, or both is supported: only the matching routes are generated.

## Wiring

```python title="urls.py"
from generated.app import create_urlpatterns
from services import services  # your GraphLinkServices(...)

urlpatterns = create_urlpatterns(services)
```

```python title="asgi.py"
from django.core.asgi import get_asgi_application
from generated.app import create_app
from services import services

application = create_app(services, get_asgi_application())
```

`create_urlpatterns` returns the GraphQL view (queries, mutations, multipart uploads) and one CSRF-exempt async
`re_path` per REST route. `create_app` is only needed for subscriptions: Django cannot serve WebSockets, so it
wraps your ASGI application, hands the GraphQL WebSocket path to Ariadne and answers `lifespan`. If you serve
subscriptions with Django Channels instead, skip `create_app`.

## Request, context and middleware

- `context.request` is the Django `HttpRequest` for queries, mutations and REST, so a `context_factory` can read
  `request.user` (use `await request.auser()` in async code). Subscriptions get the Starlette WebSocket.
- CORS is not generated: add `django-cors-headers` or your own middleware.
- Django's body limits apply (`DATA_UPLOAD_MAX_MEMORY_SIZE` caps JSON GraphQL bodies; the REST layer caps JSON and
  form bodies at 100 KB, files at 100 MB).
- Django reads a request body completely before the view runs, so uploads are spooled to disk first and are not
  streamed from the socket.

Everything else (batch mappings, guards, interceptors, depth limit, uploads) works as described in
[FastAPI / Ariadne](fastapi-ariadne.md).
