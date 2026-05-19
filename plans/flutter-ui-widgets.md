# Flutter UI Widget Generation

## Status: Phase 1 — enum labels improvement in progress

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

**`VehicleLabels`** — override the label (left side) of any field. `null` = use the auto-humanized default (`Text('Brand')`).
```dart
class VehicleLabels {
  final Widget? id;
  final Widget? brand;
  // ... one field per schema field
  const VehicleLabels({this.id, this.brand, ...});
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

**`VehicleOrder`** — override the sort position of any field. `null` = use the schema-defined order (fields fall back to position × 1000 + index). Lower values appear first.
```dart
class VehicleOrder {
  final int? id;
  final int? brand;
  // ...
  const VehicleOrder({this.id, this.brand, ...});
}
```

**`VehicleVisibility`** — show/hide individual fields. All default to `true`. This is the sole mechanism for hiding fields; a `null` label in `VehicleLabels` does NOT hide a field.
```dart
class VehicleVisibility {
  final bool id;
  final bool brand;
  // ...
  const VehicleVisibility({this.id = true, this.brand = true, ...});
}
```

**`VehicleEnumLabels`** — per-value label overrides for every enum field in the type. Each field holds a `FuelTypeLabels?` (or the relevant per-enum class). `null` field = use default for that enum field; `null` widget inside = use `Text(value.name)` for that specific value.
```dart
class VehicleEnumLabels {
  final FuelTypeLabels? fuelType;
  // one field per enum-typed field in the type
  const VehicleEnumLabels({this.fuelType});
}
```

**`VehicleLayout`** — selects the rendering layout.
```dart
enum VehicleLayout { labeledRow, listTile, listTileReversed }
```

### Widget

```dart
class VehicleWidget extends StatelessWidget {
  final Vehicle vehicle;
  final VehicleLabels? labels;
  final VehicleValues? values;
  final VehicleVisibility? visibility;
  final VehicleOrder? order;
  final VehicleEnumLabels? enumLabels;
  final VehicleLayout layout;
  final double gap;

  const VehicleWidget(
    this.vehicle, {
    super.key,
    this.labels,
    this.values,
    this.visibility,
    this.order,
    this.enumLabels,
    this.layout = VehicleLayout.labeledRow,
    this.gap = 16,
  });

  @override
  Widget build(BuildContext context) { ... }

  // Returns a data row for use inside a Table widget (values only, respects visibility/order).
  TableRow toTableRow() { ... }

  // Returns a header row for use inside a Table widget (labels only, respects visibility/order).
  TableRow toTableHeaderRow() { ... }
}
```

`toTableRow()` is an instance method — the same labels/values/visibility config is reused for both the widget and table-row rendering. No `BuildContext` is needed since widget construction is pure.

### Default value rendering

| GraphQL type | Default value widget |
|---|---|
| `String`, `ID` | `Text(value)` |
| `Int`, `Float` | `Text(value.toString())` |
| `Boolean` | `Icon(value ? Icons.check : Icons.close)` |
| enum | `enumLabels?.fuelType?[value] ?? Text(value.name)` |
| nullable of any above | null-safe equivalent (`?? ''`, `?.toString() ?? ''`, `?.name ?? ''`) |
| list / nested type | `Text(value.toString())` — override via `VehicleValues` |

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
| `lib/src/serializers/flutter_types_serializer.dart` | New — `FlutterTypesSerializer`; also emits per-enum `FuelTypeLabels` classes into `widgets/enums/`; generates `VehicleOrder` for field reordering and `toTableHeaderRow()` for table header rows |
| `lib/src/generators/dart_client_generator.dart` | Hooks `FlutterTypesSerializer` when `flutter.generateTypes` is enabled |
| `examples/flutter/ui_types/` | New Flutter 3.32.7 example project |

---

## Example project

`examples/flutter/ui_types/` — a Flutter web project using FVM 3.32.7.

Schema: `Vehicle` type with `String`, `Int`, `Float?`, `Boolean`, `FuelType` enum, nullable `String?` — covers every branch of the default value renderer.

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

**Boolean fields:** `Icon` widgets are generated with `semanticLabel: 'Yes'` / `semanticLabel: 'No'` so TalkBack/VoiceOver announce the value rather than "icon".

**Null fields:** Fields hidden by `VehicleVisibility` or null nullable fields both produce `SizedBox.shrink()`, which is excluded from the semantic tree. A screen reader user cannot distinguish "field hidden" from "field has no value".

**Recommendation:** For apps requiring full accessibility compliance, use `labeledRow` or `listTile`. Avoid `listTileReversed` until it is reimplemented without `ListTile`.

---

## Out of scope (phase 2)

- Stateful form widgets for `input` types (`AddVehicleInputForm`)
- Localization integration (`appLocalizationsImport` already in `DartClientConfig`)
- Cupertino layout variant
- Nested type widget composition (auto-embed child widgets)
- `listTileReversed` accessibility fix (requires replacing `ListTile` with a custom layout that separates visual order from semantic order)
