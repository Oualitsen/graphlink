# Action plan — Step 1: ship hoisted (propagated) args in an input object

> The hardest, highest-value step. Group an operation's propagated arguments into
> a synthesized input object instead of flat parameters, fixing the unusable
> signatures (esp. Java positional explosion). Ordered checklist for *just this
> step*. Skip cap / config key / docs are later (see `auto-query-argument-limit.md`).

## Architecture (swap in `def.arguments`)
The synthesis **mutates the operation's argument list**: it removes the propagated
args and inserts ONE synthetic arg whose type is the synthesized `<Op>FieldArgs`
input. Consequence:
- **Method signatures fall out for free.** `getArguments` already iterates
  `def.arguments`; the synthetic arg renders as a normal object param. No
  per-language signature change.
- **The GraphQL wire still needs the flat `$variables`,** so the two consumers
  that build wire-level variable lists must *expand* the synthetic arg back into
  its input's fields: the shared query-string serializer and each language's
  variables map.

No `declaredArguments`/`generatedArguments` getters and no `generatedArgsInput`
back-ref on the query are needed — the arg list itself is the source of truth.

## Naming & nullability
- **Type name:** `<Op>FieldArgs` (e.g. `GetCompaniesFieldArgs`); index-suffix on
  collision vs existing type/input/enum/interface/union/scalar names.
- **Param name:** `fieldArgs`; index-suffix on collision vs the operation's
  remaining (declared) arg `codeName`s. Synthetic arg token = `$fieldArgs` so
  `bareName`/`codeName` resolve to `fieldArgs`.
- **Object nullability:**
  `objectRequired = extracted.any((a) => !a.type.nullable && a.defaultValue == null)`.
  Synthetic arg type = the input type, nullable iff `!objectRequired`.
- **Field nullability inside the object** mirrors each arg's `type` — emitted for
  free by the existing input serializer.

## New model bits
- `GLArgumentDefinition.isDeclared` — `bool`, **default `true`**; set `false` for
  propagated args (1.1).
- `GLArgumentDefinition.hoistArgsInput` — `GLInputDefinition?`, default `null`;
  set on the synthetic arg so serializers detect & expand it (1.2).
- `GLQueryDefinition.removeArgument(String token)` — drop an entry from the
  private `_arguments` map (1.2 needs it).

---

## Steps

### 1.1 — `isDeclared` flag + set it
**File:** `lib/src/model/gl_argument.dart`
- Add `final bool isDeclared;`, ctor param `{this.isDeclared = true, this.defaultValue}`.
**File:** `lib/src/gl_grammar_projection_extension.dart`, `_addGeneratedArgument` (~862)
- Both `setArgument(GLArgumentDefinition(...))` calls (merge ~882, fresh ~887)
  build propagated args → pass `isDeclared: false`. Declared args (early-return
  ~865) keep the default `true`.
**Verify (parser test):** projected-field `$var` not declared on the op ⇒ that
op has an arg with `isDeclared == false`; its own declared args stay `true`.

### 1.2 — Hoist pass in a dedicated extension
**New file:** `lib/src/gl_grammar_hoist_args_extension.dart` (matches the
`gl_grammar_*_extension.dart` family; derivation logic lives in extensions).
- `extension GLHoistArgs on GLParser { void groupHoistedArgsIntoInputs() { … } }`:
  for each `def` in `queries.values` with any `!isDeclared` arg:
  1. `extracted = def.arguments.where((a) => !a.isDeclared).toList()`;
  2. `for (a in extracted) def.removeArgument(a.token);`
  3. resolve unique `<Op>FieldArgs` name (collision-suffix vs all type maps);
  4. build `GLInputDefinition` with one `GLField` per `extracted` arg
     (name `a.bareName`, type `a.type`, initialValue `a.defaultValue?.value`);
  5. `inputs[name] = input;`
  6. `objectRequired = extracted.any((a) => !a.type.nullable && a.defaultValue == null);`
  7. build synthetic `GLArgumentDefinition('\$' + paramName, GLType(inputNameToken,
     nullable: !objectRequired), [])`, set `..hoistArgsInput = input`, and
     `def.setArgument(it)`.
- **`GLQueryDefinition.removeArgument`** (`gl_queries.dart`): `_arguments.remove(token)`.
- **Call site:** `gl_parser.dart`, immediately after
  `propagateFieldArgumentVariables();` (line 322), **before** `createProjectedTypes();`
  (337) so the input enters projected types + import graphs.
**Verify (parser test):** explosion schema ⇒ propagated args gone from
`def.arguments`; exactly one arg with `hoistArgsInput != null`; `inputs['<Op>FieldArgs']`
present with one field per extracted arg, nullability mirrored.

### 1.3 — Method signatures (NO CHANGE — verify only)
- `getArguments` iterates `def.arguments` ⇒ declared params + the synthetic object
  param, automatically. Object param nullability follows the synthetic arg's type
  (required vs optional) via existing per-language rules.
**Verify:** generated client compiles; signature = declared params + `fieldArgs`
object (required/optional per rule).

### 1.4 — Query-string serializer: expand the synthetic arg (shared, 1 file)
**File:** `lib/src/serializers/gl_graphql_serializer.dart`
- **`serializeQueryDefinition` (347):** when mapping `def.arguments`, if
  `arg.hoistArgsInput != null` emit one flat declaration per input field
  (`\$<field>: <Type><= default>`) instead of `serializeArgumentDefinition(arg)`.
  Helper: GLField → `$name: Type[ = initialValue]`.
- **`divideQueryDefinition` (357–373):** `usedVariables` are flat `$var` names from
  each element. Build `elementArguments` from declared args **plus** the
  hoist-input fields whose `$name` ∈ `usedVariables`; emit their `variables` and
  `argumentDeclarations` the same way. Without this, partial queries silently drop
  hoisted vars.
**Verify:** generated query string declares flat `$field` vars (never
`$fieldArgs`); divided/partial queries still declare the hoisted vars they use.

### 1.5 — Variables map: expand the synthetic arg, per language (×4)
**Files:** `client_serializers/<lang>/<lang>_client_operation_serializer.dart`,
`generateVariables(def)` (and partial/multipart variants iterating `def.arguments`).
- Declared args: unchanged.
- Synthetic arg (`hoistArgsInput != null`): emit one map entry per input field,
  `'<wireName>': <fieldArgs>.<fieldCodeName>`.
  - object **required** → direct.
  - object **optional** → wrap all its entries in one guard
    (`if (fieldArgs != null) { … }`); omitted ⇒ vars absent ⇒ document default /
    null applies. **No per-field `?.`.**
- Wire keys stay `field.bareName`.
**Verify:** `glVariables__` carries declared keys + expanded hoist keys (guarded
when optional); wire keys unchanged.

### 1.6 — Default-value handling (RESOLVED — existing initializers)
All four input serializers already emit field initializers from `GLField.initialValue`
(Dart `dart_serializer.dart:353`, Java `:291`, Kotlin `:231`, TS `:178`), and their
field-required logic (`!type.nullable && initialValue == null`) matches
`objectRequired`. With the synthesized field carrying `initialValue = a.defaultValue?.value`:
- object present, field unset → initialized to default → non-null → sent;
- object omitted → guard drops the var → document default (`$x: T = N`) applies.
Both yield the default; nothing extra to build.
**Verify:** op with hoisted `Int! = N` ⇒ `<Op>FieldArgs` initializes it to `N`;
omitting it still yields `N` on the wire, never `null`.

### 1.7 — Tests
**Dir:** `test/queries_auto_gen/` (parser) + relevant per-language client dirs.
1. `isDeclared` false on propagated, true on declared (1.1).
2. swap: propagated args removed, one `hoistArgsInput` arg added, `<Op>FieldArgs`
   input synthesized with correct fields/nullability (1.2).
3. signature: declared direct + object param, required vs optional per rule (1.3).
4. query string: flat `$field` vars, no `$fieldArgs`; divided queries keep their
   hoisted vars (1.4).
5. variables map: declared + expanded hoist keys, guarded when optional, wire keys
   intact (1.5).
6. param/type-name collision ⇒ indexed.
7. default-value: `Int! = N` initialized + correct on the wire (1.6).
- Run scoped: `fvm dart test test/queries_auto_gen/ > /tmp/t.log 2>&1; grep -E "FAILED|Error|✗" /tmp/t.log`

## Audit before merging
- Other `def.arguments` consumers besides signature/varmap/query-string: cache-key
  building and multipart/upload (`_serializeMultipartAdapterCall`). Uploads are
  declared mutation args (stay `isDeclared: true`), so likely unaffected — confirm.

## Out of scope for step 1
- Skip cap / `autoGenerateQueriesArgumentLimit` / CLI warnings (next step).
- Java optional-object overloads (single nullable param is enough to start).
- Hierarchical (selection-tree) object shape — flat only.
