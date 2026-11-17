# Python servers (FastAPI and Django): known gaps

What the `fastapiAriadne` and `djangoAriadne` targets do not cover, or only partly. Both pass the fault, REST and
GraphQL suites in GraphQL-only, REST-only and mixed schemas (`make ci-http-python-modes`), the upload suites, and the
dart, ts, python and go client harnesses.

## Django

- **WebSocket context.** Queries, mutations and REST get the Django `HttpRequest` as `context.request`. Subscriptions
  get the Starlette WebSocket, so `request.user` and Django sessions are not available there.
- **No Channels.** Subscriptions are served by a small ASGI wrapper (`create_app`), not a Channels consumer.
- **Django middleware untested.** The test project has an empty `MIDDLEWARE` and no `INSTALLED_APPS`. CSRF, sessions
  and auth middleware were never run against the generated views (they are `csrf_exempt`).
- **Body limits.** `DATA_UPLOAD_MAX_MEMORY_SIZE` applies to JSON GraphQL bodies and returns 400 above it; the default
  was left as is. The REST layer applies its own limits (100 KB JSON and form bodies, 100 MB per file).
- **No streaming request bodies.** Django reads a body completely before the view runs; uploads are spooled to disk.
- **No CORS.** Not generated; use `django-cors-headers` or your own middleware.
- **Async only.** No sync/WSGI flavor.
- **Trailing slashes.** FastAPI redirects `/items/` to `/items`; Django does not. Not covered by any suite.
- **Only uvicorn tried.** daphne and hypercorn were not run.
- **No project scaffolding.** `settings.py`, `urls.py` and `asgi.py` are written by hand (see the docs page).

## Both

- **Clients not run.** The Java, Kotlin, Java-reactive and Swift client harnesses were never run against these servers
  (the Java and Kotlin ones do not compile at HEAD).
- **No combined upload schema.** There is no test with GraphQL and REST uploads in one schema.
- **No per-file size cap** on GraphQL uploads.
- **Untested REST cases.** `HEAD`, `OPTIONS`, `Accept` and size-limit cases are not in `server_rest/cases.json` for any
  server.
- **`generateEntryPoint: false`** is untested.
- **Unit tests are thin.** The Django generator has a handful of string assertions; behavior is covered by the
  integration suites.
