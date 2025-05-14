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