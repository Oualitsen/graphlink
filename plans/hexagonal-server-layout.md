# Hexagonal (Ports & Adapters) Server Layout

## Context

GraphLink generates Spring Boot servers today as a set of packages grouped **by kind**:
`types/`, `inputs/`, `enums/`, `interfaces/`, `services/`, `controllers/`, `config/`,
`security/`. The developer implements the generated service interfaces (`ArticleServiceImpl :
ArticleService`) and puts their business logic there.

Target: version **5.1**. This plan adds an **opt-in** server layout that reorganizes the same
generated output into a **ports & adapters ("close to hexagonal")** structure, plus one
behavioral change (drop repository generation in this mode). It is deliberately a
**packaging/relocation feature, not a rewrite** — no serializer changes, no method renames, no
new runtime behavior.

The name is honest about its limits: it is *close to* hexagonal, not textbook DDD hexagonal.
See "Honest limitations" below.

---

## What GraphLink already gives you (the left half of the hexagon)

Mapped onto hexagonal terms, the current output is already most of the **driving (inbound)**
side:

| Hexagonal concept | Current generated artifact | Side |
|---|---|---|
| Driving (inbound / primary) **adapter** | `ArticleController` (`@Controller` / `@SchemaMapping`) | driver |
| Driving (inbound / primary) **port** | `ArticleService` interface | driver |
| Application service (port impl) | `ArticleServiceImpl` — **developer-written** | driver (core) |
| Domain / transport model | `Article`, `Circle`, … data classes (self-serializing via `toJson`/`fromJson`) | domain |

Direction rule (settled, easy to get backwards): direction is defined by **who calls whom**,
not who implements. The controller (driving adapter) calls `ArticleService`, so control flows
*into* the core → `ArticleService` is a **driving port** and `ArticleServiceImpl` is the
core-side application service. "The developer implements an interface" does **not** make it
driven; a *driven* port is one the core calls *out* to and an outside adapter implements.

### The driven (outbound) side cannot be generated

The GraphQL schema describes the **inbound API surface** only. It says nothing about what the
domain *depends on* — repositories, gateways, external services. Therefore the entire
right-hand side of the hexagon (driven ports **and** driven adapters) is **not expressible in
GraphQL** and stays developer-owned. This is a hard limit, not a v1 shortcut.

---

## Design

### Trigger

A new config key under `serverConfig.kotlinSpring` (and the other server targets as they
adopt it):

```json
{ "serverConfig": { "kotlinSpring": { "architecture": "hexagonal" } } }
```

- Default: **absent / `"layered"`** → current by-kind layout, unchanged. Existing users' output
  does not move.
- `"hexagonal"` → the relocated layout below.

(`"hexagonal"` and `"layered"` accepted as synonyms if we want a softer name; pick one label in
`config.dart`.)

### Package layout (`hexagonal` mode)

```
<basePackage>/
  domain/                      # the clean core — see purity bar below
    types/                     # Article, Circle, WebSite, Author, unions, ...
    enums/                     # ArticleType, ...
    interfaces/                # Shape, Media, ...
    command/                   # inputs as commands: CreateArticleInput, ... (see note)
  port/
    in/                        # driving ports  = today's service interfaces
  adapter/
    in/
      graphql/                 # driving adapters = today's controllers
  config/                      # unchanged (RuntimeWiring, type resolver, ...)
  security/                    # unchanged
```

- `port/out` and `adapter/out` are **not generated** — no empty folders, no README stubs. The
  developer creates them and fills them; regeneration never touches files GraphLink did not
  emit (existing non-destructive generation semantic).
- **No repositories generated in this mode** (see decision D1).

### The purity bar we are committing to — **Bar B**

Two bars were considered:

- **Bar A (rejected):** domain classes carry *zero* serialization; `toJson`/`fromJson` extracted
  into a parallel converter graph, including a polymorphic `ShapeSerialization` dispatching on
  `__typename`. Rejected — it is a **graph-wide rebuild of the serialization subsystem**
  (serialization is mutually recursive across the type graph and is part of the `interface`
  contract, e.g. `Shape.toJson` + `Shape.fromJson`'s `__typename` dispatch). High cost, buys
  only architectural purity, changes nothing at runtime, and taxes the "zero-token boilerplate"
  promise.
- **Bar B (chosen):** domain classes have **no *framework* dependency** — no Spring, no
  `graphql.*`, no Jackson, no GraphLink runtime — only stdlib `Map<String, Any?>`
  self-serialization via the existing `toJson`/`fromJson`. **This is already true of the current
  generated types** (verified: `Article`, `Circle`, `CreateArticleInput`, `ArticleType` import
  only stdlib + sibling generated types). So Bar B requires **no changes to the classes** — only
  relocation.

**Acceptance test (Bar B):** every class placed under `domain/` imports nothing but language
primitives and sibling `domain/` types. A stdlib `toJson(): Map<String, Any?>` on the entity is
permitted and is not considered a framework leak. Enforce as a generation-time assertion or an
integration-test grep (no `springframework`, `graphql.`, `jackson`, or generated
`config/`/`controllers/` imports under `domain/`).

### Method names — unchanged

`toJson`/`fromJson` stay. They are slightly inaccurate (it is a Map, not JSON — the name is
inherited from Dart's `json_serializable` lineage), but they are **public generated API** used
by every user's hand-written code, by the forwarding/schema-mapping controllers
(`Article.fromJson(valueAsMap)`), across all four language targets, and by the integration
tests/examples/docs. A rename is trivial to *implement* and expensive to *ship* (breaking,
cross-language, cross-user) for a pedantic gain. **Out of scope** here; if ever done, gate it or
defer to a deliberate major-version bump with a migration note.

### `@glServiceName` grouping is preserved

`@glServiceName(name: "Article")` continues to fold root fields and projection resolvers into
the `Article` service/controller pair. In hexagonal mode this grouping lands in `port/in` and
`adapter/in/graphql` respectively — one cohesive driving port per domain concept.

---

## Decisions (resolved during design)

- **D1 — Repositories: dropped in hexagonal mode.** The current `generateRepositories`
  emits Spring Data repositories, which are **driven adapters with the framework baked in** —
  an anti-pattern in a layout whose premise is that the driven side is developer-owned and
  framework-independent. In `architecture: hexagonal`, repository generation is **ignored (warn)**;
  the driven side is 100% developer-owned. `generateRepositories` remains valid only in the legacy
  `layered`/default layout.
- **D2 — Inputs live in `domain/` (as commands).** With Bar B the generated input class is a
  clean, framework-free request shape → in DDD terms a **command**, and part of the driving-port
  signature (service methods take inputs). Placed under `domain/command/` to visually separate
  entities from request shapes within the clean core. (Honest caveat: inputs track the *API
  request* shape while entities track the *domain* shape; in hand-written DDD these drift and
  people separate them, but here both are schema-derived and cannot drift independently, so the
  objection is weak.)
- **D3 — No driven-side folders generated, no stubs.** Non-destructive generation makes
  developer-created `port/out` / `adapter/out` safe across regenerations.
- **D4 — Opt-in, off by default.** No existing layout moves without explicit config.

---

## Honest limitations (state these in docs)

1. **Anemic domain, by design.** Domain classes have no methods; all behavior lives in the
   services (the application layer). This is a legitimate, common layered style, but it is **not**
   rich-domain DDD — do not market it as such. It is uniform across all languages (no reliance on
   Kotlin extension functions).
2. **Self-serialization on the entity.** The one deviation from a *pure* core is a stdlib `toJson`
   on the domain class. No framework leaks; acceptable under Bar B.
3. **Driven side is entirely developer-owned.** GraphLink generates the whole left (driving) half
   of the hexagon and nothing on the right (driven) half. A future `@glDrivenPort`-style directive
   is the natural seam if we ever want to declare outbound ports — explicitly out of scope for 5.1.

---

## Scope summary

| Change | Effort |
|---|---|
| New `architecture` config key in `config.dart` (`KotlinSpringConfig`) | small |
| Relocate generated files into hexagonal packages (path/package computation only) | medium |
| Update generated `package` declarations + cross-package imports to new paths | medium |
| Ignore+warn on `generateRepositories` when `hexagonal` | small |
| Bar B acceptance assertion / integration-test check | small |
| Docs page + `llms.txt` / `llms-full.txt` / SEO sync | small |

**Not in scope:** serializer changes, method renames, driven-side generation, any runtime
behavior change, rich-domain behavior.

---

## Test plan

- Unit: given `architecture: hexagonal`, assert each artifact's emitted `package` and output path
  match the layout table; assert `generateRepositories` produces no repository files and warns.
- Acceptance (Bar B): grep every `domain/**` file for forbidden imports (`springframework`,
  `graphql.`, `jackson`, generated `controllers`/`config` packages) → must be empty.
- Regression: with the key absent, output is byte-identical to today's by-kind layout.
- End-to-end: regenerate `server_integration_tests/kotlin/kotlin_server_blocking/` in hexagonal
  mode, `./gradlew compileKotlin` → BUILD SUCCESSFUL, existing harness passes.
