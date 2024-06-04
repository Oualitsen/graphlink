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