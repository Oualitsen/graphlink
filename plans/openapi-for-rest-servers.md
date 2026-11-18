# OpenAPI spec and `/docs` for REST on the server

Status: implemented for every server target (Express, NestJS, Spring Java/Kotlin, FastAPI, Django). Not done: the `site/docs-src/` page.
`server_integration_tests/server_openapi/run_openapi.py` checks the served page, validates the spec with `openapi-spec-validator` and
checks it against rest.gql; `run_rest.py` validates every 2xx response against the spec (`server_openapi/conformance.py`, needs `jsonschema`;
CI sets `REQUIRE_OPENAPI_CONFORMANCE=1`). `openapi.file` is its own path, independent of `outputDir`.

## Problem

Every server target serves the `@glRest*` operations next to GraphQL. GraphQL can be explored interactively (GraphiQL and
introspection), but REST has nothing: no spec and no explorer. Users who don't use GraphLink can't generate a client for the REST
API, and the frameworks' own OpenAPI tooling is uneven:

| Server | Auto OpenAPI | Why it isn't enough |
|---|---|---|
| Spring (MVC, WebFlux, Kotlin) | springdoc scans `@RestController`s | Doesn't know about `responsePath`, discriminators, argument roles, spread inputs or `@glRestNullable` copies |
| FastAPI | built in at `/docs`, `/openapi.json` | The generated handlers go through the route table, so the inferred spec is thin or wrong |
| NestJS | `@nestjs/swagger` | Needs decorators or the CLI plugin, plus a dependency |
| Express, Django (non-DRF) | nothing | none |

## Rejected alternative: turn every REST endpoint into GraphQL

This would mean exposing each REST operation as a GraphQL field and steering users to GraphQL. Rejected because:
- It is lossy: downloads, text and binary responses, headers, status codes, form and multipart bodies, and HTTP caching of GETs
  don't map onto GraphQL.
- It removes the reason the REST feature exists (public APIs, webhooks, curl, CDN caching).
- The reuse of GraphQL generation is offset by the work needed to cover those gaps.

## Rejected alternative: importing an OpenAPI spec into `@glRest*` operations

The reverse direction (an existing `openapi.json` -> `.graphql` with `@glRest*`) is rejected. Specs in the wild are often incomplete
or loosely typed (`anyOf` everywhere, missing `required`, ad hoc formats). The importer would have to guess, the generated schema
would be only as good as the spec, and it would need hand-fixing anyway. It also overlaps with openapi-generator.

## Decisions

1. **One spec, built from the IR.** A target-neutral serializer turns `GLParser.restOperations`, the REST response types and
   `restDiscriminators` into one OpenAPI 3.1 document (`"openapi": "3.1.0"`). No framework plugin infers anything. 3.1 is chosen for its
   JSON Schema nullability (`type: [T, "null"]`); tools that only read 3.0 are not supported.
2. **The spec describes exactly what `toJson` writes and `fromJson` reads**: field names, scalar codecs, null handling. It comes
   from the same IR as the server code, so the two can't drift.
3. **It is served by generated routes, not by static folders.** Static-file serving is not uniform: Express and NestJS need
   wiring, and Django serves nothing outside `DEBUG`. Every server already has generated entry points, so each one gets two routes:
   - `GET <specPath>` (default `/openapi.json`): the spec, embedded as a string constant in the generated code.
   - `GET <docsPath>` (default `/docs`): a small HTML page that loads Swagger UI from a CDN and points it at `<specPath>`.
4. **No runtime dependency.** Swagger UI is loaded by the browser, not by the server. Consequence to document: `/docs` needs
   internet access in the browser. The spec itself works offline.
5. **Opt-in.** The spec describes the whole REST surface, so the routes are off by default. The `.json` file can be emitted
   without the routes (see Config).
6. **Same-origin.** The spec contains `"servers": [{"url": "/"}]` so "Try it out" calls the host that served the page, with no CORS
   setup. The base URL can be overridden by config.
7. **No guards on the two routes.** `@glIntercept` and `@glInjectContext` don't apply to them. Auth configured by the user before
   routing (Spring Security, Express middleware) may block them; the docs must say to allow both paths.
8. **FastAPI:** the generated app is created with `docs_url=None, openapi_url=None` when the feature is on, so FastAPI's own
   inferred spec never shadows ours. It stays as it is today when the feature is off.
9. **REST only.** GraphQL operations are not described; GraphiQL/introspection already covers them. A server in GraphQL-only
   mode (no REST operations) emits nothing and the option is a validation warning.
10. **The discriminator is part of the wire.** The server always writes the `@glRestDiscriminator` property when it serializes an
    implementation, so the spec describes it as a real property: `required`, with a `const` value from `valueByType`, on the
    implementation schema. Client generators need it to exist. The `run_rest.py` check (Tests, 3) enforces it.
11. **Error bodies: minimal common subset.** One shared error schema, `{ message: string }`, `additionalProperties` open, used by
    every 4xx/5xx response. Making the servers write identical error bodies is out of scope.

## Config

New `openapi` section in the shared server config (`ServerLanguageConfig`, `fromJson`):

```json
"serverConfig": {
  "spring": { "...": "..." },
  "openapi": {
    "file": "openapi.json",
    "serve": true,
    "specPath": "/openapi.json",
    "docsPath": "/docs",
    "title": "My API",
    "version": "1.0.0",
    "serverUrl": "/"
  }
}
```

- Section absent: nothing generated.
- `file`: written under `outputDir` (for CI, publishing, client generators).
- `serve: false`: file only, no routes.
- `title`: taken from this config section, empty string when absent. `version` defaults to `0.0.0`.

## Mapping (IR to OpenAPI)

### Operations

| IR | OpenAPI |
|---|---|
| `RestMethod`, `path` | `paths./x.{get,post,...}`; `{id}` placeholders kept as is |
| operation name | `operationId` |
| `RestArgRole.path / query / header` | `parameters` with `in: path / query / header`; `required` from `!` / default |
| query input with `RestEncoding.spread` | one query parameter per `spreadFields` entry |
| query input with `RestEncoding.json` | `content: application/json` on the parameter |
| query input with `RestEncoding.flat` (list styles COMMA, BRACKET, ...) | `style` / `explode` matching the configured list style |
| `RestBodyKind.json` | `requestBody` `application/json` |
| `RestBodyKind.form` | `application/x-www-form-urlencoded` with `field` roles as properties |
| `RestBodyKind.multipart` | `multipart/form-data`; `part` roles, uploads as `format: binary` |
| `RestBodyKind.raw` | `requestBody` with the operation's `contentType` |
| `bodyIsOptional` | `requestBody.required: false` |
| `RestResponseKind.json` | `200` `application/json` |
| `RestResponseKind.text` | `200` `text/plain`, `type: string` |
| `RestResponseKind.binary` (`Download`) | `200` with `accept` media type, `format: binary` |
| `RestResponseKind.none` (`Void`) | `204` |
| `responsePath` segments | the response schema is wrapped in nested objects along the path |
| `allowsEmptyBody` | the success response also allows no content |
| `@glCache` | nothing in v1 (it's client-side) |

Error responses: one shared `components.responses` entry per status the servers emit (400 bad input, 404, 405, 500), all using the
minimal error schema of decision 11.

### Types (`components.schemas`)

| GraphQL | JSON Schema |
|---|---|
| `type`, `input` | `type: object`, `additionalProperties` left open |
| non-null field | listed in `required` |
| nullable field | `type: [T, "null"]` (3.1) |
| `[T!]!` / `[T]` | `type: array`, `items` nullable when elements are |
| `ID`, `String` | `string` |
| `Int` / `Float` / `Boolean` | `integer` (`format: int32`) / `number` / `boolean` |
| `Long` and similar built-ins | `integer`, `format: int64` |
| custom scalar with codec | the codec's JSON type (`jsonType`) plus `format` when known (`date-time`, `date`, `decimal`) |
| custom scalar without codec | `{}` (any), with a `description` naming the scalar |
| enum | `type: string`, `enum` with the wire values |
| interface (a union is converted to an interface first, `fromUnion`, and takes the same path) | `oneOf` of the implementations + `discriminator.propertyName` and `mapping` from `valueByType`; each implementation schema gets the discriminator as a required `const` property (decision 10) |
| interface without `@glRestDiscriminator` | plain object: the interface's own fields, `additionalProperties` open, no `oneOf` |
| `@glRestNullable` copy (`ProductRest`) | its own schema, as generated: every field nullable |

Only the types reachable from REST operations are emitted (`restReachableTypeNames`), not the whole GraphQL schema.

## Where the code goes

- **IR (extension):** `parser_extensions/gl_grammar_openapi_extension.dart` builds a target-neutral model (`GLOpenApiDocument`:
  operations, parameters, bodies, responses, schemas) from `restOperations`, `restDiscriminators` and the scalar codecs. Every
  mapping decision above lives here.
- **Serializer:** `serializers/openapi_serializer.dart` turns that model into JSON (`JsonEncoder.withIndent`). It contains no
  mapping logic.
- **Docs page:** a constant HTML template (`openapi_constants.dart`), with `specPath` substituted in. Pin the Swagger UI version
  in the CDN URL.
- **Per server, two routes**, each built with the language's `*CodeGenUtils`:
  - Spring Java/Kotlin, MVC and WebFlux: a generated `GraphLinkOpenApiController` next to the REST controllers.
  - Express: two `router.get` entries in the generated REST router.
  - NestJS: one generated `@Controller` registered in `GraphLinkModule.forRoot`.
  - FastAPI: two routes in the generated REST router, plus decision 8.
  - Django: two views added to `create_urlpatterns`.
- **Generator:** `server_generator.dart` writes `file` and passes the spec string to the server serializers when `serve` is on.

## Tests

1. **Unit, `test/openapi/`** (inline schemas): one test per mapping row, asserting on the parsed JSON (not on string snippets).
   Covers path/query/header/spread, form, multipart, text, binary, void, `responsePath`, unions with and without discriminator,
   `@glRestNullable`, scalar codecs, enums.
2. **Spec validity:** validate the generated spec of `server_integration_tests/schema_rest/rest.gql` with `openapi-spec-validator`
   (Python; a new dev dependency of the harness, not of generated code).
3. **Spec matches the wire:** extend `server_rest/run_rest.py` to validate each response body against the operation's response
   schema in the spec (`jsonschema`). This is the check behind decisions 2 and 10, and it runs against every server in
   `ci-rest-<server>`.
4. **Routes:** one case per server in `server_rest/cases.json`: `GET /openapi.json` returns 200 and valid JSON, `GET /docs` returns
   HTML containing the spec path.

## Docs

New page `site/docs-src/` "OpenAPI and /docs for REST": the config, what is and isn't described, the auth note (decision 7),
the CDN note (decision 4), and generating a client from the spec with openapi-generator.

## Order of work

1. IR model + mapping, with unit tests (TDD).
2. JSON serializer + `file` output; validity check against `schema_rest`.
3. Routes on Express (simplest), then Spring Java/Kotlin, NestJS, FastAPI, Django.
4. `run_rest.py` wire-conformance check across all servers.
5. Docs page.

## Open questions

- Should the `x-graphlink-*` extensions (cache tags, original GraphQL type name) be emitted for tooling? Leaning no for v1:
  nothing reads them yet, and adding them later breaks no one.
