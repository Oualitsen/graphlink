# Flutter UI Input Form Generation

## Status: Implemented (phase 9 — dynamic visibility, FormContext, typed Values override, generator refactor)

---

## What changed from the original design

Sections that diverge from the original plan are marked **⚡ changed** or **⚡ added**.

---

## Configuration

Enabled by setting `generateInputs: true` inside the existing `flutter:` block:

```json
{
  "clientConfig": {
    "dart": {
      "flutter": {
        "generateTypes": true,
        "generateInputs": true,
        "booleanWidget": "switch",
        "nullableBooleanWidget": "checkbox",
        "listWidget": "chips",
        "typesToSkip": [],
        "inputsToSkip": [],
        "defaultGap": 16
      }
    }
  }
}
```

**`FlutterConfig` fields (all implemented):**
- `generateInputs: bool` — default `false`
- `booleanWidget: BooleanWidget` — global widget for `Boolean!`, default `switchWidget`
- `nullableBooleanWidget: NullableBooleanWidget` — global widget for `Boolean?`, default `checkbox`
- `listWidget: ListWidget` — global widget for list fields, default `chips` ⚡ added
- `inputsToSkip: List<String>` — mirrors `typesToSkip` but for `input` definitions

```dart
enum BooleanWidget { tristate, checkbox, switchWidget }
enum NullableBooleanWidget { tristate, checkbox }  // switchWidget excluded — Switch cannot represent null
enum ListWidget { chips, checkboxes }
```

(`switch` is a Dart keyword; the config string is `"switch"`, the Dart enum value is `switchWidget`.)

**Global widget matrix:**

| Config | `Boolean!` | `Boolean?` |
|---|---|---|
| `booleanWidget: switch` | `Switch` / `SwitchListTile`, `bool _f = false` | — |
| `booleanWidget: checkbox` | `Checkbox(tristate: false)` / `CheckboxListTile`, `bool _f = false` | — |
| `booleanWidget: tristate` | Yes/No/— Dropdown, `bool? _f = null`, required validator rejects null | — |
| `nullableBooleanWidget: checkbox` | — | `Checkbox(tristate: true)` / `CheckboxListTile`, `bool? _f = null` |
| `nullableBooleanWidget: tristate` | — | Yes/No/— Dropdown, `bool? _f = null`, null is valid |

Per-field overrides (via `${InputName}Widgets`) take precedence over the global config. See [Per-field widget override](#per-field-widget-override) below.

---

## Generated API

For each `input` definition (e.g. `AddVehicleInput`), one file is generated containing:
- 11 companion classes: `FormContext`, `DropdownLabels`, `Labels`, `Values`, `Visibility`, `Defaults`, `Validations`, `Order`, `Widgets`, `TextConfig`, `DateConfig` ⚡ added `FormContext` (phase 9)
- 2 layout enums: `Layout`, `LabelPosition`
- 1 `StatefulWidget` extending `InputFormWidget<T>`
- 1 `State` extending `InputFormState<T>`

---

### Companion classes

**`AddVehicleInputDropdownLabels`** — option label overrides for enum fields, bool fields, and list-of-enum fields. ⚡ changed: `BooleanLabels?` is now generated for **all** bool fields (not just tristate), so chips/radio can use `trueLabel`/`falseLabel`.

```dart
class AddVehicleInputDropdownLabels {
  final FuelTypeLabels? fuelType;    // enum field
  final BooleanLabels? available;    // all bool fields (was: tristate only)
  final FuelTypeLabels? fuelTypes;   // list-of-enum field
  const AddVehicleInputDropdownLabels({this.fuelType, this.available, this.fuelTypes});
}
```

`BooleanLabels` — shared, generated once into `widgets/inputs/boolean_labels.dart`:

```dart
class BooleanLabels {
  final Widget unselected;   // used by tristate dropdown
  final Widget trueLabel;    // used by chips/radio/tristate
  final Widget falseLabel;   // used by chips/radio/tristate
  const BooleanLabels({
    this.unselected = const Text('Choose an option'),
    this.trueLabel  = const Text('Yes'),
    this.falseLabel = const Text('No'),
  });
}
```

**`AddVehicleInputFormContext`** — typed snapshot of all current field values, passed to visibility and validation callbacks. Generated per input, excluding nested input fields. ⚡ added (phase 9)

```dart
class AddVehicleInputFormContext {
  final String brand;        // text fields → String (controller.text, never null)
  final FuelType? fuelType;  // enum fields → EnumType?
  final bool available;      // bool! → bool,  bool? → bool?
  final String mileage;      // nullable text → String (empty if unfilled)
  const AddVehicleInputFormContext({required this.brand, this.fuelType, ...});
}
```

Built by `_buildContext()` in the state class — called once at the start of `_visibleRows()` and once at the start of `read()`. Validators each call `_buildContext()` independently at validation time.

**`AddVehicleInputLabels`** — `Widget?` per field, `null` = auto-humanized default.

**`AddVehicleInputValues`** — typed field override. Each field is `InputFormWidget<T> Function(Key)?` where `T` matches the field's schema type. Input fields are excluded (they already use the nested key pattern). ⚡ changed (phase 9)

```dart
class AddVehicleInputValues {
  final InputFormWidget<String>  Function(Key)? brand;
  final InputFormWidget<FuelType> Function(Key)? fuelType;
  final InputFormWidget<bool>    Function(Key)? available;
  final InputFormWidget<double?> Function(Key)? mileage;
  ...
}
```

The parent form generates one `GlobalKey<InputFormState<T>>` per field. `_visibleRows()` calls `.call(key)` to build the override widget; `read()` calls `currentState!.read()` to get its value. `read()` precedence: **hidden → hiddenDefaults · override present → overrideKey.read() · else → controller/state**. If a field is hidden its override widget is not mounted — `read()` uses defaults regardless.

Use `SimpleFieldForm<T>` (generated once into `widgets/inputs/simple_field_form.dart`) for simple inline overrides without writing a full `StatefulWidget`.

**`AddVehicleInputVisibility`** — callback per field: `FieldVisibility Function(FormContext)?`. `null` = `enabled`. ⚡ changed (phase 9)

```dart
enum FieldVisibility { enabled, disabled, hidden }

class AddVehicleInputVisibility {
  final FieldVisibility Function(AddVehicleInputFormContext)? brand;
  final FieldVisibility Function(AddVehicleInputFormContext)? fuelType;
  ...
}
```

| Value | Renders | read() |
|---|---|---|
| `enabled` | Normal, interactive | Reads from field state |
| `disabled` | Shown, greyed out, non-interactive | Reads from field state |
| `hidden` | Not rendered | Uses `hiddenDefaults` |

Callbacks receive the current `FormContext` snapshot on every `build()`, enabling cross-field visibility rules (e.g. hide `notes` when `available == false`).

**`AddVehicleInputDefaults`** — values for hidden fields only. Non-nullable hidden fields with `null` default cause `read()` to throw. List fields and input fields excluded.

**`AddVehicleInputValidations`** — validator per field. Validators receive the field value AND the current `FormContext`, enabling cross-field validation. ⚡ changed (phase 9)

| Field type | Validator signature |
|---|---|
| `String`, `ID`, `Int`, `Float` | `String? Function(String?, AddVehicleInputFormContext)?` |
| enum | `String? Function(EnumType?, AddVehicleInputFormContext)?` |
| `Boolean` | `String? Function(bool?, AddVehicleInputFormContext)?` |

Disabled and hidden fields skip validation automatically (guard is generated into every validator closure).

**`AddVehicleInputOrder`** — `int?` per field. Lower values render first. `null` = schema-declaration order (default index = `1000 + schemaIndex`). ⚡ added

**`AddVehicleInputWidgets`** — per-field widget override for enum and bool fields. ⚡ added (phase 3)

**`AddVehicleInputTextConfig`** — per-field `TextFieldOptions?` for text/scalar fields. ⚡ added (phase 4)

```dart
class AddVehicleInputWidgets {
  final EnumFieldWidget? fuelType;   // one per enum field
  final BoolFieldWidget? available;  // one per bool field
  const AddVehicleInputWidgets({this.fuelType, this.available});
}
```

`EnumFieldWidget` and `BoolFieldWidget` are generated once into `widgets/inputs/field_widgets.dart`:

```dart
enum EnumFieldWidget { dropdown, chips, radio }
enum BoolFieldWidget { chips, radio }
```

`null` on a field means "use the global config" (`booleanWidget` / `nullableBooleanWidget`). Setting a value overrides the global config for that field only.

**`AddVehicleInputTextConfig`** — per-field `TextFieldOptions?` for every text/scalar field. ⚡ added (phase 4)

---

### Widget — required indicator params ⚡ added (phase 5)

Three new fields on every generated form widget (runtime, not build-time config):

```dart
class AddVehicleInputForm extends InputFormWidget<AddVehicleInput> {
  ...
  final RequiredIndicator requiredIndicator; // default: RequiredIndicator.asterisk
  final Widget? requiredLabel;               // overrides the indicator widget for required fields
  final Widget? optionalLabel;               // overrides the indicator widget for optional fields
}
```

`RequiredIndicator` — generated once into `widgets/inputs/required_indicator.dart`:

```dart
enum RequiredIndicator { none, asterisk, requiredText, optionalText }
```

| Mode | Effect |
|---|---|
| `none` | No indicator |
| `asterisk` | Required fields: label + red ` *` (default) |
| `requiredText` | Required fields: label + small red `required` |
| `optionalText` | Nullable fields: label + small dimmed `optional` |

`requiredLabel` / `optionalLabel` replace the default indicator widget entirely when provided. The `isRequired` flag is baked at generation time from `!f.type.nullable` — zero runtime cost for classification.

A `_requiredLabel(Widget label, bool required)` helper is generated into the state class and applied to every field label in `_visibleRows()`.

```dart
class AddVehicleInputTextConfig {
  final TextFieldOptions? brand;
  final TextFieldOptions? notes;
  // one per text/scalar field
  const AddVehicleInputTextConfig({this.brand, this.notes});
}
```

`TextFieldOptions` — generated once into `widgets/inputs/text_field_options.dart`:

```dart
class TextFieldOptions {
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool obscureText;        // enables password mode with show/hide toggle
  final int? maxLength;
  final int? maxLines;
  final InputDecoration Function(InputDecoration)? decoration;  // transformer callback

  const TextFieldOptions({
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.obscureText = false,
    this.maxLength,
    this.maxLines = 1,
    this.decoration,
  });
}
```

**Decoration callback**: `decoration` receives the generator's base `InputDecoration` (with label and any password toggle icon already applied) and returns a modified copy. Callers use `copyWith` to add prefix icons, change borders, etc. without losing the label.

```dart
TextFieldOptions(
  decoration: (d) => d.copyWith(prefixIcon: const Icon(Icons.email_outlined)),
)
```

**Smart defaults** — baked at generation time by field name (no runtime cost):

| Field name pattern | Applied defaults |
|---|---|
| `email` | `keyboardType: emailAddress, autocorrect: false, enableSuggestions: false` |
| `phone` | `keyboardType: phone` |
| `url`, `website` | `keyboardType: url, autocorrect: false, enableSuggestions: false` |
| `password`, `secret`, `pin` | `obscureText: true, autocorrect: false, enableSuggestions: false` |
| `Int` / `Float` scalar type | `keyboardType: number` |
| everything else | all defaults above |

`TextFieldOptions` always wins over smart defaults for any field it is applied to.

**Password mode**: Fields matching the password pattern get `bool _${field}Obscured = true` state and a `suffixIcon` toggle (`Icons.visibility` / `Icons.visibility_off`). The toggle icon is inserted into the base decoration before the user's `decoration` callback runs, so the callback can still override or replace it.

A `_textDecoration(Widget label, TextFieldOptions? opts, Widget? suffixIcon)` helper is generated into the state class:
```dart
InputDecoration _textDecoration(Widget label, TextFieldOptions? opts, Widget? suffixIcon) {
  var d = _decoration(label);
  if (suffixIcon != null) d = d.copyWith(suffixIcon: suffixIcon);
  return opts?.decoration?.call(d) ?? d;
}
```

---

### Layout enums

```dart
enum AddVehicleInputLayout { column, twoColumn }
enum AddVehicleInputLabelPosition { beside, above, floatingLabel }
```

Note: `card` was removed — it had no useful behaviour over `column`.

---

### Widget

```dart
class AddVehicleInputForm extends InputFormWidget<AddVehicleInput> {
  final AddVehicleInput? initialValues;    // pre-populates all fields; null = empty form

  // list fields
  final List<FuelType> fuelTypes;          // [FuelType!]! — enum list, no Options param
  final List<String> tags;                 // [String!]! — scalar list, default []
  final List<String>? tagsOptions;         // options for scalar list chips/checkboxes

  final AddVehicleInputDropdownLabels? dropdownLabels;
  final AddVehicleInputLabels?         labels;
  final AddVehicleInputValues?         values;
  final AddVehicleInputVisibility?     visibility;
  final AddVehicleInputOrder?          order;
  final AddVehicleInputDefaults?       hiddenDefaults;
  final AddVehicleInputValidations?    validations;
  final AddVehicleInputWidgets?        widgets;   // ⚡ added (phase 3)
  final AddVehicleInputTextConfig?     textConfig; // ⚡ added (phase 4)
  final AddVehicleInputLayout          layout;
  final AddVehicleInputLabelPosition   labelPosition;
  final double                         labelWidth;
  final double                         gap;
  ...
}
```

**List field constructor params:**
- Enum list (`[FuelType!]!`): `this.fuelTypes = const <FuelType>[]` — no Options param; possible values come from `EnumType.values`.
- Scalar list (`[String!]!`): `this.tags = const <String>[]` plus `this.tagsOptions` — `null` options → empty group (no chips rendered).

---

**`initialValues` behaviour:**
- Text controllers seeded via `TextEditingController(text: initialValues?.field ?? '')` (int/double use `.toString()`)
- Enum state set to `initialValues?.fuelType`
- Bool state set to `initialValues?.available ?? false` (nullable bool: `initialValues?.available`)
- List fields are unaffected — they use their own constructor params as before
- `didUpdateWidget` does not reset on `initialValues` change (set once at construction)

Three canonical use cases:
```dart
AddVehicleInputForm(key: _key)                           // create — empty
AddVehicleInputForm(key: _key, initialValues: existing)  // edit — pre-populated
AddVehicleInputForm(key: _key, initialValues: prefilled) // integration test — drive only what matters
```

---

### State

`AddVehicleInputFormState` is **public** (required for `GlobalKey`).

```dart
class AddVehicleInputFormState extends InputFormState<AddVehicleInput> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _brandController;   // one per text field

  FuelType? _fuelType;          // enum field state
  bool _available = false;      // Boolean! (switch/checkbox global config)
  // bool? _available;          // Boolean! with tristate config, or any Boolean?

  late List<FuelType> _fuelTypes;   // [FuelType!]! — late (dart2js)
  List<String>? _tags;              // nullable list — implicitly null
}
```

---

### `read()` method

Triggers `Form` validation, throws `InputReadException` on failure, then builds the typed input.

- **Non-nullable visible**: reads from state or controller; required validators run.
- **Nullable visible**: reads from state or controller; null is valid.
- **Hidden non-nullable**: `hiddenDefaults?.field ?? throw InputReadException(...)`.
- **Hidden nullable**: `hiddenDefaults?.field` — null is valid.
- **List fields**: always from state `_list`, never from `hiddenDefaults`.

---

### Label positioning

Every generated form has helpers to handle label layout at runtime:

**`_field(label, input)`** — wraps text, enum (dropdown), list, and tristate bool fields:

```dart
// beside  → Row(SizedBox(labelWidth, label), Expanded(input))
// above   → Column(label, SizedBox(4), input)
// floating → input  (label is in InputDecoration)
```

**`_decoration(label)`** — attached to `TextFormField` / `DropdownButtonFormField`.

**`_switchBoolField(label, value, onChanged)`** — handles all three label positions for Switch.

**`_checkboxBoolField(label, value, tristate, onChanged)`** — same for Checkbox.

Switch/Checkbox fields call their helper from inside a `FormField` builder and do **not** go through the outer `_field` wrapper. Tristate and chips/radio use `_field` for the default dropdown case.

---

### `_visibleRows()` — field ordering ⚡ fixed

Fields now iterate in **schema declaration order** (not grouped by type). Default order index = `1000 + schemaIndex`. `AddVehicleInputOrder` can override per-field.

---

### Per-field widget override ⚡ added (phase 3)

Each enum field and each bool field gets its own `_${fieldName}Row(Widget label)` method generated in the state class. The method does a `switch` on `_form.widgets?.fieldName`:

**Enum field row (`chips` case):**
- Wrapped in `FormField<EnumType?>` with `autovalidateMode: AutovalidateMode.onUserInteraction`
- Required validator for non-nullable fields; custom validator always chained
- `ChoiceChip` per value with `key: ValueKey(e)` — stable test finder regardless of label ⚡ added (phase 5)
- `field.didChange(v)` on select/deselect
- Each chip gets `side: field.hasError ? BorderSide(color: errorColor) : null` — borders turn red in error state ⚡ added (phase 5)
- Error text rendered below chips via `Theme.of(context).colorScheme.error`

**Enum field row (`radio` case):**
- Same `FormField` wrapper and validation
- Radio tiles wrapped in a `Container` with `BoxDecoration(border: Border.all(color: errorColor), borderRadius: 4)` when `field.hasError` ⚡ added (phase 5)
- `RadioListTile<EnumType?>` per value with `key: ValueKey(e)` ⚡ added (phase 5)

**Enum field row (`null` / default):**
- Falls through to `_field(label, _enumDropdownExpr)` — existing dropdown behavior

**Bool field row (`chips` / `radio` cases):**
- `FormField<bool>` (non-nullable) or `FormField<bool?>` (nullable/tristate)
- `autovalidateMode: AutovalidateMode.onUserInteraction`
- Custom `trueLabel`/`falseLabel` from `dropdownLabels?.fieldName`
- Chips: `key: const ValueKey(true/false)` + same `side` error border ⚡ added (phase 5)
- Radio: `key: const ValueKey(true/false)` + same `Container` error border ⚡ added (phase 5)
- Error text rendered the same way as enum fields
- For non-nullable chips: only `if (on)` branch fires — value is always true or false

**Bool field row (`null` / default):**
- Falls through to existing global-config behavior (switch/checkbox/tristate dropdown)

`_serializeVisibleRowsMethod` routes enum and bool fields through their row method:
```dart
entries.add(MapEntry(ord.fieldName ?? idx, _form.values?.fieldName ?? _fieldNameRow(label)));
```
List chip/checkbox fields continue to render inline (no row method).

---

### List fields ⚡ added (phase 2/3)

**Enum list fields** (`[FuelType!]!`):
- Global `listWidget: chips` → `FilterChip` multi-select per `EnumType.values`
- Global `listWidget: checkboxes` → `CheckboxListTile` per value
- Initial selection passed as constructor param (default `const <T>[]`)
- `enumLabelImports` covers list-of-enum fields so `FuelTypeLabels` is importable

**Scalar list fields** (`[String!]!`, `[Int!]!`, `[Float!]!`):
- Same widgets, but caller passes `List<T>? ${fieldName}Options`
- `null` options → empty group (no chips rendered)
- `_isScalarListField` checks `_dartSerializer.typeMap.containsKey(innerType)`

**Design rationale — no dynamic list editing:**

The generator only renders list fields when the option set is known at widget-construction time (enum values are always known; scalar options are passed via `${field}Options`). This is intentional.

When the list items are dynamic and domain-specific (e.g. a list of entity IDs), the generator cannot know how to search, display, or paginate those items. The correct pattern is the **replacement widget + constructor param** combo:

```dart
// Parent holds the selected IDs in its own state
List<String> _collaboratorIds = existingIds;

AddProjectInputForm(
  key: _key,
  collaboratorIds: _collaboratorIds,           // data — feeds read()
  values: AddProjectInputValues(
    collaboratorIds: CollaboratorPicker(       // custom UI — caller owns this
      selected: _collaboratorIds,
      onAdd: (id) => setState(() => _collaboratorIds.add(id)),
      onRemove: (id) => setState(() => _collaboratorIds.remove(id)),
    ),
  ),
)
// read() returns _collaboratorIds — form just passes it through
```

`didUpdateWidget` syncs `_collaboratorIds` in the form state on each rebuild, so `read()` always returns the current selection regardless of how the caller modifies it. The generator owns the data contract; the caller owns the UX.

---

### Shared base files

Generated once into `widgets/inputs/`:

| File | Contents |
|---|---|
| `input_form_widget.dart` | `InputFormWidget<T>` / `InputFormState<T>` |
| `input_read_exception.dart` | `InputReadException` |
| `boolean_labels.dart` | `BooleanLabels` |
| `field_widgets.dart` | `EnumFieldWidget`, `BoolFieldWidget` ⚡ added (phase 3) |
| `text_field_options.dart` | `TextFieldOptions` ⚡ added (phase 4) |
| `required_indicator.dart` | `RequiredIndicator` ⚡ added (phase 5) |
| `date_input_config.dart` | `DateInputConfig`, `DateInputMode`, `DateType` ⚡ added (phase 7) |
| `date_input_formatter.dart` | `DateInputFormatter` ⚡ added (phase 7) |
| `field_visibility.dart` | `FieldVisibility { enabled, disabled, hidden }` ⚡ added (phase 9) |
| `simple_field_form.dart` | `SimpleFieldForm<T>` — thin helper for inline field overrides ⚡ added (phase 9) |

---

## Architecture: `GlInputEntity`

```dart
class GlInputEntity {
  final GLInputDefinition input;
  GlInputEntity(this.input, this._parser);

  String get name => input.token;
  List<GLField> get fields => input.getSerializableFields(CodeGenerationMode.client);

  Set<String> enumDataImports(String prefix) { ... }  // scalar + list-of-enum data classes
  Set<String> enumLabelImports(String prefix) { ... }  // scalar + list-of-enum label classes
}
```

Field classification (text / enum / bool / list / nested) lives in `FlutterInputsTypeHelpers`. ⚡ refactored (phase 9)

The generator is split into 7 collaborating classes under `lib/src/serializers/flutter_inputs/`:

```
FlutterInputsSerializer          ← orchestrator, public API
  FlutterInputsTypeHelpers        ← field classification, smart defaults, FormContext/Values type helpers
  FlutterInputsSharedSerializer   ← once-generated shared file strings
  FlutterInputsCompanionSerializer ← companion class code generation
  FlutterInputsFieldSerializer    ← field widget expressions + row methods
  FlutterInputsDateSerializer     ← date row + picker helpers
  FlutterInputsStateSerializer    ← widget class, state class, layout helpers
```

Dependency chain: `TypeHelpers ← FieldSerializer ← DateSerializer ← StateSerializer ← Orchestrator`.

---

## File layout

```
lib/generated/
  inputs/
    add_vehicle_input.dart               ← data class (unchanged)
  widgets/
    inputs/
      input_form_widget.dart             ← generated once
      input_read_exception.dart          ← generated once
      boolean_labels.dart                ← generated once
      field_widgets.dart                 ← generated once (phase 3)
      text_field_options.dart            ← generated once (phase 4)
      required_indicator.dart            ← generated once (phase 5)
      field_visibility.dart              ← generated once (phase 9)
      simple_field_form.dart             ← generated once (phase 9)
      add_vehicle_input_form.dart        ← all generated items for this input
    enums/
      fuel_type_labels.dart              ← extended with unselected field (phase 1) ⚡ fixed (phase 6)
```

---

## Key files

| File | Role |
|---|---|
| `lib/src/config.dart` | `FlutterConfig`, `BooleanWidget`, `NullableBooleanWidget`, `ListWidget` |
| `lib/src/model/gl_ui_entity.dart` | `GlInputEntity` — import resolution |
| `lib/src/serializers/flutter_types_serializer.dart` | Type widgets + enum labels |
| `lib/src/serializers/flutter_inputs/flutter_inputs_serializer.dart` | Thin orchestrator — public entry point ⚡ refactored (phase 9) |
| `lib/src/serializers/flutter_inputs/flutter_inputs_type_helpers.dart` | Field classification, smart defaults, FormContext helpers ⚡ added (phase 9) |
| `lib/src/serializers/flutter_inputs/flutter_inputs_shared_serializer.dart` | Once-generated shared file content ⚡ added (phase 9) |
| `lib/src/serializers/flutter_inputs/flutter_inputs_companion_serializer.dart` | Companion class generation (FormContext, Visibility, Values, Validations, etc.) ⚡ added (phase 9) |
| `lib/src/serializers/flutter_inputs/flutter_inputs_field_serializer.dart` | Field widget expressions + row methods ⚡ added (phase 9) |
| `lib/src/serializers/flutter_inputs/flutter_inputs_date_serializer.dart` | Date row method + picker helpers ⚡ added (phase 9) |
| `lib/src/serializers/flutter_inputs/flutter_inputs_state_serializer.dart` | Widget class, state class, layout helpers ⚡ added (phase 9) |
| `lib/src/generators/dart_client_generator.dart` | Hooks both serializers, writes shared files |
| `examples/flutter/ui_types/` | Live example — 12 tabs covering all features |
| `examples/flutter/ui_types/GRAPHLINK_FLUTTER_GUIDE.md` | AI agent reference guide ⚡ added (phase 9) |

---

## Open questions resolved

1. `Values` + `read()` interaction — Option A. No controller for overridden fields; `read()` uses `hiddenDefaults` or throws. ✅
2. `Boolean?` + `switchWidget` — two separate config keys. ✅
3. Enum null option label — `FuelTypeLabels.unselected`. ✅
4. Nested input — deferred to phase 4.
5. `inputsToSkip` — implemented. ✅
6. Switch/Checkbox `Form` validation — `FormField<bool>` wrapping. ✅
7. Default list display — `Text('N items')`. ✅
8. Field declaration order — fixed; fields render in schema order. ✅
9. Chips/radio validation — `FormField` + `autovalidateMode` + `field.errorText` display. ✅ (phase 3)
10. Text field options — `TextFieldOptions` + `${Input}TextConfig` companion class. ✅ (phase 4)
11. Password support — auto-detected by field name, `_obscured` state + show/hide toggle. ✅ (phase 4)
12. Smart keyboard defaults — baked at generation time from field name and scalar type. ✅ (phase 4)
13. Decoration callback — `InputDecoration Function(InputDecoration)?` lets callers add prefix icons etc. without losing the generated label. ✅ (phase 4)
14. Chip/radio error styling — chips get `side` border in error color; radio groups get a `Container` outline border. ✅ (phase 5)
15. Dropdown placeholder style — "Choose an option" renders italic + `hintColor` to distinguish it from real values. ✅ (phase 5)
16. Required field indicator — `RequiredIndicator` enum on the form widget (runtime, not config); default `asterisk`; custom `requiredLabel`/`optionalLabel` widgets supported. ✅ (phase 5)
17. `initialValues` — optional typed input pre-populates all form fields; covers create/edit/test flows without a separate companion class. ✅ (phase 5)
18. `ValueKey` on chips and radio tiles — `ValueKey(enumValue)` on enum widgets, `const ValueKey(true/false)` on bool widgets; stable test finders independent of custom labels. ✅ (phase 5)
19. `FuelTypeLabels.unselected` — `unselected: Widget?` field generated on all `${Enum}Labels` classes; used as the null dropdown item label. ✅ (phase 6, was missing from types serializer)
20. Accessibility — four fixes applied in phase 6. ✅
    - Password toggle `IconButton` gets `tooltip: 'Show/Hide password'` (screen reader announcement)
    - Required `*` indicator gets `semanticsLabel: 'required'` (reads "required" instead of "asterisk")
    - Error text below chips/radio wrapped in `Semantics(liveRegion: true)` (announced immediately on appearance)
    - Radio group error border `Container` wrapped in `Semantics(label: field.errorText)` (error linked to group, not just visual)
27. Dynamic cross-field visibility — `Visibility` fields changed from `bool` to `FieldVisibility Function(FormContext)?`; callbacks receive a live snapshot of all field values; `FieldVisibility.disabled` renders but blocks interaction. ✅ (phase 9)
28. Cross-field validation — validator signatures extended to `String? Function(T?, FormContext)?`; disabled/hidden fields skip validation automatically via guard generated into every validator closure. ✅ (phase 9)
29. Typed field override — `Values` fields changed from `Widget?` to `InputFormWidget<T> Function(Key)?`; parent form generates and owns the `GlobalKey`; `read()` delegates to `overrideKey.currentState!.read()`; hidden wins over override (no crash on unmounted widget). ✅ (phase 9)
30. `SimpleFieldForm<T>` — shared helper class for simple inline field overrides without writing a full `StatefulWidget`. ✅ (phase 9)
31. Generator split — monolithic `FlutterInputsSerializer` (~2100 lines) replaced with 7 collaborating injected classes under `flutter_inputs/` folder. ✅ (phase 9)

---

## Testability

### Display widgets

Stateless, pure functions of their data — trivially testable. Pump with known data, assert on text/widget presence. No state, no interaction required.

### Input forms

**What works well:**

- `GlobalKey<${Input}FormState>` — call `read()` after driving the UI; assert on the typed result directly without inspecting the widget tree
- `initialValues` — pre-populate the entire form with a typed input; only drive the one field under test
- Standard Flutter widgets throughout — all `flutter_test` finders and interactions apply
- `read()` throws `InputReadException` on validation failure — easy to assert the error path

**Chip / radio finders — stable by `ValueKey`:**

Every `ChoiceChip` and `RadioListTile` carries a key based on its value, so finders survive label changes:

```dart
// enum chip or radio
await tester.tap(find.byKey(ValueKey(FuelType.HYBRID)));

// bool chip or radio
await tester.tap(find.byKey(const ValueKey(true)));
```

**Text field finders:**

One `TextFormField` per field — disambiguate by position or by ancestor label. Interaction via `tester.enterText()`.

**Remaining friction:**

- `DropdownButtonFormField` requires two taps (open + select menu item) and is notoriously awkward in Flutter tests. Mitigation: pass `widgets: ${Input}Widgets(fieldName: EnumFieldWidget.chips)` in the test to avoid dropdowns entirely.

**Recommended integration test pattern:**

```dart
final key = GlobalKey<AddVehicleInputFormState>();

// pre-fill everything except the field under test
await tester.pumpWidget(MaterialApp(
  home: AddVehicleInputForm(
    key: key,
    initialValues: AddVehicleInput(
      brand: 'Toyota', model: 'Camry', year: 2024,
      fuelType: FuelType.PETROL, available: false,
    ),
    widgets: const AddVehicleInputWidgets(fuelType: EnumFieldWidget.chips),
  ),
));

// drive only what you're testing
await tester.tap(find.byKey(ValueKey(FuelType.HYBRID)));
await tester.pumpAndSettle();

final result = key.currentState!.read();
expect(result.fuelType, FuelType.HYBRID);
expect(result.brand, 'Toyota'); // unchanged from initialValues
```

---

## Accessibility (phase 6)

### Password toggle

`IconButton` for show/hide gets a dynamic `tooltip` so screen readers announce the action:

```dart
IconButton(
  tooltip: _passwordObscured ? 'Show password' : 'Hide password',
  icon: Icon(_passwordObscured ? Icons.visibility_off : Icons.visibility),
  onPressed: () => setState(() => _passwordObscured = !_passwordObscured),
)
```

### Required indicator

The `*` asterisk `Text` widget carries `semanticsLabel: 'required'` so screen readers say "required" instead of "asterisk" or " star":

```dart
_form.requiredLabel ?? Text(' *', semanticsLabel: 'required', style: ...)
```

### Chip / radio error text — live region

Error text rendered below chips and radio groups is wrapped in `Semantics(liveRegion: true)` so it is announced immediately when it appears:

```dart
if (field.errorText != null) Semantics(
  liveRegion: true,
  child: Padding(
    padding: const EdgeInsets.only(top: 4, left: 4),
    child: Text(field.errorText!, style: ...),
  ),
)
```

### Radio group error border — semantic label

The `Container` that shows the red outline border on validation error is wrapped in `Semantics(label: field.errorText)` so the error is also associated with the group itself, not just the live-region text below:

```dart
Semantics(
  label: field.hasError ? field.errorText ?? '' : null,
  child: Container(decoration: field.hasError ? BoxDecoration(...) : null, ...),
)
```

---

## Date inputs (phase 7)

### Overview

Date fields are detected at **runtime** — no generator re-run needed. Any `Int` or `String` field becomes a date field when a non-null `DateInputConfig` is provided for it in `${Input}DateConfig`. Fields without a config retain their regular behaviour (number field / text field).

**Part I** — `Int` fields (epoch ms): `Int` → pick date → `DateTime.millisecondsSinceEpoch`  
**Part II** — `String` fields (formatted string): `String` → pick date → `DateFormat(pattern).format(picked)`

### New shared files

| File | Contents |
|---|---|
| `widgets/inputs/date_input_config.dart` | `DateInputConfig`, `DateInputMode`, `DateType` |
| `widgets/inputs/date_input_formatter.dart` | `DateInputFormatter extends TextInputFormatter` |

### `DateInputConfig`

```dart
enum DateType { date, dateTime }
enum DateInputMode { dialog, inline }

class DateInputConfig {
  final DateType type;              // date or dateTime
  final DateInputMode mode;         // dialog (showDatePicker) or inline (future)
  final String pattern;             // e.g. 'yyyy-MM-dd', 'dd/MM/yyyy'
  final bool allowKeyboardInput;    // true → editable + auto-formatter; false → read-only, tap opens picker
  final DateTime? firstDate;        // min selectable date
  final DateTime? lastDate;         // max selectable date
  final DateTime? initialDate;      // shown in picker when no value yet selected

  const DateInputConfig({
    this.type = DateType.date,
    this.mode = DateInputMode.dialog,
    this.pattern = 'yyyy-MM-dd',
    this.allowKeyboardInput = true,
    this.firstDate,
    this.lastDate,
    this.initialDate,
  });
}
```

### `${Input}DateConfig` companion class

Generated when the input has at least one `Int` or `String` field. Has `DateInputConfig?` per eligible field:

```dart
class AddVehicleInputDateConfig {
  final DateInputConfig? year;    // Int field
  final DateInputConfig? notes;   // String field
  const AddVehicleInputDateConfig({this.year, this.notes});
}
```

Added as `final ${inputName}DateConfig? dateConfig;` on the form widget + `this.dateConfig` in the constructor.

### Widget behaviour

For each `Int` / `String` field the generated code branches at runtime:

```dart
// Int field example
_form.dateConfig?.year != null
    ? TextFormField(
        controller: _yearController,
        readOnly: !(_form.dateConfig!.year!.allowKeyboardInput),
        keyboardType: ... ? TextInputType.datetime : TextInputType.none,
        inputFormatters: ... ? [DateInputFormatter(pattern)] : const [],
        onTap: allowKeyboardInput ? null : () => _pickDate(_yearController, config),
        decoration: _textDecoration(label, null, IconButton(
          tooltip: type == DateType.dateTime ? 'Pick date & time' : 'Pick date',
          icon: const Icon(Icons.calendar_today_outlined),
          onPressed: () => _pickDate(_yearController, config),
        )),
        validator: ...,
      )
    : TextFormField(   // regular number field — unchanged behaviour
        controller: _yearController,
        keyboardType: TextInputType.number,
        ...
      )
```

**`onTap` rule**: when `allowKeyboardInput` is `false` the field is read-only and `onTap` opens the picker directly. When `true` the field is editable and only the calendar icon opens the picker.

### `_pickDate` helper (generated per state class)

Chains `showDatePicker` + `showTimePicker` for `DateType.dateTime`; uses `DateFormat(config.pattern).format(picked)` to populate the controller:

```dart
Future<void> _pickDate(TextEditingController controller, DateInputConfig config) async {
  // parse existing controller text → initialDate
  // showDatePicker (always)
  // if DateType.dateTime → also showTimePicker
  // setState(() => controller.text = DateFormat(config.pattern).format(picked))
}
```

### `_parseDate` helper (Int fields only)

```dart
int? _parseDate(String text, DateInputConfig config) {
  if (text.isEmpty) return null;
  try { return DateFormat(config.pattern).parse(text).millisecondsSinceEpoch; }
  catch (_) { return null; }
}
```

### `read()` differences

| Field type | Without dateConfig | With dateConfig |
|---|---|---|
| `Int!` | `int.parse(controller.text)` | `_parseDate(...)! ` |
| `Int?` | `int.tryParse(controller.text)` | `_parseDate(...)` |
| `String!` | `controller.text` | `controller.text` (same — already formatted) |
| `String?` | `controller.text.isEmpty ? null : controller.text` | same |

### `initialValues` for Int date fields

```dart
_yearController = TextEditingController(
  text: _form.dateConfig?.year != null && _form.initialValues?.year != null
      ? DateFormat(_form.dateConfig!.year!.pattern)
          .format(DateTime.fromMillisecondsSinceEpoch(_form.initialValues!.year))
      : _form.initialValues?.year.toString() ?? '',
);
```

String date fields use `initialValues?.field` directly — already a formatted string.

### `DateInputFormatter`

Auto-inserts the pattern separator (e.g. `-` or `/`) as the user types:

```dart
class DateInputFormatter extends TextInputFormatter {
  // strips non-digits, replays through pattern, inserts separators at the right positions
  // length capped naturally by the pattern length
}
```

### Open questions resolved (phase 7)

21. Date as `Int` (epoch ms) — `_parseDate` + `DateInputFormatter` + `_pickDate`. ✅
22. Date as `String` (formatted) — same widget shape, `read()` returns controller text directly. ✅
23. Runtime detection — no generator config needed; `DateInputConfig?` slot generated for all `Int` and `String` fields; opt-in per field at runtime. ✅
24. `allowKeyboardInput: false` tap handling — `onTap` on the `TextFormField` opens the picker when read-only; calendar icon always available as secondary trigger. ✅
25. `DateType.dateTime` — chains `showDatePicker` + `showTimePicker`; guards `!mounted` between the two awaits. ✅
26. `CalendarDatePicker` initial date assertion — `_clampDate` generated into every date-aware state class; applied to all three picker paths before any date reaches a Flutter widget. ✅ (phase 8)

---

## Date guard (phase 8)

`_clampDate(date, first, last)` is generated into every state class that has date-eligible fields. It is applied to the derived `initialDate` in all three date picker paths before the date reaches any Flutter widget:

- `_pickDateMaterial` — clamps before passing to `showDatePicker`
- `_pickDateCupertino` — clamps before passing to `CupertinoDatePicker`
- Inline `CalendarDatePicker` / `CupertinoDatePicker` — clamps the `initialDateExpr`

This ensures that even if `initialValues` carries an out-of-range epoch value, the picker opens without assertion errors, defaulting to the nearest boundary date.

```dart
DateTime _clampDate(DateTime date, DateTime first, DateTime last) {
  if (date.isBefore(first)) return first;
  if (date.isAfter(last)) return last;
  return date;
}
```

---

## Out of scope (by design)

- **Dynamic list editing (add/remove/reorder)** — intentionally not generated. The generator only handles list fields with a known option set (enum values, or caller-supplied `${field}Options`). For domain-specific lists (e.g. list of IDs with a search UI), use the replacement widget + constructor param pattern described in the list fields section above. The generator owns the data contract; the caller owns the UX.
- **`FormStrings` + `AppLocalizations` auto-wiring** — `FormStrings` is manual by design: wire it from your localization delegate in your widget's `build` method. Auto-integration would couple the generator to a specific localization approach.
- **Cupertino form fields** — text fields, checkboxes, switches remain Material. Cupertino applies to date pickers only (auto-detected or forced via `useCupertino`).
