# HOWTO Generation

## Goal

Generate a `GRAPHLINK_client.md` (or `GRAPHLINK_server.md`) file alongside the generated
code on every `glink` run.
The file is **targeted at AI agents**, not humans — dense, structured, no narrative fluff.
It describes the exact generated API for the current schema and config so an agent can
use the generated client without reading 30+ generated files.

---

## Key Decisions

- **Always generated** — no config flag, no opt-in. It is part of the output, full stop.
- **File names**: `GRAPHLINK_client.md` for client runs, `GRAPHLINK_server.md` for server runs.
  No language suffix — the language is implicit from `outputDir`.
- **Output location**: directly in `outputDir` (root), not in a subdirectory.
- **Regenerated on every `glink` run** — always in sync with the schema.
- **Config-aware**: content reflects active options (`captureErrors`, `inputAsRecord`,
  `observables`, `immutableInputFields`, etc.).

---

## Architecture

### New files

```
lib/src/serializers/client_serializers/howto/
  howto_serializer.dart               ← abstract base
  dart_howto_serializer.dart          ← Dart implementation
  java_howto_serializer.dart          ← Java implementation
  typescript_howto_serializer.dart    ← TypeScript implementation
```

### Abstract base — `HowtoSerializer`

Owns the document skeleton: header, section ordering, iteration over operations/inputs/enums.
Language subclasses override only the language-specific rendering methods.

```dart
abstract class HowtoSerializer {
  final GLParser parser;
  final GeneratorConfig config;

  HowtoSerializer(this.parser, this.config);

  String get languageName;   // "Dart" | "Java" | "TypeScript"
  String get fileName => 'GRAPHLINK_client.md';

  String generate(); // assembles all sections in order

  // --- overridden per language ---
  String renderHeader();        // #GRAPHLINK + #CFG lines
  String renderInit();          // #INIT block
  String renderPatterns();      // #PATTERNS block (call conventions + ERR)
  String renderOp(GLQueryDefinition q);   // one Q/M/S line with response field notation
  String renderInput(GLInputDefinition i); // one #INPUTS line
  String renderEnum(GLEnumDefinition e);   // one #ENUMS line
  String renderRules();         // #RULES block
}
```

The base `generate()` method calls the above in a fixed order:
1. `#GRAPHLINK` header line (lang + date)
2. `#CFG` line (active config flags)
3. `#INIT` block (constructor overloads)
4. `#PATTERNS` block (call conventions, error handling — always present)
5. `#OPS` block — Q/M/S lines (skipped entirely if none)
6. `#INPUTS` block (skipped if none)
7. `#ENUMS` block (skipped if none)
8. `#RULES` block (always present — at minimum the "never modify generated files" rule)

Sections are omitted entirely when empty — no empty content in the output.

Section order: `#GRAPHLINK` → `#CFG` → `#INIT` → `#PATTERNS` → `#OPS` → `#INPUTS` → `#ENUMS` → `#RULES`

### Language subclasses

Each subclass overrides the render methods to produce language-correct code snippets.
Nothing else differs — the structure and ordering are fixed in the base.

| Subclass | File |
|---|---|
| `DartHowtoSerializer` | `dart_howto_serializer.dart` |
| `JavaHowtoSerializer` | `java_howto_serializer.dart` |
| `TypeScriptHowtoSerializer` | `typescript_howto_serializer.dart` |

---

## Integration

One `writeToFile` call added at the **end** of each `generate*ClientClasses()` function,
right before `cleanUpObsoleteFiles()`.

```dart
// dart_client_generator.dart
futures.add(writeToFile(
  data: DartHowtoSerializer(parser, config).generate(),
  fileName: 'GRAPHLINK_client.md',
  subdir: '',
  imports: [],
  destinationDir: destinationDir,
));
```

Same pattern for `java_client_generator.dart` and `typescript_client_generator.dart`.
For `server_generator.dart`, filename is `GRAPHLINK_server.md` and the serializer
class is `SpringHowtoSerializer`.

No changes to `main.dart`, `config.dart`, or the core engine.

---

## Data available from `GLParser`

| Data | Source |
|---|---|
| All operations (queries/mutations/subscriptions) | `parser.queries` (Map<String, GLQueryDefinition>) |
| Operation type | `q.type` → `GLQueryType.query \| mutation \| subscription` |
| Operation arguments | `q.arguments` → `List<GLArgumentDefinition>` |
| Cache TTL | `q.cacheTTL` (0 = no cache) |
| Cache tags | `q.cacheTags` |
| Invalidate tags | `q.invalidateCacheTags` |
| Invalidate all | `q.cacheInvalidateAll` |
| Input types | `parser.inputs` (Map<String, GLInputDefinition>) |
| Enum types | `parser.enums` (Map<String, GLEnumDefinition>) |
| Response types | `parser.projectedTypes` |
| Has subscriptions | `parser.hasSubscriptions` |

Config-aware flags read from `config.clientConfig!.language` (cast to the appropriate subtype).

---

## Document Format

**Target audience: LLMs only. Optimize for information density, not readability.**

The format is dense flat text — no YAML, no markdown headers, no prose. Every byte earns its place.
One file covers the entire client. Do not split per-entity.

Notation:
- `!` = required, `?` = optional, `?=X` = optional with default
- `Q` / `M` / `S` = query / mutation / subscription
- `→ XResponse(field:Type)` = response wrapper class + the field name the agent must access
- `@cache(Ns [tag1,tag2])` = cached with TTL and tags
- `@invalidates([tag1,tag2])` = mutation invalidates these tags
- `@invalidatesAll` = mutation invalidates entire cache

```
#GRAPHLINK DART 2026-05-24
#CFG captureErrors:false immutableInputs:true

#INIT
GraphLinkClient.withHttp(url:String!, wsUrl:String!, [headersProvider:fn?, wsHeadersProvider:fn?, store:GraphLinkCacheStore?])
GraphLinkClient.fromUrl(adapter:fn!, wsUrl:String!, [wsHeadersProvider:fn?, store:?])
GraphLinkClient(adapter:fn!, wsAdapter:GraphLinkWebSocketAdapter!, [store:?])

#PATTERNS
Q: await graphlink.queries.X(arg:val)     → Future<XResponse>  → res.fieldName:Type
M: await graphlink.mutations.X(arg:val)   → Future<XResponse>  → res.fieldName:Type
S: graphlink.subscriptions.X(arg:val)     → Stream<XResponse>  → .listen((res) => res.fieldName)
I: InputType(requiredField:val, [optionalField:val])
ERR(captureErrors=false): catch(e){ e as List<GraphLinkError> }
ERR(captureErrors=true): res.data:T? res.errors:List<GraphLinkError>? res.hasErrors:bool

#OPS
Q getCar(id:String!) → GetCarResponse(getCar:Car) @cache(60s)
Q getCarAndOwner(carId:String!, ownerId:String!) → GetCarAndOwnerResponse(car:Car, getOwner:Owner) @cache(60s [cars,data][persons,data])
M createCar(input:CreateCarInput!) → CreateCarResponse(createCar:Car) @invalidates([cars])
S counter() → Stream<CounterResponse>(counter:int)

#INPUTS
CreateCarInput: make:String! model:String! year:int! ownerId:String?

#ENUMS
UserRole: ADMIN|USER|GUEST

#RULES
- never modify files under generated/
- never call graphlink internals (__ prefixed fields/methods)
- cache is automatic — do not manage it manually
- subscription streams must be cancelled to avoid leaks
```

Language variations:
- **Java** `#PATTERNS`: `client.queries().X(arg)` returns `CompletableFuture<XResponse>`;
  subscriptions use a callback `client.subscriptions().X(arg, handler)`;
  input construction uses builder (`XInput.builder().field(val).build()`) unless `inputAsRecord:true`.
- **TypeScript** `#PATTERNS`: `await client.queries.X({arg:val})` returns `Promise<XResponse>`;
  if `observables:true`, returns `Observable<XResponse>` instead.

---

## Config-aware behaviour

| Config flag | Effect on HOWTO |
|---|---|
| `captureErrors: true` | `#PATTERNS ERR` shows `FullResponse` pattern; `#CFG` reflects it |
| `inputAsRecord: true` | Java `#PATTERNS I` shows record syntax instead of builder |
| `typeAsRecord: true` | Java `#PATTERNS` field access shows component accessor instead of getters |
| `observables: true` | TypeScript `#PATTERNS Q/M` shows `Observable<T>` instead of `Promise<T>` |
| `immutableInputFields: false` | `#CFG immutableInputs:false`; `#RULES` notes fields are mutable |
| `httpAdapter` / `wsAdapter` | `#INIT` shows correct adapter class name |

---

## What does NOT go in the HOWTO

- Narrative, explanation, or motivation
- Per-field metadata (validation rules, semantic types, server-only flags)
- Links to docs
- Configuration reference
- Anything a human developer would want but an agent does not need
- Per-entity files — one file covers the entire client
