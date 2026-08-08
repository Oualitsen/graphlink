# Future client languages — C#, Go, Rust, Python

Not started. Notes to revisit when we pick one up. Order below is priority order,
not necessarily build order — see "Where to start" at the end.

Rationale (from the planning conversation): TypeScript + Dart (Flutter) + Kotlin
(Android) + Swift (iOS/macOS) already cover the large majority of the frontend/client
surface — web, cross-platform mobile, and both native mobile platforms. Adding more
client languages now is comparatively cheap because the architecture already
generalizes cleanly (a `*CodeGenUtils` block/method/class builder +
`*Serializer` for types/inputs/enums + `*ClientSerializer` for operations — see
`CLAUDE.md`'s "Adding a new target language" section). The four below extend reach
into markets the current five don't touch at all, each for a different reason.

---

## C# (.NET) — top priority

**Why:** Closest structural match to the existing targets (Kotlin/Java in
particular) — properties, nullable reference types map directly onto GraphQL
nullability, `record` types mirror Kotlin's `data class`. Likely the fastest to
ship given the established pattern. Opens Unity, MAUI/WPF desktop, and enterprise
.NET backends-as-GraphQL-consumers — none of which GraphLink reaches today.

**Design notes:**
- `record` for input/type generation, mirroring `dataClass`/`structDecl` in
  Kotlin/Swift.
- Nullable reference types (`string?`) map 1:1 to GraphQL nullability — no
  `Optional<T>` wrapper needed, similar to Swift's `?`.
- HTTP: `HttpClient` as the zero-dependency default adapter (mirrors Java's
  JDK-`HttpClient`/Swift's `URLSession` approach) — avoids a hard dependency on
  `RestSharp`/`Refit`.
- Async: `Task<T>`/`async`-`await` — no reactive-flavor equivalent needed unless
  we later want an `IObservable<T>`/Rx.NET variant for subscriptions (mirrors
  Java's blocking-vs-reactive split).
- Package/build convention: likely NuGet package output, `.csproj` targets —
  needs its own integration-test harness shape (`csharp_client_tests/`) same as
  every other target.

---

## Go — second priority

**Why:** Backend-to-backend GraphQL consumers, CLI tooling, infra/platform
tooling — a market none of the current five serve. Also positions GraphLink to
generate a **Go server target** later, which matters for the API-gateway
direction (see bottom of file).

**Design notes:**
- No classes/generics-as-Java-knows-them — structs + methods, `struct` tags for
  JSON (`json:"fieldName"`). Nullability is idiomatically `*T` (pointer) for
  optional fields, not a wrapper type.
- No exceptions — error returns (`(T, error)`), which changes the shape of
  `executeFull`/`executeData`/`executeCached` significantly compared to every
  other target (all of which use throw/catch or reactive error channels). This
  is probably the single biggest architectural departure of the four — worth a
  deeper design pass before starting, not just a template copy.
- No inheritance — GraphQL interfaces/unions need Go's structural approach
  (embedded structs + type assertions, or a `oneof`-style tagged union), not a
  direct translation of the `protocolDecl`/`kotlinInterface` pattern.
- HTTP: stdlib `net/http` as the zero-dependency default, matching the
  "zero-dependency generated code" principle.

---

## Rust — third priority

**Why:** Highest differentiation, highest effort. Nobody in the GraphQL codegen
space does a *full* client (caching, subscriptions, uploads, zero extra
runtime deps beyond what the generated code itself needs) for Rust —
`graphql_client` and similar are operation-only, same limitation as the JS
ecosystem tools. Reaches embedded/CLI/WASM consumers currently unreachable.

**Design notes:**
- Ownership/lifetimes don't map onto the existing `CodeGenUtils` shape as
  directly as C#/Go do — this will need more from-scratch design, not just
  adaptation. Budget for this up front rather than assuming a fast port.
- `struct` + `serde::{Serialize, Deserialize}` derive macros for JSON, mirroring
  Kotlin's `@Suppress`/`kotlinx.serialization` pattern conceptually but with a
  different mechanism (derive macros, not hand-generated `toJson`/`fromJson`
  method bodies) — worth deciding whether GraphLink hand-generates
  `to_json`/`from_json` (consistent with every other target, zero extra
  dependency) or leans on `serde` derive (idiomatic Rust, but a real runtime
  dependency, similar tradeoff to the Redis client decision in
  `backend-cache.md`).
- Async: `async`/`.await` via `tokio` or runtime-agnostic — reqwest is the
  obvious HTTP default but is a dependency, not stdlib; there's no
  zero-dependency async HTTP client in Rust the way `HttpClient`/`URLSession`
  are "free" on their platforms. This is a real departure from the
  zero-dependency principle worth deciding explicitly, not defaulting into.
- Error handling: `Result<T, GraphLinkError>` — closer to Go's approach than
  exception-based Java/Kotlin/Swift/TS/Dart.

---

## Python — fourth priority, different market

**Why:** Not a "frontend" pick like the other three — this is the
backend/scripting/data-consumer market: Django/FastAPI services calling a
GraphQL API, data pipelines, notebook-driven scripts. No other GraphQL codegen
tool serves this well either.

**Two compelling features independent of each other:**
1. A **fully functional generated client** — `client.queries.get_user(id=...)`
   handles query-string building, variable marshalling, and response parsing,
   which is real value even before type-safety enters the picture (no
   hand-written GraphQL strings/untyped dicts).
2. **Static type-safety via type hints**, not runtime enforcement — generated
   `dataclasses`/`TypedDict` + type hints get checked by `mypy`/`pyright` and
   give full IDE autocomplete, the same DX tier TypeScript itself offers (also
   erased at runtime). This is *not* nothing, even without a `pydantic`-style
   runtime validation layer.

**Design notes:**
- `@dataclass` for input/type generation as the default (zero extra runtime
  dependency, matches the project's core principle) — `pydantic` could be an
  opt-in variant later for runtime validation, mirroring Kotlin's
  data-class-vs-open-class config axis, but shouldn't be the default.
- HTTP: `httpx` (async-capable, closest thing to a modern stdlib-adjacent
  choice) vs `requests` (sync-only, no async story) — needs a decision; neither
  is truly zero-dependency the way JDK `HttpClient`/`URLSession` are.
- No real generics-as-constraints — Python's type hints are checked externally
  (mypy/pyright), not by the interpreter, so there's no analog to Kotlin/Swift's
  compiler enforcing correctness. Worth being explicit about this in docs/
  marketing copy so the type-safety claim isn't overstated.

---

## Where to start

Given the priority order above, **C# is the recommended first pick** — fastest
to ship (closest to existing patterns), and covers the biggest reachable
audience (Unity + enterprise .NET) with the least new design work. Go and Rust
both need real up-front design (error-handling model, HTTP-client dependency
decision) before they're "copy the template" work the way C# is. Python is a
different market entirely and can be sequenced independently of the other
three.
