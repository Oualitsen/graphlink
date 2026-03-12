## 1.0.0+1 - 2023-08-14

- Initial Release.

## 1.1.0 - 2023-09-19

- All generated data classes have `explicitToJson: true`

## 1.1.1 - 2023-10-19

- Updates readme file

## 2.0.0 - 2024-06-03

 - Adds `_all_fields` to target all fields (without class name)
 - Detects cycles in depencies when generating `all fields fragements`
 - You can use the package as a dev depency instead of a dependecy
 - Generates more meaningful class names when a all fields projection is used in queries/mutations.

 ## 2.0.1 - 2024-06-04
  - Fixes `_all_fields` to target all fields (without class name)

 ## 2.0.2 - 2024-06-04
  - Fixes generated code when `_all_fields` is used.

 ## 2.0.3 - 2024-06-11
  - Optimizes code generation.
  - Generates code much faster.

 ## 2.1.0 - 2025-05-14
  - Generate constructor without `required` for nullable arguments
    ### Note:
    if you need to keep generating required nullable fields you need to pass `nullableFieldsRequired: true` on your build.yaml

## 2.1.1 - 2025-05-14
    - Updates project dependcy versions
## 2.1.2 - 2025-05-14
    - Adds project links on generated files
## 2.1.3 - 2025-05-14
    - Fixes transitive frament reference
## 2.2.0 - 2025-05-15
    - Generates declares queries mutations and subscriptions without declaration
      You need to pass `autoGenerateQueries: true` on your build.yaml to enable this option
      You can also pass `autoGenerateQueriesDefaultAlias` as an alias to be used for queries, mutations and subscriptions.

## 3.0.0 - 2025-05-21
    - Generates code for unions
    - Generates == and hashcode method using either:
        1. @gqEqualsHashcode(fields: ["field1", "field2"])
        2. on build.yaml 
        identityFields: ["field1", "field2"]
    Note: In case of Unions and Interfaces, the Retrofit Graphql generates empty interfaces instead of base classes.  
## 3.0.1 - 2025-05-21
    - Fixed some minor bugs

## 3.1.0 - 2025-05-21
    - Generates all implemented interfaces

## 4.0.0 - 2026-03-12
  ### Java / Spring Boot code generation
  - Generates Java types, inputs, enums with `toJson`/`fromJson` methods
  - Generates Java client serializer
  - Generates Spring for GraphQL controllers and service interfaces
  - Generates repository interfaces (`@gqRepository`)
  - Generates null checks on inputs and types
  - Generates Java records support
  - Generates annotations on controllers
  - Validates backend inputs (`@gqValidateInput`)
  - Injects data-fetching on mappings
  - Generates schema mappings (identity, refactored)

  ### Dart code generation
  - Generates `toJson`/`fromJson` without `json_serializable` dependency
  - Generates Flutter UI views (optional, `noUi: true` to disable)
  - Projected interfaces support
  - Fixes response generation for single-element queries

  ### New directives
  - `@gqDecorators` — attach decorators to generated classes
  - `@gqSkipOnServer` / `@gqSkipOnClient` — skip fields/types per target
  - `@gqArray` — serialize GraphQL lists as arrays (Java)
  - `@gqInternal` — skip internal objects from processing
  - `@gqExternal` — mark external types
  - `extend` keyword support
  - `repeatable` keyword support for directives
  - Directives can now apply to fields

  ### CLI & tooling
  - CLI configuration support
  - Watch-files mode
  - Wildcard filename support
  - Handle multiple input files
  - Jenkins CI file added

  ### Other improvements & fixes
  - Removes `isScalar` from `GqType`
  - Schema generation support
  - Annotation serialization on controllers
  - Interface directive inheritance
  - `all_fields` projection skips `@gqSkipOnClient` fields
  - Wildcard maps/lists instead of `List<Object>` / `Map<Object, Object>`
  - Java primitives auto-boxed when nullable
  - Multiple subscription fixes
  - Various import and serialization bug fixes
