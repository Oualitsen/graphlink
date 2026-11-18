---
title: "OpenAPI and /docs for REST Operations"
description: "Generate an OpenAPI 3.1 spec from your @glRest operations and serve it with a Swagger UI page on every server target, or write it to a file for CI and client generators."
---

# OpenAPI and `/docs`

The [REST operations](rest-client.md) a generated server serves can be described by an **OpenAPI 3.1** document built from the same schema as the server code, so the two cannot drift. GraphLink can write it to a file, serve it at `/openapi.json`, and serve a [Swagger UI](https://swagger.io/tools/swagger-ui/) page at `/docs`.

This is opt-in: nothing is generated unless the server config has an `openapi` section. A server with no `@glRest*` operation ignores the section.

## Config

`openapi` sits next to the server language key in `serverConfig`:

```json
"serverConfig": {
  "spring": { "basePackage": "com.acme.generated" },
  "openapi": {
    "file": "src/main/resources/static/openapi.json",
    "serve": true,
    "specPath": "/openapi.json",
    "docsPath": "/docs",
    "title": "My API",
    "version": "1.0.0",
    "serverUrl": "/"
  }
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `file` | `string` | none | Where to write the spec. It is its own path, relative to the working directory, and is **not** resolved under `outputDir`, so it can live in a resources or docs folder. Parent folders are created. Without it no file is written. |
| `serve` | `boolean` | `true` | Generate the two routes below. `false` writes the file only. |
| `specPath` | `string` | `"/openapi.json"` | Route serving the spec. Must start with `/`. |
| `docsPath` | `string` | `"/docs"` | Route serving the Swagger UI page. Must start with `/` and differ from `specPath`. |
| `title` | `string` | `""` | `info.title` of the spec, and the page title. |
| `version` | `string` | `"0.0.0"` | `info.version` of the spec. |
| `serverUrl` | `string` | `"/"` | The spec's `servers[0].url`. |

## What each server serves

With `serve` on, the generated code answers two `GET` routes. The spec is embedded in the generated code, so it works offline.

| Server | Generated |
|---|---|
| Spring Boot (Java and Kotlin, MVC and WebFlux) | `controllers/GraphLinkOpenApiController` |
| Express | Two routes in the generated REST router, registered before the REST routes |
| NestJS | `rest/openapi.controller.ts`, registered first in `GraphLinkModule.forRoot` |
| FastAPI | `rest/openapi.py`, a router included before the REST router. FastAPI's own `/docs` and `/openapi.json` stay disabled, so its inferred spec never shadows this one |
| Django | `rest/openapi.py`, two entries added to `create_urlpatterns` |

!!! warning "Auth and the two routes"
    The routes are generated outside your services, so `@glIntercept` and `@glInjectContext` do not apply to them. Authentication you configure before routing (Spring Security, Express middleware, a Django middleware) can block them: allow `specPath` and `docsPath` if the API is protected.

!!! note "Swagger UI needs internet access in the browser"
    The `/docs` page loads Swagger UI (pinned to one version) from a CDN, so it does not add a dependency to your server, but the browser opening it needs internet access. The spec itself is served by your server and works offline.

The default `serverUrl` of `/` makes "Try it out" call the host that served the page, so no CORS setup is needed.

## What the spec describes

Only the `@glRest*` operations. GraphQL operations are not described: GraphiQL and introspection already cover them.

- **Operations:** path, method and `operationId` (the field name). Path, query and header arguments become parameters (required when non-null without a default). A [spread](rest-client.md) input becomes one query parameter per field, a JSON-encoded one carries `content: application/json`.
- **Bodies:** JSON, form (`application/x-www-form-urlencoded`), multipart and raw upload bodies. Uploads are `format: binary`.
- **Responses:** JSON, text, binary downloads and `Void` (`204`). A `responsePath` wraps the schema in the nested objects of the path, and a nullable result also allows `204`.
- **Types:** only the types reachable from REST operations, under `components.schemas`. Nullable fields use `type: [T, "null"]`. Enums list their wire values. `Long` is `integer` with `format: int64`. A custom scalar with a `jsonType` codec uses that JSON type, with a `format` for `Date`, `DateTime` and decimals. One without a codec is any value, with a description naming the scalar.
- **Interfaces and unions:** `@glRestDiscriminator` becomes `oneOf` with a `discriminator` mapping, and each implementation carries the discriminator as a required `const` property, because the server always writes it.
- **`@glRestNullable`:** the nullable copy (`ProductRest`) is its own schema with every field nullable, as generated.
- **Errors:** every `400`, `404` and `500` response points at one shared `{ message: string }` schema, with open `additionalProperties`. The servers do not write identical error bodies, so this is the common subset.

`@glCache` is not described: it is client-side.

## Serving Swagger UI from the file

The page GraphLink generates is optional. The file is a standard OpenAPI 3.1 document, so any tool can use it:

```bash
# Swagger UI in Docker
docker run -p 8081:8080 -e SWAGGER_JSON=/spec/openapi.json \
  -v "$PWD/src/main/resources/static:/spec" swaggerapi/swagger-ui

# A client in another language
openapi-generator-cli generate -i openapi.json -g python -o ./client
```

If the page is hosted on a different origin than the API, set `serverUrl` to the API's real URL and allow that origin in the server's CORS configuration.

On Spring Boot, a file written under `src/main/resources/static/` is also served by Spring's static resource handling at `/openapi.json`. The generated controller answers the same path with the same content, so use either.

## Related

- [REST Operations](rest-client.md): the directives the spec is built from.
- [Configuration](configuration.md): every config key.
