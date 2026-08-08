# GraphLink as an API Gateway — Full Scope & V1

Vision: GraphLink generates not just a GraphQL server *implementation shell*
(interfaces you fill in), but a **complete gateway** — schema in, and for fields
that are pure forwarding, zero hand-written resolver code. Config declares "this
field calls that upstream," GraphLink generates the call, the caching, the retry,
and the response mapping. Hand-written `*ServiceImpl` code stays reserved for
genuine business logic, not boilerplate HTTP glue.

Foundation: Spring Boot + Spring Security. Don't reinvent AuthN/AuthZ — generate
a config skeleton (same pattern as the Express `context.ts` stub — a file
written once, filled in by hand) and let Spring Security own enforcement at the
gateway edge.

---

## Full scope (everything a "real gateway" eventually needs)

Roughly the checklist from the earlier discussion, organized by when it matters:

**Routing & composition**
- Forward a field to a REST endpoint (method, path, param/body mapping)
- Forward a field to another GraphQL server (query/mutation passthrough)
- Forward to gRPC (protobuf interop)
- Forward to SOAP (WSDL/XSD interop)
- Schema stitching / composing multiple upstream schemas (GraphLink already
  supports combining multiple schemas into one at the schema layer — this
  extends that into "combine multiple *services'* schemas," not just files)

**Resilience**
- Retry with backoff, idempotency-aware, keyed off upstream error classification
- Circuit breakers per upstream
- Timeouts enforced at the gateway, independent of upstream config
- Fallback to stale cache on exhausted retry (`staleIfOffline`, already designed
  in `backend-cache.md`)

**Caching** — see `backend-cache.md` (already fully scoped: TTL/tag reuse of
`@glCache`, per-tenant key context, in-memory + Redis store, generated
invalidation surface)

**Traffic control**
- Rate limiting / throttling per client or operation
- Request coalescing / deduplication for identical in-flight upstream calls
- Load balancing across upstream instances

**Security**
- AuthN/AuthZ at the edge (Spring Security)
- Credential propagation/translation to upstreams (bearer token passthrough,
  API-key injection, per-upstream credential — **not the same problem as edge
  auth**)
- Query complexity/depth limiting (GraphQL-specific DoS vector for a gateway)

**Observability**
- Tracing, structured logging, correlation-ID propagation to upstreams
- Per-route/per-upstream metrics (latency, error rate, cache hit rate)
- Health checks per upstream dependency

**Enterprise / monetizable tier** (separate product surface — schema/CI
tooling, not runtime gateway behavior; can be built in parallel with the
runtime work since it has no dependency on it)
- Schema registry
- Breaking-change detection
- Usage analytics / API governance

---

## V1 scope — what actually ships first

**REST forwarding + GraphQL forwarding. Caching. Retry tied to error
classification.** That's it. gRPC, SOAP, schema stitching across services, rate
limiting, circuit breakers, and the enterprise tier are all real and worth
planning for, but not V1 — see Non-Goals below.

### The forwarding config (the actual hard part)

A separate config file, not a schema directive — the schema stays an
implementation-agnostic contract; backend wiring (URLs, headers, retry policy)
is deployment detail, same reasoning as why `clientConfig`/`serverConfig`
already live in `config.json` rather than in the schema. GraphLink already
parses the full schema, so the generator validates this config against it at
build time — "you mapped a field/arg that doesn't exist" becomes a build
error, not a runtime surprise.

Minimum shape needed per forwarded field — **request mapping, response
mapping, auth injection, and retryability are all part of "forwarding," not
separable follow-ups**, or the gateway can't handle real APIs:

1. **Request mapping** — HTTP method, path template with GraphQL-argument
   substitution (`/users/{id}`), which args become query params vs body vs
   path segments.
2. **Response mapping** — REST JSON almost never lines up field-for-field with
   the GraphQL type (snake_case vs camelCase, nested envelopes, pagination
   wrappers, extracting one field from a larger payload). Needs at minimum a
   field-rename/path-extraction mapping from the REST response shape onto the
   GraphQL type's fields.
3. **Auth injection** — which header/token to attach when calling this
   upstream, sourced from where (static config value, a value forwarded from
   the incoming request, a secret). This is a *different* credential than the
   one the gateway itself validated at the edge.
4. **Error/retry classification** — which upstream HTTP statuses are
   retryable (5xx, timeouts) vs terminal (4xx, especially 401/422), and how a
   terminal upstream error maps onto a GraphQL error. This determines both
   whether retry fires and whether the retry-exhausted path falls back to
   `staleIfOffline` cache or surfaces the error.

GraphQL-to-GraphQL forwarding is comparatively close to "simple config" (query
document passthrough, minimal reshaping) since both sides already speak
typed GraphQL — REST forwarding is where the real design and implementation
weight of V1 lives.

### Sequencing within V1

Caching can be (and already was) designed independently — it wraps whatever's
inside the resolver regardless of what that is. Forwarding must exist before
retry is meaningful (nothing to retry without an outbound call). Retry design
depends on the error-classification piece of the forwarding config, so it
can't be bolted on generically after the fact:

1. Server-side caching (`backend-cache.md`)
2. REST + GraphQL forwarding, with the four-part config above
3. Retry, wired to forwarding's error classification and cache's
   `staleIfOffline`

---

## Non-goals for V1

- **gRPC forwarding** — protobuf interop is its own substantial design
  problem (import `.proto`, generate a protobuf↔GraphQL type bridge), separate
  in kind from REST/GraphQL forwarding, not just "one more protocol adapter."
- **SOAP forwarding** — WSDL parsing, XSD type mapping, XML envelopes,
  `Fault` handling. Legacy, shrinking-demand, disproportionately expensive.
- **Multi-service schema stitching/federation** — `backend-cache.md` already
  scopes caching to one generated service's own resolvers; V1 forwarding is
  the same scope (one gateway service forwarding to N upstreams, not N
  gateway services composed together).
- **Circuit breakers, rate limiting, request coalescing, query
  complexity/depth limiting** — real resilience/traffic-control features,
  deferred past V1's retry-and-cache baseline.
- **Schema registry, breaking-change detection** — separate product surface,
  no runtime dependency on the gateway work, can be sequenced independently
  whenever there's bandwidth.

---

## Open questions

1. Config file format/location — new top-level `gatewayConfig` block in
   `config.json` (matches existing `clientConfig`/`serverConfig` convention),
   or a separate file referenced from `config.json`? Leaning separate file
   given this config will likely be large per-field and edited more
   frequently than `config.json` itself, but not decided.
2. How does response-mapping handle REST responses shaped as arrays/lists
   feeding a GraphQL list field — same nesting/rename rules recursively, or
   does list-shaped REST data need its own mapping primitive?
3. Auth-injection value sourcing — is "forward the incoming request's own
   Authorization header" a first-class mapping option (the common case for a
   pure pass-through gateway), or does every upstream require an explicit
   config entry even for that case?
4. Where does the REST forwarding call happen relative to the cache lookup —
   presumably identical to `backend-cache.md`'s "check cache before
   `supplyAsync`, write to cache in a `.thenApply`" pattern, with the
   forwarding call substituted for what's inside `supplyAsync`. Should be
   confirmed once forwarding's actual generated shape exists.
5. Retry policy configurability — fixed backoff strategy per V1, or
   configurable (max attempts, backoff curve) per forwarded field from day
   one? Simpler to ship fixed and add configurability later without a
   breaking config change, if the config key is additive.

---

## Relationship to existing plans

- **`backend-cache.md`** — caching architecture this plan builds on top of;
  `staleIfOffline` fallback is the retry/cache connection point described
  above.
- **`hexagonal-server-layout.md`** — forwarding-generated resolvers need a
  package placement decision under both the legacy and hexagonal layouts,
  same open question `backend-cache.md` already flagged for its own generated
  classes.
- **`future-client-languages.md`** — independent track (client-side language
  coverage vs. server-side gateway capability); no sequencing dependency
  between the two, can run in parallel.
