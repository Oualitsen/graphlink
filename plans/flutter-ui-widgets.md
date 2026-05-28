# Flutter UI Widget Generation

## Status: Phase 1 — complete

---

## Context

GraphLink already generates fully-typed Dart data classes for GraphQL types and inputs. This plan adds opt-in Flutter widget generation on top of those classes:

- **Stateless display widgets** for `type` definitions (e.g. `VehicleWidget`) — ✅ done
- **Stateful form widgets** for `input` definitions (e.g. `AddVehicleInputForm`) — phase 2, not in scope

---

## Configuration

Flutter widget generation is enabled by adding a `flutter:` block inside `clientConfig.dart`:

```json
{
  "clientConfig": {
    "dart": {
      "flutter": {
        "generateTypes": true,
        "generateInputs": false,
        "typesToSkip": ["SomeInternalType"],
        "defaultGap": 16
      }
    }
  }
}
```

`FlutterConfig` is a dedicated class in `config.dart` (replacing the old flat `generateUiTypes` / `generateUiInputs` booleans that have been removed). Presence of the `flutter:` key enables generation; absence disables it entirely.

| Field | Type | Default | Description |
|---|---|---|---|
| `generateTypes` | `bool` | `true` | Generate stateless widgets for schema `type`s |
| `generateInputs` | `bool` | `false` | Reserved for phase 2 form widgets |
| `typesToSkip` | `string[]` | `[]` | Type names excluded from widget generation |
| `defaultGap` | `number` | `16` | Default spacing between field rows |

---

## Generated API — Stateless Type Widgets

For each concrete, non-response GraphQL `type`, one file is generated containing five items.

### Companion classes

**`VehicleLabels`** — override the label (left side) of any field. `null` = use the auto-humanized default (`Text('Brand')`). Also holds `$group` — the scalar group title in `expandable` layout (default `Text('Details')`). The `$` prefix is a valid Dart identifier character and is impossible in GraphQL field names, eliminating any collision risk.

Each field also has a companion `String? ${field}Info` (e.g. `brandInfo`). When non-null, a small `Icons.info_outline` button is rendered next to the label; tapping/clicking it opens an `AlertDialog` containing that string. `null` = no info button. `$groupInfo` works the same way for the expandable scalar accordion title.

**Note:** the info button is only rendered in the four main layout helpers (`labeledRow`, `listTile`, `listTileReversed`, `expandable`). `toTableRow()` and `toTableHeaderRow()` have no `BuildContext` and omit it.

```dart
class VehicleLabels {
  final Widget? id;
  final String? idInfo;
  final Widget? brand;
  final String? brandInfo;
  // ... one Widget? + one String? per schema field
  final Widget? $group;   // scalar accordion title in expandable layout
  final String? $groupInfo;
  const VehicleLabels({this.id, this.idInfo, this.brand, this.brandInfo, ..., this.$group, this.$groupInfo});
}
```

**`VehicleValues`** — override the value widget (right side) of any field. `null` = default rendering.
```dart
class VehicleValues {
  final Widget? id;
  final Widget? brand;
  // ... one field per schema field
  const VehicleValues({this.id, this.brand, ...});
}
```

**`VehicleOrder`** — override the sort position of any field. `null` = use the schema-defined order (fields fall back to position × 1000 + index). Lower values appear first. Also holds `$group` — the sort position of the scalar accordion group in `expandable` layout (default `0`, before all field-based accordions).
```dart
class VehicleOrder {
  final int? id;
  final int? brand;
  // ...
  final int? $group;  // position of the scalar accordion group in expandable layout
  const VehicleOrder({this.id, this.brand, ..., this.$group});
}
```

**`VehicleVisibility`** — show/hide individual fields. `ID`-typed fields default to `false`; all others default to `true`. This is the sole mechanism for hiding fields; a `null` label in `VehicleLabels` does NOT hide a field.
```dart
class VehicleVisibility {
  final bool id;
  final bool brand;
  // ...
  const VehicleVisibility({this.id = false, this.brand = true, ...});
}
```

**`VehicleShowOnly`** — inverse of `VehicleVisibility`: all fields default to `false`; set specific fields to `true` to show only those. Converts to a `VehicleVisibility` via `toVisibility()`. Pass it to the widget via `showOnly:`; using both `visibility` and `showOnly` on the same widget triggers an `assert`.
```dart
class VehicleShowOnly {
  final bool id;
  final bool brand;
  // ... all default to false
  const VehicleShowOnly({this.id = false, this.brand = false, ...});
  VehicleVisibility toVisibility() => VehicleVisibility(id: id, brand: brand, ...);
}
```

Usage:
```dart
VehicleWidget(vehicle, showOnly: VehicleShowOnly(brand: true, mileage: true))
// → only brand and mileage are visible; all other fields hidden

// Using both raises an assert in debug mode:
VehicleWidget(vehicle, visibility: VehicleVisibility(), showOnly: VehicleShowOnly()) // ❌ assert fires
```

**`VehicleEnumLabels`** — per-value label overrides for every enum field in the type, including list-of-enum fields. Each field holds a `FuelTypeLabels?`. `null` field = use default for that enum field; `null` widget inside = use `Text(value.name)` (or `Chip(label: Text(value.name))` for list fields) for that specific value.
```dart
class VehicleEnumLabels {
  final FuelTypeLabels? fuelType;   // scalar enum field
  final FuelTypeLabels? fuelTypes;  // list-of-enum field
  // one field per enum-typed field (scalar or list) in the type
  const VehicleEnumLabels({this.fuelType, this.fuelTypes});
}
```

**`VehicleLayout`** — selects the rendering layout.
```dart
enum VehicleLayout { labeledRow, listTile, listTileReversed, expandable }
```

### Widget

```dart
class VehicleWidget extends StatelessWidget {
  final Vehicle vehicle;
  final VehicleLabels? labels;
  final VehicleValues? values;
  final VehicleVisibility? visibility;
  final VehicleShowOnly? showOnly;
  final VehicleOrder? order;
  final VehicleEnumLabels? enumLabels;
  final VehicleLayout layout;
  final double gap;
  final VehicleLayout groupLayout;  // style of the scalar accordion in expandable layout
  final FormStrings strings;

  const VehicleWidget(
    this.vehicle, {
    super.key,
    this.labels,
    this.values,
    this.visibility,
    this.showOnly,
    this.order,
    this.enumLabels,
    this.layout = VehicleLayout.labeledRow,
    this.groupLayout = VehicleLayout.labeledRow,
    this.gap = 16,
    this.strings = const FormStrings(),
  }) : assert(visibility == null || showOnly == null,
           'VehicleWidget: use visibility or showOnly, not both');

  @override
  Widget build(BuildContext context) { ... }

  // Returns a data row for use inside a Table widget (values only, respects visibility/order).
  TableRow toTableRow() { ... }

  // Returns a header row for use inside a Table widget (labels only, respects visibility/order).
  TableRow toTableHeaderRow() { ... }

  // Returns a DataRow for use inside a DataTable widget (values wrapped in DataCell).
  DataRow toDataRow() { ... }

  // Returns List<DataColumn> for the columns: parameter of a DataTable widget (labels wrapped in DataColumn).
  List<DataColumn> toDataColumns() { ... }
}
```

These are instance methods — the same labels/values/visibility/order config is reused for both the widget and table-row rendering. No `BuildContext` is needed since widget construction is pure.

### Expandable layout

`VehicleLayout.expandable` groups fields into collapsible `ExpansionTile` sections:

| Group | Content | Title |
|---|---|---|
| Scalar group | All scalar, enum, and scalar-list fields — rendered as a labeled two-column table inside one `ExpansionTile` | `labels?.details ?? Text('Details')` |
| Nested type field | One `ExpansionTile` per field — contains the auto-embedded child widget (e.g. `OwnerWidget`) | `labels?.owner ?? Text('Owner')` |
| List-of-nested-type field | One `ExpansionTile` per field — contains a `Column` of child widgets, one per element | `labels?.vehicles ?? Text('Vehicles')` |

Rules:
- A nullable nested type field whose value is `null` → its accordion is omitted entirely.
- A list field that is `null` or empty → its accordion is omitted entirely.
- `VehicleVisibility` still controls inclusion; hidden fields are excluded from all groups.
- `VehicleValues` still overrides individual cells inside the scalar group, or the entire child widget for nested type fields.
- The scalar group's internal style is controlled by `groupLayout` (default `labeledRow`). Accepts `labeledRow`, `listTile`, or `listTileReversed` — `expandable` falls back to `labeledRow`.
- All accordion entries (scalar group + each nested/list field) are collected into one list and sorted together by their `VehicleOrder` value — `ord.$group` for the scalar group, `ord.fieldName` for the rest. This gives full control over group order.
- Default order: scalar group at `0`, field-based accordions at `1000 + schemaIndex` — scalars appear first by default.

Imports for both single and list nested-type fields are deduplicated via `Set<String>` at generation time.

### Default value rendering

| GraphQL type | Default value widget |
|---|---|
| `String`, `ID` | `Text(value)` |
| `Int`, `Float` | `Text(value.toString())` |
| `Boolean` | `Icon(value ? Icons.check : Icons.close)` |
| enum | `enumLabels?.fuelType?[value] ?? Text(value.name)` |
| nullable of any above | null-safe equivalent (`?? ''`, `?.toString() ?? ''`, `?.name ?? ''`) |
| scalar list (`[String!]`, `[Int!]`, …) | `Wrap` of `Chip` widgets, one per element (`e.toString()`) — override via `VehicleValues` |
| enum list (`[FuelType!]`) | `Wrap` of `Chip` widgets — `Chip(label: enumLabels?.fuelTypes?.call(e) ?? Text(e.name))` per element — `enumLabels` controls the chip **label** only; use `VehicleValues` for full chip replacement |
| nested type list (`[Car!]`) | `Text('N items')` in non-expandable layouts; use `expandable` layout for proper rendering |
| nested type | auto-embeds the child widget (e.g. `OwnerWidget(value)`) — override via `VehicleValues` |

**List field evaluation order** — `type.isList` is checked first, before all scalar type checks. Within the list branch, nested-type lists are detected first, then enum lists, then scalar lists.

**Enum rendering priority** (enum fields only):
1. `values.fuelType` — full widget override (replaces the entire value cell)
2. `enumLabels?.fuelType?.gasoline` — per-value label for the current enum value
3. `Text(value.name)` — default

Auto-humanization of field names: `camelCase` → `Title Case` (e.g. `fuelType` → `Fuel Type`).

---

## Skipped types

The generator silently skips:
1. `GLInterfaceDefinition` — abstract types cannot be instantiated
2. Types where `isResponseType == true` — query/mutation response containers (e.g. `GetVehicleResponse`, `ListVehiclesResponse`) generated by `GLQueryDefinition.getGeneratedTypeDefinition()`
3. Type names listed in `FlutterConfig.typesToSkip`

`isResponseType` is a `final bool` field on `GLTypeDefinition` (default `false`), set to `true` exclusively in `GLQueryDefinition.getGeneratedTypeDefinition()`.

---

## File layout

```
lib/generated/
  types/
    vehicle.dart              ← data class (unchanged)
  widgets/
    enums/
      fuel_type_labels.dart   ← FuelTypeLabels (one per enum, generated once)
    types/
      vehicle_widget.dart     ← VehicleWidget + VehicleLabels + VehicleValues
                                  + VehicleVisibility + VehicleEnumLabels + VehicleLayout
```

Per-enum labels classes live in `widgets/enums/` and are generated once regardless of how many types reference the enum. The type widget file now contains six items.

---

## Key files changed / created

| File | Change |
|---|---|
| `lib/src/config.dart` | Added `FlutterConfig` class; replaced `generateUiTypes`/`generateUiInputs` in `DartClientConfig` with `FlutterConfig? flutter` |
| `lib/graphlink_generator_builder.dart` | Reads `flutter:` as a nested map; builds `FlutterConfig` |
| `lib/src/main.dart` | Updated help text for new `flutter.*` keys |
| `lib/src/model/gl_type_definition.dart` | Added `final bool isResponseType` (default `false`) |
| `lib/src/model/gl_queries.dart` | Sets `isResponseType: true` in `getGeneratedTypeDefinition()` |
| `lib/src/dart_code_gen_utils.dart` | Added `extendsClassName` to `createClass`; added `isConst`/`positionalArguments` to `createMethod`; added `switchExpression` + `DartSwitchExpressionCase` |
| `lib/src/serializers/flutter_types_serializer.dart` | Thin orchestrator — delegates to `flutter_types/` sub-serializers; emits per-enum `FuelTypeLabels` classes into `widgets/enums/`; wires `VehicleShowOnly` into the widget |
| `lib/src/serializers/flutter_types/flutter_types_companion_serializer.dart` | Generates Labels, Values, Visibility, **ShowOnly**, Order, EnumLabels companion classes |
| `lib/src/serializers/flutter_types/flutter_types_layout_serializer.dart` | All layout method bodies; resolves `showOnly?.toVisibility() ?? visibility` |
| `lib/src/serializers/flutter_types/flutter_types_value_renderer.dart` | `defaultValueExpression`, `labelTextWidget`, `humanize` |
| `lib/src/serializers/flutter_types/flutter_types_constants.dart` | Shared `flutterInternalTypes` / `flutterInternalEnums` sets |
| `lib/src/generators/dart_client_generator.dart` | Hooks `FlutterTypesSerializer` when `flutter.generateTypes` is enabled |
| `examples/flutter/ui_types/` | New Flutter 3.32.7 example project |

---

## Example project

`examples/flutter/ui_types/` — a Flutter web project using FVM 3.32.7.

Schema types:
- `Vehicle` — `String`, `Int`, `Float?`, `Boolean`, `FuelType` enum — covers every scalar branch of the default value renderer.
- `Owner` — has two nested `Vehicle` fields (`primaryVehicle`, `secondaryVehicle?`) — demonstrates nested type auto-embed.
- `Fleet` — has scalar fields, a nested `Owner` field, and a `[Vehicle!]` list field — demonstrates the `expandable` layout with all three accordion groups.

Tabs (16 total):

| # | Tab | What it demonstrates |
|---|---|---|
| 1 | Display | Layout switcher, gap slider, label/value/order overrides, `toTableRow` |
| 2 | Add Vehicle | Input form layouts and label positions |
| 3 | Hidden Fields | Hidden fields with `hiddenDefaults` |
| 4 | Update | Nullable-field update form |
| 5 | Search | List-of-enum chip field |
| 6 | Field Widgets | Per-field enum/bool widget override |
| 7 | Text Options | `TextFieldOptions`, smart defaults |
| 8 | Chip Validation | Chip validation + `RequiredIndicator` |
| 9 | Date Inputs | Int/String date fields, dialog/inline/Cupertino |
| 10 | Composition | Nested input composition + `SimpleFieldForm` |
| 11 | Type Widgets | `OwnerWidget` with nested `VehicleWidget`, `toTableRow` |
| 12 | Dynamic Forms | Visibility/validation callbacks with `FormContext` |
| 13 | onChange | `onContextChange`, debounced `onChange`, `tryRead` |
| 14 | Stepper | Stepper layout for nested inputs |
| 15 | Expandable | `FleetWidget` with `expandable` layout — scalar accordion, nested-type accordion, list accordion |
| 16 | Field Info | `VehicleLabels` + `AddVehicleInputLabels` `*Info` strings — toggle on/off to compare; tapping a `?` icon opens an `AlertDialog` |

```
make get        # fvm flutter pub get
make generate   # run graphlink generator
make web        # launch in Chrome on port 9090
make all        # get + generate
make clean-widgets  # rm -rf lib/generated/widgets (clears stale files)
```

---

## Accessibility (screen reader) support

| Layout | Status | Notes |
|---|---|---|
| `labeledRow` | ✅ reads correctly | Table read row-major: "Label", "Value", next row… |
| `listTile` | ✅ reads correctly | `ListTile(title: label, subtitle: value)` — label announced first |
| `listTileReversed` | ⚠️ value announced before label | `ListTile(title: value, subtitle: label)` — Flutter's `ListTile` always reads `title` first via internal `MergeSemantics`; no clean fix in generated code |
| `expandable` | ✅ reads correctly | `ExpansionTile` announces its title; scalar table reads row-major inside the tile |

**Boolean fields:** `Icon` widgets are generated with `semanticLabel: 'Yes'` / `semanticLabel: 'No'` so TalkBack/VoiceOver announce the value rather than "icon".

**Null fields:** Fields hidden by `VehicleVisibility` or null nullable fields both produce `SizedBox.shrink()`, which is excluded from the semantic tree. A screen reader user cannot distinguish "field hidden" from "field has no value".

**Recommendation:** For apps requiring full accessibility compliance, use `labeledRow` or `listTile`. Avoid `listTileReversed` until it is reimplemented without `ListTile`.

---

## Out of scope (phase 2)

- Stateful form widgets for `input` types (`AddVehicleInputForm`)
- Localization integration (`appLocalizationsImport` already in `DartClientConfig`)
- Cupertino layout variant
- `listTileReversed` accessibility fix (requires replacing `ListTile` with a custom layout that separates visual order from semantic order)
- `expandable` layout: per-field initial expanded/collapsed state (currently all tiles start collapsed)
