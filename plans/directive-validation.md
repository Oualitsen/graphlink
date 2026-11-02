# Plan: Directive validation

Status: **inventory done, nothing implemented.** This is a breaking change, announced in `CHANGELOG.md` under `Unreleased`.

## Decisions

1. Every directive application is validated: GraphLink's internal directives and the ones a schema declares.
2. A directive that is not internal and has no declaration is an error.
3. GraphLink catches naming and type errors itself; the IDE (IntelliJ) is no longer the only line of defence.
4. Valid GraphQL directive *declarations* in a user's schema (including hand-written copies of internal ones) keep working.

## Method

A throwaway script parsed every schema source in the repo with `GLParser.parse(text, validate: false)` and read `directiveValues` and
`directiveDefinitions`: 405 sources (`.graphql`/`.gql` files under `test/`, `examples/`, `integration_tests/`,
`server_integration_tests/`, plus inline `'''` schemas in `test/**/*.dart`). 7 sources did not parse alone (multi-file fragments) and were
skipped. 61 distinct directives were found. "Observed locations" below are the locations **the parser attaches**, which is what a validator
would compare against.

## The three sources disagree

GraphLink's directive shape is currently written down in three places, and no two agree.

| Directive | Observed (parser) | `directives.md` "Copy-paste declarations" | Registry (`GLParser.directives`) |
|---|---|---|---|
| `@glMapField` | `INPUT_FIELD_DEFINITION` | `FIELD_DEFINITION` (an IDE would flag correct usage) | not registered |
| `@glTypeName` | `FIELD`, `INLINE_FRAGMENT`, `INPUT_OBJECT`, `MUTATION`, `QUERY` | `OBJECT`, `INPUT_OBJECT`, `ENUM` | `INPUT_OBJECT`, `FRAGMENT_DEFINITION`, `QUERY`, `MUTATION`, `SUBSCRIPTION` |
| `@glIntercept` | `FIELD_DEFINITION`, `INPUT_FIELD_DEFINITION`, `OBJECT` | no `INPUT_FIELD_DEFINITION` | no `INPUT_FIELD_DEFINITION` |
| `@glRepository` | `INTERFACE` | `OBJECT` | not registered |
| `@glCache` `ttl` | `Int` or a duration string (`"30s"`) | `String!` | not registered |
| `@glNoCache`, `@glDownload`, `@glVoid`, `@glRest*` | in use | missing | not registered |
| `@deprecated` | 11 locations, including types, unions and schema | not listed | `FIELD_DEFINITION`, `ENUM_VALUE` only |

Only 9 directives are registered at all: `@include`, `@skip`, `@deprecated`, `@specifiedBy`, `@glTypeName`, `@glEqualsHashcode`,
`@glExpand`, `@glCaptureErrors`, `@glIntercept`. Everything else is accepted by the parser without any check.

## Inventory: internal directives

Observed arguments are all the argument names seen in the corpus. "n" is the number of applications. REST counts are low because most REST
tests use single-quoted one-line schemas, which the script did not read.

| Directive | n | Observed locations | Observed arguments |
|---|---|---|---|
| `@glCache` | 56 | `FIELD`, `FIELD_DEFINITION`, `QUERY` | `ttl`, `tags`, `staleIfOffline` |
| `@glCacheInvalidate` | 33 | `FIELD`, `FIELD_DEFINITION`, `MUTATION` | `all`, `tags` |
| `@glNoCache` | 9 | `FIELD`, `FIELD_DEFINITION` | – |
| `@glCaptureErrors` | 21 | `FIELD_DEFINITION` | – |
| `@glDecorators` | 12 | `ENUM`, `FIELD_DEFINITION`, `INPUT_OBJECT`, `INTERFACE`, `OBJECT` | `value` (repeatable) |
| `@glEqualsHashcode` | 3 | `FIELD`, `OBJECT` | `fields` |
| `@glExpand` | 9 | `OBJECT` | `depth` |
| `@glExternal` | 7 | `INPUT_OBJECT`, `OBJECT`, `SCALAR` | `glClass`, `glImport` |
| `@glInjectContext` | 1 | `FIELD_DEFINITION` | – |
| `@glIntercept` | 35 | `FIELD_DEFINITION`, `INPUT_FIELD_DEFINITION`, `OBJECT` | `tag` |
| `@glMapField` | 27 | `INPUT_FIELD_DEFINITION` | `to` |
| `@glMapsTo` | 120 | `INPUT_OBJECT` | `type` |
| `@glRepository` | 10 | `INTERFACE` | `glType`, `glIdType` |
| `@glServerLenient` | 2 | `OBJECT` | – |
| `@glServiceName` | 40 | `ENUM`, `FIELD_DEFINITION`, `INPUT_OBJECT`, `INTERFACE`, `OBJECT` | `name` |
| `@glSkipOnClient` | 30 | `ENUM_VALUE`, `FIELD_DEFINITION`, `OBJECT` | – |
| `@glSkipOnServer` | 103 | `ENUM`, `FIELD_DEFINITION`, `INPUT_OBJECT`, `OBJECT`, `SCALAR` | `batch`, `mapTo` |
| `@glTypeName` | 37 | `FIELD`, `INLINE_FRAGMENT`, `INPUT_OBJECT`, `MUTATION`, `QUERY` | `name` |
| `@glUpload` | 10 | `SCALAR` | – |
| `@glValidate` | 4 | `FIELD_DEFINITION` | – |
| `@glInternal` | 0 | not observed (documented: `OBJECT`) | – |
| `@glRest` | 45 | `FIELD_DEFINITION` | `path`, `method` (also `contentType`, `accept`, `response`, `responsePath`) |
| `@glRestPrefix` | 8 | `OBJECT` | `path`, `method` |
| `@glRestParam` | 2 | `ARGUMENT_DEFINITION`, `INPUT_FIELD_DEFINITION` | `name` (also `encoding`) |
| `@glRestHeader` | 3 | `ARGUMENT_DEFINITION`, `INPUT_FIELD_DEFINITION` | `name` |
| `@glRestPath`, `@glRestBody`, `@glRestField`, `@glRestPart` | – | defined in `rest-client-specs.md` | `name` / none / `name`, `encoding` / `name`, `encoding` |
| `@glRestDiscriminator` | 4 | `INTERFACE`, `UNION` | `field`, `values` |
| `@glDownload`, `@glVoid` | 1, 1 | `SCALAR` | – |

Loose ends found by the scan:

- `@glEqualsHashcode(fields:)` is `[String]` in the registry and `[String!]!` in the docs.
- `@glEqualsHashcode` is observed on `FIELD` (an operation-document location). Needs a decision: legitimate or a parser artefact.
- `@glRepository` is applied to **interfaces** in every fixture; the docs say `OBJECT`.

## Not internal, despite the name

| Directive | Reality |
|---|---|
| `@glArray` | Removed in v4.4.0 (`directives.md`). Declared by one fixture as a user directive. |
| `@glQuery` | A fixture's own declaration. `glQuery__` in `lib/` is an unrelated generated variable name. |
| `@glReturnsProjection` | Only in `plans/glstrict-consolidated.md` and fixtures that declare it themselves. No code reads it. |

## Inventory: standard and user directives

- **Standard, registered:** `@include`, `@skip`, `@deprecated`, `@specifiedBy`.
- **Declared by schemas, never applied:** `@defer` and `@stream` appear only as `directive @defer` / `@stream` declarations (the Shopify Storefront
  schemas). A text grep counted them 8 and 2 times; the parser sees no application. `@oneOf` is not in the corpus at all.
- **User directives declared in the same corpus (accepted today and after):** about 35, mostly the Java annotation mechanism
  (`@Getter`, `@Id`, `@JsonProperty`, `@CreatedBy`, `@gqQuery`, ...) and the GitHub/GitLab schemas' own (`@docsCategory`, `@possibleTypes`,
  `@webhookEventsInfo`, `@inContext`, ...).
- **Used and never declared (these fixtures would start failing):** `@auth`, `@gqHide`, `@gqId`, `@gqJpaQuery`, `@link`.
- **Internal directives that fixtures use without declaring them** (so they must stay built in, not become "declare it yourself"):
  `@glDownload`, `@glExpand`, `@glInjectContext`, `@glIntercept`, `@glNoCache`, `@glServiceName`, `@glTypeName`, `@glVoid`, `@glRest*`.

## Design

1. **One canonical declaration set** for the internal directives, as SDL inside the package: argument names, types, required flags, repeatable
   flag and locations. It is the only place that is edited.
2. It is parsed into a **separate store** and never into `enums`, `scalars` or `directiveDefinitions`: its internal enums (`RestMethod`, ...) and
   scalars (the `Int | duration` type of `ttl`) must not reach any generator.
3. Validation runs once, after parsing, over `directiveValues`: declared? known argument names? required arguments present? value kinds? location
   allowed? Cost per application is a map lookup (GitHub has 7,256 `@deprecated`).
4. A user declaration of an internal directive is accepted when it matches the canonical one (no more "already declared"), rejected with a
   diff-style message when it does not.
5. `directives.md` "Copy-paste declarations" is replaced by output generated from the same set, and a `glink` command writes it for the IDE.
6. Server mode validates too.

## Phases (each starts with failing tests)

| Phase | Rule | Risk |
|---|---|---|
| A | Undeclared non-internal directive is an error | the five fixtures above, plus users with federation directives |
| B | Unknown argument names and missing required arguments | catches `@glRest(methdo: PUT)` |
| C | Value kinds (`Int`, `String`, `Boolean`, lists, enums, objects) | `ttl` accepts two kinds |
| D | Locations | highest: the parser's own location tags are approximate |

Before phase D, audit every `_parseDirectiveValueList(scope)` call site against the 19 GraphQL locations.

## Decisions taken

| Question | Decision |
|---|---|
| `@oneOf` | Built in (GraphQL spec). The input type needs every field nullable; GraphLink also checks at runtime that exactly one is set. See "oneOf" below. |
| `@defer`, `@stream` | **Not built in.** They are not in the released GraphQL spec, nothing applies them, and the schemas that mention them declare them. They are accepted like any declared user directive. Incremental delivery would be a separate feature. |
| `@deprecated` | Follow the spec: `FIELD_DEFINITION`, `ARGUMENT_DEFINITION`, `INPUT_FIELD_DEFINITION`, `ENUM_VALUE` only. Fixtures that put it elsewhere get fixed. |
| `@glMapField` | `INPUT_FIELD_DEFINITION` only; the docs are wrong. |
| Baseline | The full test suite is green today. |

Still to confirm: `@glEqualsHashcode` and `@glTypeName` on `FIELD`/`INLINE_FRAGMENT` (both used in operation documents to name and give equality to projected types,
and neither documented), `@glRepository` on `INTERFACE`, and federation directives in server schemas.

## oneOf

- Validation: fields of an `@oneOf` input must be nullable and have no default (spec rule), and the directive is only valid on `INPUT_OBJECT`.
- Generation: every field of the generated type is nullable (as declared). The constructor/`toJson` raises when zero or more than one field is set.
- A server answering with an `@oneOf` input needs no check.

## Canonical declarations (proposal, to be applied in the next PR)

`!` means required. The location set is the observed set, widened with documented uses. Rows marked **?** need the confirmation above.
Internal helper types (never generated): `Duration` (an `Int` of seconds or a string like `"30s"`), `GLMap` (an object value), and the enums
`RestMethod { GET POST PUT PATCH DELETE }`, `RestEncoding { FLAT JSON SPREAD }`, `RestResponseKind { JSON TEXT BINARY }`.

| Directive | Arguments | Locations |
|---|---|---|
| `@include`, `@skip` | `if: Boolean!` | `FIELD`, `FRAGMENT_SPREAD`, `INLINE_FRAGMENT` |
| `@deprecated` | `reason: String = "No longer supported"` | `FIELD_DEFINITION`, `ARGUMENT_DEFINITION`, `INPUT_FIELD_DEFINITION`, `ENUM_VALUE` |
| `@specifiedBy` | `url: String!` | `SCALAR` |
| `@oneOf` | – | `INPUT_OBJECT` |
| `@glCache` | `ttl: Duration!`, `tags: [String!]`, `staleIfOffline: Boolean` | `QUERY`, `FIELD`, `FIELD_DEFINITION` |
| `@glCacheInvalidate` | `tags: [String!]`, `all: Boolean` | `MUTATION`, `FIELD`, `FIELD_DEFINITION` |
| `@glNoCache` | – | `QUERY`, `FIELD`, `FIELD_DEFINITION` |
| `@glCaptureErrors` | – | `FIELD_DEFINITION` |
| `@glDecorators` (repeatable) | `value: [String!]!` | `OBJECT`, `INPUT_OBJECT`, `INTERFACE`, `ENUM`, `FIELD_DEFINITION` |
| `@glEqualsHashcode` **?** | `fields: [String!]!` | `OBJECT`, `INPUT_OBJECT`, `FIELD` |
| `@glExpand` | `depth: Int` | `OBJECT` |
| `@glExternal` | `glClass: String!`, `glImport: String` | `SCALAR`, `OBJECT`, `INPUT_OBJECT` |
| `@glInjectContext` | – | `FIELD_DEFINITION` |
| `@glInternal` | – | `OBJECT` |
| `@glIntercept` | `tag: String` | `QUERY`, `MUTATION`, `SUBSCRIPTION`, `FIELD_DEFINITION`, `INPUT_FIELD_DEFINITION`, `OBJECT` |
| `@glMapField` | `to: String!` | `INPUT_FIELD_DEFINITION` |
| `@glMapsTo` | `type: String!` | `INPUT_OBJECT` |
| `@glRepository` **?** | `glType: String!`, `glIdType: String!` | `INTERFACE` |
| `@glServerLenient` | – | `OBJECT`, `INTERFACE` |
| `@glServiceName` | `name: String!` | `OBJECT`, `INTERFACE`, `INPUT_OBJECT`, `ENUM`, `FIELD_DEFINITION` |
| `@glSkipOnClient` | – | `OBJECT`, `INPUT_OBJECT`, `SCALAR`, `FIELD_DEFINITION`, `ENUM_VALUE` |
| `@glSkipOnServer` | `mapTo: String`, `batch: Boolean` | `OBJECT`, `INPUT_OBJECT`, `ENUM`, `SCALAR`, `FIELD_DEFINITION` |
| `@glTypeName` **?** | `name: String!` | `OBJECT`, `INPUT_OBJECT`, `ENUM`, `QUERY`, `MUTATION`, `SUBSCRIPTION`, `FIELD`, `INLINE_FRAGMENT`, `FRAGMENT_DEFINITION` |
| `@glUpload`, `@glDownload`, `@glVoid` | – | `SCALAR` |
| `@glValidate` | – | `FIELD_DEFINITION` |
| `@glRest` | `path: String`, `method: RestMethod`, `contentType: String`, `accept: String`, `response: RestResponseKind`, `responsePath: String` | `FIELD_DEFINITION` |
| `@glRestPrefix` | `path: String!`, `method: RestMethod` | `OBJECT` |
| `@glRestPath` | `name: String` | `ARGUMENT_DEFINITION` |
| `@glRestParam` | `name: String`, `encoding: RestEncoding` | `ARGUMENT_DEFINITION`, `INPUT_FIELD_DEFINITION` |
| `@glRestHeader` | `name: String` | `ARGUMENT_DEFINITION`, `INPUT_FIELD_DEFINITION`, `INPUT_OBJECT` |
| `@glRestBody` | – | `ARGUMENT_DEFINITION` |
| `@glRestField`, `@glRestPart` | `name: String`, `encoding: RestEncoding` | `ARGUMENT_DEFINITION`, `INPUT_FIELD_DEFINITION` |
| `@glRestDiscriminator` | `field: String!`, `values: GLMap` | `INTERFACE`, `UNION` |

Gap in the REST IR found while writing this table: `@glRestHeader` on an `input` definition (`rest-client-specs.md` section 4.4, "every argument of that
type becomes a header group") is specified but not implemented; today it only works on an argument.

## Open questions

1. Confirm the three **?** rows.
2. Federation directives (`@key`, `@link`, ...) in server schemas: an error per the decision, or a documented way to declare them.
