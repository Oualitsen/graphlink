# Serializer split and shared client-operation base

Status: audit done, nothing implemented. Everything listed was measured (line counts, method names). Bodies were
read only where noted ("bodies read"); duplication claims elsewhere come from identical signatures and are
labelled as such.

## Why

- Large serializer files cost an AI agent many tokens to change one thing, and mix unrelated responsibilities.
- The client operation serializers share an unwritten interface that nothing declares, so an agent adding a
  language or a feature has no single place that says what a client operation serializer must provide.
- Some derivation logic is duplicated in serializers, against the rule that derivation lives in the IR
  (`gl_grammar_*_extension.dart` / model getters).

`*_constants.dart` runtime templates are out of scope (decided earlier: do not refactor them).

## Measured sizes (lines, `lib/src/serializers/`, excluding `*_constants.dart`)

| File | Lines |
|---|---|
| `client_serializers/java/java_client_serializer.dart` | 2151 |
| `dart/flutter_inputs/flutter_inputs_state_serializer.dart` | 1728 |
| `client_serializers/dart/dart_client_serializer.dart` | 1427 |
| `java/java_serializer.dart` | 1223 |
| `client_serializers/kotlin/kotlin_client_serializer.dart` | 1052 |
| `typescript/express_apollo_server_serializer.dart` | 1036 |
| `client_serializers/python/python_client_serializer.dart` | 993 |
| `client_serializers/typescript/typescript_client_serializer.dart` | 971 |

## Part 1: split `java_client_serializer.dart` (do first)

One class (`JavaClientSerializer`) with about 25 `generate*File` methods:

- `generateClient`, constructors, persisted-call helpers (top, ~lines 162 to 900)
- `generateGraphLinkResolverBaseFile`: one method, about 495 lines (918 to 1412)
- subscription listener / graphql-ws message types / subscription handler (1413 to ~1450)
- exception file, upload progress callback, multipart adapter (1447 to ~1560)
- persisted queries and GET files (1550 to ~1627)
- reactive / WebClient default adapters and their multipart members (1628 to 2151)
- REST files: `generateRestFiles` (452 to ~600) plus the REST-only helpers at the top

Proposed split by responsibility, each a separate class that receives the shared context
(`JavaClientContext`, grammar, flavor) as a constructor argument, the way `JavaClientOperationSerializer` and
`java_reactive_flavor.dart` already do:

- `JavaClientSerializer`: orchestration only (`generateClient`, which files exist).
- resolver base (the 495-line method),
- blocking / reactive / WebClient adapters (incl. GET and multipart variants),
- REST file generation,
- persisted queries + subscriptions + exception.

Rules for the split:

- Pure move, no behaviour change. Generated output must be byte-identical: compare the generated Java client of
  `integration_tests/mock/java_client_tests` and the REST packages before and after (diff the generated tree, do
  not run the full test suite).
- Keep the public entry points `GLClientSerializer` expects (`generateClient`, `generateUploadsFile`, ...)
  on `JavaClientSerializer` and delegate.
- Kotlin (1052) and Dart (1427) client serializers are candidates for the same treatment afterwards; look at
  Java first, then decide whether the same cut lines apply.

## Part 2: `java_serializer.dart` (optional, lower priority)

Mixes enum/type/input emission, accessors and builders, from/to JSON, `@glMapsTo` mapping methods, equals/hashCode,
interface emission and the REST discriminator. Extract three groups:

- mapping methods `generateToMethod` / `generateFromMethod` and their helpers (about 190 lines, 458 to 645),
- accessors and builders (`serializeGetter`, `serializeSetter`, `generateBuilder`, `getterName`, ...),
- REST discriminator (`_discriminatedFromJson`, `_serializeFromJsonForInterface`).

Note `generateToMethod` / `generateFromMethod` exist in every language serializer (declared in
`gl_serializer.dart`), so any extraction for Java should be shaped so it can be repeated for Kotlin (765),
Swift, Go, Dart and Python.

## Part 3: shared base for client operation serializers

### Finding

- `GLClientSerializer` (`gl_client_serializer.dart`, 271 lines) is extended by the 7 `*ClientSerializer` classes.
- The 14 operation serializer classes (7 `*ClientOperationSerializer`, 7 `*RestOperationSerializer`) extend nothing.
- The client operation serializers use the same method set under the same names: `queryToMethod`,
  `mutationToMethod`, a cached-query body, `_serializePartialQuery`, `_serializeInvalidationCall`,
  `_resolveArgType`, `getArguments`, `returnTypeByQueryType`, `_generateVariables`, `_variablesExpr`,
  `_serializeArgumentValue`, `_callToJson` (seen in Dart, Kotlin, Swift, Python, Go, TypeScript, Java listings).
- `GLClientSerializer` already provides `shouldInvalidateAll`, `getInvalidationTags`, `isUploadMutation`,
  `getFragmentsForDef`, `divideQuery`. Dart, Python and TypeScript operation serializers redeclare private copies
  (one-liners read at the top of those files; Go has similar helpers, not read in full).

### Step A: move derivation into the IR

The redeclared helpers are derivation (for example `def.elements.any((e) => e.cacheInvalidateAll)`), which the
project rules place in the IR. Move them to `GLQueryDefinition` or a `gl_grammar_*_extension.dart` getter, switch
`GLClientSerializer` and all operation serializers to those getters, and delete the private copies. Start with
the five helpers listed above.

### REST operation serializers (read in this pass)

The 7 `*RestOperationSerializer` classes (Dart 308, Kotlin 319, Swift 323, Python 344, Go 362, TypeScript 362,
Java 384 lines) are the strongest duplication in the client side:

- They share about 20 methods with the same names and the same order: `operationToMethod`, `_signature`,
  `_returnType`, `_requestExpression`, `_pathExpression`, `_headers`, `_contentTypeEntries`, `_headerEntry`,
  `_entries`, `_entry`, `_bodyStatements`, `_nullGuard`, `_collected`, `_partEntries`, `_partEntry`, `_execution`,
  `_cachedReturn`, `_invalidation`, `_isUpload`, `_hasProgress`, `_bodyMayBeNull`, `_nonNull`, `_escapeLiteral`,
  `_listOptions`.
- **Identical derivation, copied per language (bodies read in Dart and Kotlin; one-liners seen in all 7):**
  - `_isUpload(a)` = `uploadScalarNames.contains(a.argument.type.firstType.token)`;
  - `_hasProgress(op)` = `bodyKind` is `raw` or `multipart`;
  - `_bodyMayBeNull(op)` = `bodyKind` is `form` or `multipart`, else the body argument is nullable;
  - `_nonNull(type)` (`GLListType(type.type, false)` or a non-null `GLType`), present in Dart, Kotlin, Python,
    TypeScript and Java.
- **Same algorithm, different quoting (bodies read in Dart and Kotlin):**
  - `_pathExpression` walks `restPlaceholder` matches over `op.path`, escapes the literal parts and substitutes
    path arguments. Only the quote character, the encode function and the escape rules differ.
  - `_contentTypeEntries` is the same decision tree (`switch` on `bodyKind`, then nullable or not, raw uses
    `mimeType` or the declared type). Only the emitted syntax differs.
- Go differs most (options struct, `_isOptional`, `_required`/`_optional`, `_failure`) and has no `_bodyMayBeNull`.
  Java additionally has overloads, reactive flavors and a context container; Swift and Go have no `_nonNull`.

Consequences for Step A: the three one-liners above and `_nonNull` move to the IR (`GLRestArgument` /
`GLRestOperation` / `GLType`). The path walk and the content-type decision should also be IR data (for example
`op.pathSegments` as a list of literal-or-argument parts, and a resolved content-type source), so each language
serializer only quotes and joins. That removes most of the 20 methods' logic, not just the helpers.

### Step B: declare the contract

- `GLClientOperationSerializer` (abstract): declares the shared method set with a doc comment on each saying what
  it returns and when it is called (for example: argument list, return type, variables expression, partial-query
  emission, invalidation call). Does not contain language logic.
- `GLRestOperationSerializer` (abstract): same for the 7 REST operation serializers. See the REST findings below.
- Languages differ in shape (Go has an options struct; Kotlin and Java take a `GLImportContainer`; Java is
  async-flavored; TypeScript has `uploadMutationToMethod`). The base declares only what is truly common; the
  rest stays per language.

### Adoption rule

A base class nobody extends misleads more than it helps, because it reads as authoritative. So at least Dart
and one other language (suggest Python, closest in size) extend the new base in the same change. The remaining
languages migrate afterwards, one per change.

### ARCHITECTURE.md

Add a short section for the operation serializers: their file locations, the contract above, and the Java
client serializer parts after the split. Update the "Client operation serializers" table, which currently lists
per-language files but not what they share.

## Part 4: `flutter_inputs_state_serializer.dart` (1728 lines, read this pass)

One class, `FlutterInputsStateSerializer`, built almost entirely with `_u.createMethod` / `DartCaseStatement`
(so it already follows the CodeGenUtils rule). It emits several unrelated generated pieces:

- `serializeWidgetClass` (30 to 157) and `serializeStateClass` (157 to ~369), the composition of the state class;
- reset, dirty, scroll-to-first-error, error notifier, scroll-to-field (369 to 546, 1516 to 1590);
- build, validate, read/tryRead, build-result, visible rows (547 to 800);
- widget helpers: required label, label with info, floating info, field helper, switch/checkbox helpers,
  decoration helpers, clear button, intersperse (809 to 1079, about 270 lines);
- stepper: build-steps, scalar rows, validate-and-read-current-step, continue/cancel, step controls
  (1245 to 1462, about 220 lines);
- async validation scheduling (1472 to 1515);
- `serializeErrorSummaryClass` (1592 to 1714), a separate generated class.

Sibling files already exist for the same family (`flutter_inputs_draft_serializer`, `_date_serializer`,
`_radio_binding`, `_companion_serializer`, `_field_serializer`, `_shared_serializer`), so the precedent is set.
Proposed extractions, in order of cleanliness: error-summary class, stepper, widget helpers, async validation.
Keep `serializeStateClass` as the composer. Same acceptance bar: generated Flutter output unchanged.

## Part 5: `express_apollo_server_serializer.dart` (1036 lines, read this pass)

One class, about 45 methods, `extends ServerSerializer with ServerSerializerUtils`. `ServerSerializer` is 17 lines
and `ServerSerializerUtils` 29, so the Express serializer shares almost nothing with the Spring bases
(`jvm_spring_*_base`). Clusters in the file:

- entry point and server setup: `serializeEntryPoint` (708 to 857, about 150 lines), `_wsContextOption`,
  `_registerMiddleware`, upload declarations;
- resolvers: `_serializeResolvers`, root and subscription blocks, `_argsDestructure`, `_entry` (355 to 605);
- type mappings and loaders: `serializeLoader`, `_loaderFactory`, `_serializeTypeMappings`,
  `_mappingResolver`, `_mappingRunBeforeStatement` (251 to 354, 606 to 705);
- services and guards: `serializeService`, `serializeGuard`;
- context and interceptors: `serializeContext`, `serializeContextStub`, `serializeInterceptorInterface`,
  `_interceptorTagCallArg`, `_runBeforeStatement`;
- referenced-type collection for imports: `_collectType`, `_addIfKnown`, `_imports` (960 to 995). This is
  derivation ("which types does this field reference") and belongs in the IR or `ServerSerializerUtils`, not here.

Proposed: split into entry point, resolvers, loaders and mappings, context and interceptors; move the type
collection to the IR. `_RootEntry` and `_MappingEntry` (private data classes at 997 and 1032) go with the parts
that use them. Note the enums-as-strings plan (`plans/enums-as-strings.md`) touches lines ~388, ~430, ~540, ~967
of this file, so do the enum change first or the split first, not both at once.

## Suggested order

1. Part 1 (Java client serializer split), verified by generated-output diff.
2. Part 3 step A (IR getters, delete the duplicate helpers), starting with the REST ones: the three one-liners,
   `_nonNull`, then path segments and content type.
3. Part 3 step B (abstract bases, Dart + Python adopt, ARCHITECTURE.md). REST has the cleanest contract of the two.
4. Part 4 (Flutter state serializer extractions), independent of the others.
5. Part 5 (Express split), coordinate with the enums-as-strings work.
6. Part 2 (`java_serializer.dart`), then the same cut for the Kotlin and Dart client serializers.

## Open questions

1. Split mechanism for Part 1: separate classes with a shared context (my suggestion, matches the existing
   operation serializer pattern) or Dart `part` files / extensions on one class? Classes keep each file readable
   alone; `part` files keep one class but do not reduce what an agent must understand.
2. Is byte-identical generated output the acceptance bar, or are you fine with incidental changes?
3. Should Part 3 step A (IR getters) be its own PR before the base classes?
4. Does the 495-line `generateGraphLinkResolverBaseFile` count as a runtime template (leave as is, moved intact),
   or as serializer logic that should go through `*CodeGenUtils` more fully?
5. REST path and content type: are you comfortable with the IR exposing `pathSegments` and a resolved
   content-type source (small structured data per operation), so serializers only quote and join?
6. Express and Spring server serializers share almost nothing today. Is aligning Express with the
   `JvmSpring*` base structure (a common server contract) in scope, or only the internal split?
