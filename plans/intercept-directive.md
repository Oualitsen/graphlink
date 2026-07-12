# `@glIntercept` — a generic pre-execution interceptor directive

## Goal

Give server targets that have **no AOP** (primarily Apollo/Express) the same guarantee
Spring Boot gets from `@PreAuthorize` + AOP: **by the time execution reaches a service
method, a caller-authorization check has already run** — throw to deny, return to
proceed — without hand-written boilerplate in every resolver.

The mechanism is deliberately **generic**: not framework-specific ("make Apollo look
like Spring"), and not auth-specific in the model. It is a "run something before the
service executes" hook that *happens* to be the natural home for authorization. It
generalizes conceptually across every server target (Express, Spring Java, Spring
Kotlin).

```graphql
type Query {
  articles: [Article]                         # not intercepted
  getArticle(id: ID!): Article  @glIntercept(tag: "auth")
  adminStats: Stats             @glIntercept(tag: "admin")
}

# Object-level scopes to the fields DECLARED IN THIS BLOCK — not the merged type.
# Group the fields you want intercepted into an `extend` block that carries the
# directive; leave public fields in a plain block.
type Mutation {
  login(input: LoginInput!): Session          # not intercepted (public)
}

extend type Mutation @glIntercept(tag: "auth") {
  createArticle(input: CreateArticleInput!): Article   # intercepted
  deleteArticle(id: ID!): Boolean                       # intercepted
}
```

The developer implements **one** generated interface (like a Service) and dispatches on
a **tag**. No per-resolver code, no per-operation typed signatures.

---

## Background / relationship to prior work

An earlier plan (`typescript-server-auth-directive.md`, now **deleted**) proposed
`@glAuth(roles: [...])` implemented as an Apollo **schema-directive transformer**
(`mapSchema` + `getDirective`). That approach was rejected and replaced by this one
because it was **both** Apollo-specific (relies on `@graphql-tools` schema mapping that
has no analogue on other targets) **and** auth-specific (roles hard-modeled into the
directive). `@glIntercept` supersedes it: framework-agnostic, and auth is just the first
use of a generic before-hook.

Design decisions already settled during discussion (do **not** relitigate):

- **Object-level scopes to the declaring block, not the merged type.**
  `@glIntercept` on a `type`/`extend type` block applies to the fields declared **in
  that block only** — *not* to the fully-merged type. A developer groups the fields to
  intercept into an `extend type Query @glIntercept { … }` block and leaves public
  fields in a plain block.
- **Server-only — load-bearing, not incidental.** `@glIntercept`
  applies to generated **server** code only. This is the authorization guarantee, and
  authz is only real server-side: the client is untrusted (anyone can edit/bypass
  generated client code or hit the endpoint directly), so a client-side check enforces
  nothing while *looking* like security. The design is also server-shaped — positional
  args captured before input mapping, and a "throw = deny execution" contract gating a
  service call — neither of which transfers to a client that already holds typed args
  and is merely about to send a request. **The same schema drives both client and
  server generation, so a `client`-mode build must not fail on `@glIntercept`** — it is
  simply ignored there: `isIntercepted`/`interceptTag` still resolve correctly (schema
  semantics are mode-agnostic), but no `GlInterceptorTag` enum, no `GlInterceptor`
  interface, and no `runBefore` call site are ever emitted in client mode (see §1, §3,
  §6). If a client-side *pre-request* hook is ever wanted (telemetry, header injection,
  confirm-before-mutation),
  build it as a **separate** feature on the HTTP adapter/link layer with its own
  contract — do **not** overload `@glIntercept`, which would muddy the "throw = deny"
  semantics that make the server version trustworthy.
- **Opt-in by intent, via the directive.** The model is "secure *this* / intercept
  *that*", declared per resolver or per object. This is *not* an "always-called,
  can't-forget-it" coverage mechanism — an unannotated resolver is simply not
  intercepted, by design.
- **Uniform, positional, untyped args.** The interceptor receives operation args as a
  positional list ordered by **declared field-argument order**, captured **before**
  input-type mapping (`CreateArticleInput.fromJson(...)`). This is what keeps one
  signature working for `getArticle(id)`, `createArticle(input)`, `bulkCreate(matrix)`
  alike. Resource/ownership checks ("can this user edit article #5") need typed args and
  stay **out of scope** in the service body — same as Spring's
  `@PreAuthorize("@bean.canEdit(#id)")` escape hatch.
- **Contract:** `runBefore` throws → deny; returns normally → proceed to the service
  call. Identical to Spring.
- **Method name is `runBefore`** (not `intercept` — `intercept` implies OkHttp/gRPC
  around-style where the callee must proceed a chain; ours is a pure before-hook).
- **`tag` is an optional string** carried through to the interceptor (Flavor A).
  We explicitly did **not** adopt the "the `tag` names an interceptor class + name→impl
  registry" variant (Flavor B) — too much per-framework wiring for v1. Because `tag`
  is optional, bare `@glIntercept` still works and passes a `null` tag.
- **Tags are emitted as a generated enum** (`GlInterceptTag`) so the developer's
  dispatch `switch`/`when` gets compiler/IDE exhaustiveness help. (Strong in TS/Kotlin;
  Java's `javac` won't fail the build on a non-exhaustive `switch`, but IntelliJ hints
  it — accepted, we are not changing that.)

---

## Contract (the generated interface)

One interface per app, developer-implemented like a Service. Uniform core params
`(tag, operation, args, context)`; `info` is included only where the framework hands it
to the resolver (TS yes; JVM omits it).

**TypeScript** (`src/generated/interceptor/gl-interceptor.ts`):

```ts
export enum GlInterceptTag { Auth, Admin }   // members = sanitized distinct `tag`s

export interface GlInterceptor {
  runBefore(
    tag: GlInterceptTag | null,
    operation: string,
    args: unknown[],
    context: GraphLinkContext,
    info: GraphQLResolveInfo,
  ): Promise<void> | void;
}
```

**Java** (`GlInterceptTag.java` + `GlInterceptor.java`):

```java
public enum GlInterceptTag { AUTH, ADMIN }

public interface GlInterceptor {
   void runBefore(GlInterceptTag tag, String operation, java.util.List<Object> args, GraphQLContext context);
}
```

**Kotlin** (`GlInterceptor.kt`):

```kotlin
enum class GlInterceptTag { AUTH, ADMIN }

interface GlInterceptor {
   suspend fun runBefore(tag: GlInterceptTag?, operation: String, args: List<Any?>, context: GraphQLContext)
}
```

Example developer Impl (TS), exhaustive on the tag:

```ts
runBefore(tag, op, args, ctx) {
  switch (tag) {
    case GlInterceptTag.Auth:  requireUser(ctx); return;
    case GlInterceptTag.Admin: requireRole(ctx, "ADMIN"); return;
    case null: return;                       // bare @glIntercept
    // no default → TS flags a newly-added tag as unhandled
  }
}
```

---

## Design

### 1. Directive registration (parser)

`lib/src/model/built_in_dirctive_definitions.dart` — add the const names (mirror
`glCaptureErrors`):

```dart
const glIntercept = "@glIntercept";
const glInterceptTagArg = "tag";
```

`lib/src/model/new_parser/gl_parser.dart` — add to the `directiveDefinitions` map
(the block that contains `glCaptureErrors: GLDirectiveDefinition(...)`, ~line 178):

```dart
glIntercept: GLDirectiveDefinition(
  glIntercept.toToken(),
  [
    GLArgumentDefinition(
      glInterceptTagArg.toToken(),
      GLType("String".toToken(), true),   // nullable → optional; bare @glIntercept OK
      [],
    ),
  ],
  {
    GLDirectiveScope.QUERY,
    GLDirectiveScope.MUTATION,
    GLDirectiveScope.SUBSCRIPTION,
    GLDirectiveScope.FIELD_DEFINITION,
    GLDirectiveScope.OBJECT,            // object-level = fields declared in that block
  },
  false,
),
```

- Confirm bare `@glIntercept` (no `tag` supplied) parses cleanly given the nullable
  `String` arg. If the parser requires an explicit value for a declared arg, treat
  "directive present, `tag` absent" as `null` in the extension (§2), not a parse
  error. (Same open point the old `@glAuth` plan flagged for optional args.)
- These directives are **server-only** and must **not** produce any client-side
  artifact. Client-generated query documents only ever serialize selection sets, never
  the original type-declaration directives, so `@glIntercept` never leaks into emitted
  query text regardless of mode — nothing extra needed there. What *does* need gating
  is the **generated scaffolding**: `registerInterceptorTagEnum()` and
  `registerInterceptorInterface()` (§2/§3) both no-op unless
  `mode == CodeGenerationMode.server`, so a client-mode build of a schema that uses
  `@glIntercept` emits no `GlInterceptorTag` enum and no `GlInterceptor` interface —
  it simply proceeds as if the directive weren't there. Schema-level resolution
  (`isIntercepted`/`interceptTag`) stays mode-agnostic and still works in client mode
  (harmless — nothing in the client pipeline calls it), which is what lets the exact
  same schema drive both a client and a server build without special-casing.

### 2. Derivation extension (all logic lives here)

New `lib/src/parser_extensions/gl_grammar_intercept_extension.dart` — lazy getters on
`GLParser`. **No derivation in generators/serializers.**

Required API (names illustrative):

```dart
extension GlInterceptExtension on GLParser {
  /// True when this operation resolver must call runBefore:
  /// field carries @glIntercept, OR the `type`/`extend type` block that
  /// DECLARED this field carries @glIntercept.
  bool isIntercepted(GLQueryDefinition op);

  /// Resolved tag: field's `tag` if the field is annotated, else the tag on
  /// the declaring block, else null (bare). Most-specific-wins.
  String? interceptTag(GLQueryDefinition op);

  /// Distinct, non-null tags across the whole schema, in a stable order,
  /// used to generate the GlInterceptTag enum.
  List<String> distinctInterceptTags;

  /// Whether the schema uses @glIntercept anywhere (gates whether the
  /// interface/enum files are generated at all).
  bool get usesInterceptor;
}
```

**Key mechanism — object-level scopes to the declaring block, not the merged type.**
GraphLink merges `extend type X { … }` into a single `GLTypeDefinition`. The object-level
`@glIntercept` must apply only to the fields that were **lexically declared in the same
block** that carries the directive — not to every field of the merged type. The
implementer must therefore either (a) stamp each field, at parse/merge time, with the
`@glIntercept` present on its declaring block, or (b) retain per-field provenance
(which declaration block it came from) so the extension can look up that block's
directives. Verify how the existing `extend`/schema-merge path
(`gl_grammar_extension.dart`, `schema_merging/`) preserves — or discards — per-block
directives; this is the crux of the whole feature and the most likely place to get it
wrong. Without it, `extend type Query @glIntercept { … }` would wrongly intercept the
whole `Query` type.

Precedence rule (settled): **most-specific-wins.** Exactly one `runBefore` call per
resolver — never two (no block-level + field-level stacking; the "two checks" case is the
out-of-scope resource-level concern). Resolution order for the tag:

1. field-level `@glIntercept(tag:)` → that tag (may be null if bare on the field)
2. else the `@glIntercept(tag:)` on the field's declaring `type`/`extend type` block
3. else → not intercepted

### 3. Tag → enum generation & sanitization

The enum members come from `distinctInterceptTags`, sanitized to valid identifiers using
the **existing** per-language enum-value naming already used for `enum` definitions —
`NamingConvention.enumValue` (`lib/src/naming_convention.dart`: lowerCamel / PascalCase
for TS-ish, ScreamingSnake for Java/Kotlin) and the normalization pass in
`lib/src/parser_extensions/gl_grammar_normalization_extension.dart`
(`applyEnumValueNaming`). Do **not** invent a new sanitizer.

Edge cases to handle explicitly:

- **Collision:** two distinct tag strings that sanitize to the same member (e.g.
  `"read:x"` and `"read.x"`). Detect and raise a validation error (mirror the
  duplicate-name guarding in `sanitizeTypeNames`).
- **No tags but directive used** (all usages bare): generate an **empty** enum
  (`enum GlInterceptTag {}`) and keep the param typed `GlInterceptTag | null` (always
  `null`). Uniform, if slightly degenerate. (Alternative: fall back to a `string | null`
  param when there are zero tags — decide in review; empty-enum is recommended for
  cross-target uniformity.)
- Keep the wire tag string → enum member mapping in the extension so every serializer
  emits the same members and the same call-site member reference.

### 4. Express/Apollo serializer (v1 — the actual gap)

`lib/src/serializers/express_apollo_server_serializer.dart`
(+ `express_apollo_server_constants.dart` for fixed templates):

- Generate `src/generated/interceptor/gl-interceptor.ts` (enum + `GlInterceptor`
  interface) **only when `usesInterceptor`**.
- The interceptor instance is supplied through the existing services object passed to
  `createServer` — add `interceptor?: GlInterceptor` to `GraphLinkServices` (same shape
  the deleted `@glAuth` plan used for `authService`). If `@glIntercept` is used and no
  interceptor is provided, fail fast at server start with a clear error.
- In each generated resolver for an intercepted operation, insert the call as the
  **first statement**, building the positional args array in declared field-arg order
  **before** any input mapping:

  ```ts
  getArticle: async (parent, args, context, info) => {
    await services.interceptor.runBefore(GlInterceptTag.Auth, "getArticle", [args.id], context, info);
    // …existing resolver body (input mapping, service call) unchanged…
  }
  ```

  - `tag` argument is the resolved enum member (or `null` for bare).
  - `args` array: `[args.<argName>, …]` in declared order (raw, pre-mapping). Zero-arg
    operations pass `[]`.

### 5. JVM Spring serializers (v2 — port after Express lands)

Shared JVM logic lives in `jvm_spring_controller_serializer_base.dart` (with
`java_spring_controller_serializer.dart` / `kotlin_spring_controller_serializer.dart`
specializing). Note: Spring targets *already* have the `@PreAuthorize` + AOP path via
`@glAnnotation`, so `@glIntercept` is for **consistency**, not because they lack the
guarantee — hence v2.

- Generate `GlInterceptTag` enum + `GlInterceptor` interface files (Java/Kotlin variants
  from §Contract), gated on `usesInterceptor`.
- The controller obtains the interceptor by **single-bean injection** (constructor or
  `@Autowired`) — one interface, one bean, no name→impl registry (Flavor A). Developer
  provides a `@Component` implementing `GlInterceptor`.
- **Placement is the delicate part:** the call must go **above** the existing
  `Xxx.fromJson(...)` line in the controller method, because that is where typed mapping
  currently happens first — the whole point is to run before mapping. Build the
  positional `List<Object>` from the **raw** method params (JSON strings / scalars) in
  declared order:

  ```java
  // generated controller method, intercepted:
  glInterceptor.runBefore(GlInterceptTag.AUTH, "createArticle", java.util.List.of(inputJson), graphQlContext);
  CreateArticleInput input = CreateArticleInput.fromJson(inputJson);   // existing line, now second
  return articleService.createArticle(input) …;
  ```

- Verify context propagation across the existing async hop: `java_server` wraps service
  calls in `CompletableFuture.supplyAsync(...)` (ForkJoinPool). The `runBefore` call must
  execute on the **request thread, before** `supplyAsync`, so it sees the real
  `SecurityContext`/request scope — placing it as the first statement of the controller
  method (before the future is constructed) satisfies this. Do **not** move it inside the
  `supplyAsync` lambda. (Kotlin `withContext(Dispatchers.IO + SecurityCoroutineContext())`
  already propagates; still emit `runBefore` before entering the withContext block.)
- Kotlin `runBefore` is `suspend` — call it with the surrounding coroutine builder the
  controller already uses.
- `info` is omitted from the JVM signature (framework doesn't hand a
  `GraphQLResolveInfo` equivalent to the controller). Keep `(tag, operation, args,
  context)` uniform across Java/Kotlin.

### 6. Validation

Implemented in `lib/src/parser_extensions/gl_grammar_intercept_extension.dart`, wired
into `GLParser.validateSemantics()` (mode-agnostic — these are schema-correctness
checks, not target-specific, so they run for both client and server builds):

- `validateInterceptPlacement()`: `@glIntercept` allowed only on Query/Mutation/
  Subscription root fields, and on those root **objects** (`type`/`extend type`
  blocks) — errors on a plain object/interface/input field or a non-root object block
  (this codebase never enforces `GLDirectiveDefinition.scopes` against usage at parse
  time, so this check is the only thing standing between a misplaced directive and it
  silently doing nothing). (v-next) `@glSkipOnServer` mapping fields.
- `validateInterceptTagValues()`: tag must be a non-blank string, and tag collision
  after sanitization (§3) → error.
- **Server-only is NOT a validation error.** `@glIntercept` is silently ignored in a
  `client`-mode build (§1) — no enum, no interface, no error. Only the *generation*
  steps (`registerInterceptorTagEnum()`, `registerInterceptorInterface()`) are
  mode-gated; nothing here rejects the schema based on mode.

---

## Open questions (for the implementer to resolve in review)

1. **Empty-enum vs `string | null`** when the schema uses only bare `@glIntercept`
   (§3). Recommendation: empty enum for uniformity.
2. **Bare-directive parsing** — confirm `@glIntercept` with no `tag` parses given the
   optional nullable arg, or add the "present-but-absent ⇒ null" handling in the
   extension (§1).
3. **`@glSkipOnServer` mapping fields** (batch/non-batch relation resolvers) — should
   they be interceptable in v1, or is v1 limited to root operation fields? Recommended:
   root operations only for v1; extend later.
4. **Where the interface/enum files live** per target and how they’re wired into the
   barrel/index generation (`barrel_file_handler.dart`).
5. **Client SDL stripping** mechanism for the two directives (§1) — confirm the existing
   server-only-directive path covers them.

---

## Test plan

### Unit (`test/intercept/`, inline `const` schemas per CLAUDE.md)

- field-level `@glIntercept(tag:"auth")` → resolver emits
  `runBefore(GlInterceptTag.Auth, "op", [..], ctx …)` as first statement.
- bare `@glIntercept` → `runBefore(null, …)`.
- object-level on `extend type Mutation @glIntercept(tag:"auth")` → only fields declared
  **in that block** emit the call; a field of the same `Mutation` declared in a plain
  (unannotated) block emits **no** call. **most-specific-wins** when a field in the
  annotated block also carries its own `@glIntercept`.
- distinct tags → correct `GlInterceptTag` members per language
  (TS Pascal/camel, Java/Kotlin ScreamingSnake).
- tag-collision schema → validation error.
- args array ordering: multi-arg op → `[args.a, args.b]` in declared order; zero-arg →
  `[]`.
- JVM: `runBefore(...)` line emitted **above** `fromJson(...)` and **before**
  `supplyAsync`/`withContext`.
- no `@glIntercept` anywhere → interface/enum files not generated.

### End-to-end (`server_integration_tests/`)

Extend the Author/Article matrix schema:

- `getArticle @glIntercept(tag:"auth")`, `adminStats @glIntercept(tag:"admin")`,
  an `extend type Mutation @glIntercept(tag:"auth")` block grouping the protected
  mutations, with a public mutation left in a plain `type Mutation` block, and
  unannotated query controls.
- Hand-write a `GlInterceptor` Impl per server target: `"Bearer admin"` → allow all;
  `"Bearer user"` → allow `auth`, throw on `admin`; no header → throw on any tag.
- Drive with the existing clients (dart/ts/java/kotlin): assert denied ops surface the
  thrown error and the service body did **not** run; allowed ops proceed. Start with
  the **TypeScript server** target (v1).

---

## Task list

- [ ] Register `@glIntercept(tag:String)`
      (`built_in_dirctive_definitions.dart` + `gl_parser.dart` directive map, scopes incl. OBJECT)
- [ ] Strip `@glIntercept` from client SDL/queries (server-only)
- [ ] **Per-block scoping**: ensure object-level `@glIntercept` on a `type`/`extend type`
      block binds only to fields declared in that block (stamp/provenance at merge time —
      the crux; see §2)
- [ ] `gl_grammar_intercept_extension.dart`: `isIntercepted`, `interceptTag`
      (most-specific-wins), `distinctInterceptTags`, `usesInterceptor`
- [ ] Tag→enum sanitization via existing `NamingConvention.enumValue` +
      `applyEnumValueNaming`; collision detection
- [ ] Validation (`gl_validation_extension.dart`): scopes, collisions, server-only
- [ ] **v1** Express: generate `gl-interceptor.ts` (enum+interface), add
      `GraphLinkServices.interceptor`, insert `runBefore` first in each intercepted
      resolver with pre-mapping positional args
- [ ] `test/intercept/` unit suite
- [ ] `server_integration_tests` TS-server e2e (schema + Impl + client assertions)
- [ ] **v2** JVM: generate Java/Kotlin enum+interface, single-bean injection, insert
      `runBefore` above `fromJson` / before `supplyAsync`/`withContext`
- [ ] **v2** JVM e2e across java/kotlin servers
