# Python server target: FastAPI + Ariadne

Status: implemented 2026-11-16, all phases. GraphQL uploads run against `servers/python_upload_server` (Dart upload harness).
`server_integration_tests/servers/python_fastapi_server` passes the faults, REST and GraphQL suites with no known defect, and the Dart, TypeScript,
Python and Go client harnesses against it.

Where the implementation differs from this draft:
- Decision 1 went to option B, `to_json()` at the boundary, with the `__glSource__` mechanism of the Express target (`attach_source` / `source_of`) so
  mappings still receive the instance the service returned. Field resolvers are only registered for mappings and `mapTo` pass-through fields.
- `PythonSerializer` takes a `runtimeDir` (the server writes `runtime/`, the client keeps `client/`), instead of a module path.
- Errors and the depth limit: `max_depth_rule` is an `ASTValidationRule`; `ExplorerHttp405` replaces the GraphiQL page on a bare GET;
  `GraphLinkWSHandler` answers malformed WebSocket frames with 4400.
- `graphql-core` must stay below 3.2.14: Ariadne's enum `parse_value` patch fails there.

## Goal

A fourth server language next to Spring (Java, Kotlin) and Express. Same contract as the others: one schema gives
typed models, service interfaces, guards, resolver wiring, batch loaders, REST routes and an entry point. The developer
only implements the services. The generated code has no runtime dependency on GraphLink; third-party dependencies are
`fastapi`, `ariadne`, `uvicorn` (entry point only), `python-multipart` (forms and uploads only) and `pydantic` (already
required by the Python client).

Ariadne is schema-first: it takes the SDL string and binds resolvers to it, which is how the Express target already
works (`typeDefs.ts` + `buildResolvers`). **The Express serializer is the model to follow, not Spring.** For the types,
reuse `PythonSerializer` (pydantic v2), already used by the Python client.

## What gets generated

```
<outputDir>/<package>/
  __init__.py
  type_defs.py           # TYPE_DEFS = """...""" (same SDL as typeDefs.ts)
  types/ inputs/ enums/ interfaces/   # PythonSerializer, server mode
  services/<service>.py  # Protocol classes, async methods
  guards/<service>.py    # Protocol classes for @glValidate
  loaders/<service>.py   # per-request batch loaders for @glBatchMapping
  resolvers.py           # build_schema(services, guards, ...) -> GraphQLSchema
  context.py             # GraphLinkContext (request, user context, loaders)
  rest/router.py         # build_rest_router(services, ...) -> APIRouter   (only if @glRest*)
  rest/support.py        # parsing helpers, errors, uploads, downloads
  file_upload.py         # only if uploads
  app.py                 # entry point: FastAPI app + Ariadne mount (generateEntryPoint)
```

Each service Protocol looks like:

```python
class ArticleService(Protocol):
    async def get_article(self, id: str) -> Optional[Article]: ...
    async def create_article(self, input: CreateArticleInput, context: GraphLinkContext) -> Article: ...  # @glInjectContext
    def article_deleted(self) -> AsyncIterator[str]: ...                                                  # subscription
    async def article_author(self, articles: List[Article]) -> Dict[Article, Author]: ...                  # batch mapping
```

## Config

```json
"serverConfig": { "fastapiAriadne": {
  "package": "generated", "port": 8000, "graphqlPath": "/graphql",
  "generateEntryPoint": true, "injectContext": false
} }
```

- `config.dart`: `FastapiAriadneServerConfig extends ServerLanguageConfig`, and a branch in
  `ServerLanguageConfig.fromJson`. Update its error message.
- `server_generator.dart`: `_generateFastapiAriadneClasses`, same shape as `_generateExpressApolloClasses`, with
  `cleanUpObsoleteFiles` at the end.

## New Dart files

```
lib/src/serializers/python/
  fastapi_ariadne_server_serializer.dart     # extends ServerSerializer: services, guards, resolvers, loaders, context, app
  fastapi_ariadne_server_constants.dart      # static runtime templates (loader, context base)
  fastapi_ariadne_rest_serializer.dart       # APIRouter from GLParser.restOperations
  fastapi_ariadne_rest_constants.dart        # rest/support.py
```

All generated control flow, methods and classes go through `PythonCodeGenUtils`. Add any builder that's missing there
(e.g. `async def`, `async for`, decorators), don't hand-write strings. Derived data stays in the `gl_grammar_*`
extensions. Most of it already exists for Express (`services`, `isIntercepted`, `restOperations`, `carriesSources`, upload
getters).

## Design decisions (need your call)

### 1. How resolvers hand pydantic models to Ariadne

Ariadne's default resolver reads `obj.<graphqlFieldName>`. Python field names are normalized (`first_name`, `class_`), so
`firstName` would resolve to null.

- **A (recommended):** the generated `ObjectType` bindings set a field resolver only where `codeName != wire name`
  (`obj.set_field("firstName", lambda o, *_: o.first_name)`). Services return typed models, parents stay typed for
  mappings, nothing is copied.
- B: return `model.to_json()` at the boundary. Simpler, but mapping resolvers then receive dicts (the Java "parent is a
  copy" problem, `SERVER_GRAPHQL.md` bug 6), and it costs an extra pass.
- C: Ariadne `convert_names_case`. Rejected: it doesn't know GraphLink's keyword normalization (`class_`).

Inputs go the other way: the resolver calls `CreateArticleInput.from_json(args["input"])`. That reuses the client's
`from_json`, so defaults and scalar codecs behave like in every other target ("uniform explicit JSON", no framework
shortcut).

Custom scalars: one Ariadne `ScalarType` per mapped scalar, its serializer and parser calling the same codec expressions
as `to_json` / `from_json`.

### 2. Batch loading

Ariadne ships no DataLoader.

- **A (recommended):** generate a small per-request asyncio batcher in `loaders/` (a constants template, about 40 lines):
  collect keys in the current tick, call the batch service once, resolve the futures. No extra dependency.
- B: depend on `aiodataloader`. Same behaviour, but the package is lightly maintained.

The loaders live on `GraphLinkContext` and are created per request, as on Express.

### 3. Async only?

- **Recommended:** async services only in v1. FastAPI and Ariadne are async, subscriptions have to be async anyway, and
  sync code can call `run_in_threadpool`.
- A sync flavor (like Spring MVC vs. reactive) can be added later behind a config flag if users ask.

### 4. Where `PythonSerializer` lives in server mode

`pythonModelBaseModule = 'client/graph_link_model'` is hard-coded for the client layout. Make the module path a
constructor parameter so the server writes `graph_link_model.py` at its package root. `getSerializableFields(grammar.mode)`
already skips client-only fields in server mode.

## Feature mapping

| Feature | Express today | FastAPI + Ariadne |
|---|---|---|
| Queries / mutations | `buildResolvers` | `QueryType` / `MutationType` bindings calling the service |
| Subscriptions | graphql-ws `useServer` | `ariadne.asgi.handlers.GraphQLTransportWSHandler`; service returns `AsyncIterator`, `SubscriptionType.source` + `.field` |
| Subscription over HTTP POST | Apollo errors | Must be an error. Check with `core_subscription_over_http_rejected`; add a guard in the generated handler if Ariadne answers 200 |
| `@glValidate` | guard called before service | same, `guards/` Protocol, `validate_<op>` |
| `@glInjectContext` / `injectContext` | `context` param | `context: GraphLinkContext` param; `context_value` built from the FastAPI `Request` |
| `@glIntercept` | interceptor interface | same, `GraphLinkInterceptor` Protocol called with the tag before the resolver |
| `@glSkipOnServer` mappings, `mapTo` | field resolvers | field resolvers on `ObjectType`; `mapTo` source fields return the parent (Express bug 1 fix applies from day one) |
| `@glBatchMapping` | DataLoader | decision 2 |
| GraphQL uploads | graphql-upload | Ariadne's multipart support (`Upload` scalar, `combine_multipart_data`), `python-multipart` |
| `@glRest*` | Express router | FastAPI `APIRouter`; body read from `Request` and parsed with `from_json` (not FastAPI's auto-models, so codecs and errors match the other servers); forms via `request.form()`, uploads via `UploadFile`, downloads via `StreamingResponse`, `responsePath` wrapping |
| Errors | Apollo formatting | Ariadne `debug=False` and an `error_formatter` that never puts tracebacks in `extensions` (the fault suite's `LEAK` check); REST: 400 on malformed JSON, no FastAPI 422 pages |
| Entry point | `index.ts` | `app.py`: `FastAPI()`, `app.mount(graphqlPath, GraphQL(schema, ...))`, REST router included, `uvicorn.run` under `__main__` |

## Phases

Each phase ends with unit tests and the server matrix green for what exists.

1. **Skeleton:** config, generator, `type_defs.py`, types/inputs/enums, services, query/mutation resolvers (decisions 1
   and 4), `app.py`. Unit tests in `test/server/python_fastapi/`, schemas inline. Then `server_graphql` "core" cases
   and the Dart client harness against it.
2. **Mappings:** schema mappings, batch loaders, `mapTo`, guards, context, intercept. Run the `mapping_*` cases.
3. **Subscriptions:** WebSocket handler, the reject-over-HTTP check, the `server_graphql` WS cases, and the clients'
   subscription tests.
4. **REST:** router plus support, the whole `server_rest/cases.json`.
5. **Uploads and downloads:** GraphQL multipart, REST parts/forms/downloads; a `python_upload_server` if the upload suite
   needs a separate schema, as on TS.
6. **Matrix and docs:**
   - `server_integration_tests/servers/python_fastapi_server/` (impl copied from the TS impls, `server.mk`, a free port,
     9975);
   - `ci-http-python-fastapi`, plus a line in the `ci.yml` matrix (line ~602);
   - every client harness against it;
   - an entry in the three `known_defects.json` files;
   - an `examples/python_fastapi/` example;
   - a `site/docs-src` page;
   - CLAUDE.md (generator map, serializer map, server list).

## Risks and open questions

- **Ariadne specifics to check early (phase 1 spike):**
  - whether introspection limits match graphql-js (the schema cases depend on it);
  - how it answers GET, and whether it has CSRF protection like Apollo (`core_get_request_is_answered_or_refused`);
  - how it handles a malformed body or a batched array (fault suite).
- **Server-side defaults:** graphql-core fills argument defaults from the SDL before the resolver runs; input-field
  defaults come from `from_json`. The `defaults_*` cases will tell.
- **Python version:** use the Python client's minimum (not pinned in the harnesses today; decide it once for both).
- **Performance:** pydantic validation on every `from_json` is slower than plain dicts; acceptable for v1, and measure
  before optimizing.
- **Django later:** the core (types, services, guards, resolvers, loaders) has no FastAPI import. Only `app.py`,
  `context.py` and `rest/` are FastAPI-specific, so a Django flavor replaces those three.
