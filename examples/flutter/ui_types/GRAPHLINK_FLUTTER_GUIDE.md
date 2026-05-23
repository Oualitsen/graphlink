# GraphLink Flutter UI — AI Agent Guide

This document tells an AI agent everything it needs to use GraphLink-generated Flutter forms and display widgets in a real project. Read it fully before writing any code.

---

## What GraphLink generates

From a GraphQL schema, GraphLink generates two categories of Flutter code under `lib/generated/`:

| Directory | Contents |
|---|---|
| `widgets/inputs/` | One form file per `input` type + shared runtime files |
| `widgets/types/` | One display widget file per `type` + enum label helpers |
| `inputs/` | Plain Dart data classes (the GraphQL input types) |
| `types/` | Plain Dart data classes (the GraphQL response types) |
| `enums/` | Dart enums from GraphQL enum definitions |

Regenerate at any time by running `dart run lib/generate.dart` from the example root. **Never edit files in `lib/generated/`** — they are overwritten on every generation.

---

## Shared runtime files (generated once)

These live in `widgets/inputs/` and are imported by every generated form:

| File | Key type |
|---|---|
| `input_form_widget.dart` | `InputFormWidget<T>`, `InputFormState<T>` |
| `input_read_exception.dart` | `InputReadException` |
| `field_visibility.dart` | `FieldVisibility { enabled, disabled, hidden }` |
| `form_strings.dart` | `FormStrings` — all user-facing strings (localizable) |
| `required_indicator.dart` | `RequiredIndicator { none, asterisk, requiredText, optionalText }` |
| `field_widgets.dart` | `EnumFieldWidget`, `BoolFieldWidget` |
| `text_field_options.dart` | `TextFieldOptions` |
| `date_input_config.dart` | `DateInputConfig`, `DateType`, `DateInputMode` |
| `date_input_formatter.dart` | `DateInputFormatter` |
| `boolean_labels.dart` | `BooleanLabels` |
| `simple_field_form.dart` | `SimpleFieldForm<T>` — thin helper for field value overrides |

---

## Form anatomy — AddVehicleInputForm as example

Every generated form produces these classes in a single file:

```
AddVehicleInputFormContext     — snapshot of current field values (for callbacks)
AddVehicleInputDropdownLabels  — custom label widgets for enum/bool options
AddVehicleInputLabels          — custom label widget per field + optional String? *Info for info dialogs
AddVehicleInputValues          — replace a field's entire widget with your own
AddVehicleInputVisibility      — control per-field visibility (callback-based)
AddVehicleInputDefaults        — values for hidden fields (used by read())
AddVehicleInputValidations     — custom validators per field
AddVehicleInputOrder           — render order override per field
AddVehicleInputWidgets         — enum/bool widget style per field
AddVehicleInputTextConfig      — TextFieldOptions per text field
AddVehicleInputDateConfig      — DateInputConfig per Int/String field
AddVehicleInputLayout          — { column, twoColumn }
AddVehicleInputLabelPosition   — { beside, above, floatingLabel }
AddVehicleInputForm            — the StatefulWidget
AddVehicleInputFormState       — the State (public, needed for GlobalKey)
```

---

## Minimal usage

```dart
final _key = GlobalKey<AddVehicleInputFormState>();

// In build():
AddVehicleInputForm(key: _key)

// On submit:
try {
  final AddVehicleInput input = _key.currentState!.read();
  // use input
} on InputReadException catch (e) {
  // validation failed — e.message has the reason
}
```

`read()` triggers `Form.validate()` internally. It throws `InputReadException` on failure. On success it returns a fully-typed data object.

---

## Visibility — FieldVisibility

Each field in the `Visibility` class is a nullable callback `FieldVisibility Function(FormContext)?`. `null` means `enabled`.

```dart
enum FieldVisibility { enabled, disabled, hidden }
```

| Value | Effect in form | Effect in read() |
|---|---|---|
| `enabled` | Normal, interactive | Reads from field state |
| `disabled` | Shown but non-interactive (greyed out) | Reads from field state |
| `hidden` | Not rendered | Uses `hiddenDefaults` |

**Precedence in `read()`**: hidden → hiddenDefaults · override widget present → `overrideKey.currentState!.read()` · otherwise → field state/controller.

### Static visibility

```dart
// Convenience — always hides
FieldVisibility _hidden(Object? _) => FieldVisibility.hidden;

AddVehicleInputForm(
  visibility: const AddVehicleInputVisibility(
    mileage: _hidden,
    notes: _hidden,
  ),
  hiddenDefaults: const AddVehicleInputDefaults(
    mileage: null,
    notes: null,
  ),
)
```

### Dynamic visibility (cross-field)

The callback receives a `FormContext` — a typed snapshot of all current field values. Use it to implement field dependencies:

```dart
AddVehicleInputForm(
  visibility: AddVehicleInputVisibility(
    // hide notes when car is not available
    notes: (ctx) => ctx.available
        ? FieldVisibility.enabled
        : FieldVisibility.hidden,
    // disable mileage for electric vehicles
    mileage: (ctx) => ctx.fuelType == FuelType.ELECTRIC
        ? FieldVisibility.disabled
        : FieldVisibility.enabled,
  ),
)
```

The `FormContext` is rebuilt on every `setState`. Fields in it are:
- Text/scalar fields → `String` (the controller's raw text — never null, empty if unfilled)
- Enum fields → `EnumType?`
- Bool fields → `bool` or `bool?`
- List fields → `List<T>`

---

## Validations — cross-field rules

Validators receive `(fieldValue, FormContext)`. The context gives access to any other field's current value:

```dart
AddVehicleInputForm(
  validations: AddVehicleInputValidations(
    year: (v, ctx) {
      if (ctx.fuelType == FuelType.ELECTRIC) {
        final y = int.tryParse(v ?? '');
        if (y != null && y < 2010) return 'Electric vehicles were not available before 2010';
      }
      return null;
    },
  ),
)
```

A validator returning `null` means the field is valid. Returning a non-null string shows it as an error. Disabled and hidden fields skip validation automatically.

---

## Field override — AddVehicleInputValues

Replace any field's generated widget with your own while keeping `read()` working. Each field accepts a builder `InputFormWidget<T> Function(Key)`.

### Simple inline override with `SimpleFieldForm`

```dart
// Parent holds the selected value
FuelType? _selectedFuel;

AddVehicleInputForm(
  values: AddVehicleInputValues(
    fuelType: (key) => SimpleFieldForm<FuelType>(
      key: key,
      reader: () => _selectedFuel!,
      builder: (ctx) => MyCustomFuelPicker(
        value: _selectedFuel,
        onChanged: (f) => setState(() => _selectedFuel = f),
      ),
    ),
  ),
)
```

### Full custom form widget

For more control, extend `InputFormWidget<T>` directly and implement `read()` in the state:

```dart
class CountryPicker extends InputFormWidget<String> {
  const CountryPicker({super.key});
  @override
  State<InputFormWidget<String>> createState() => _CountryPickerState();
}

class _CountryPickerState extends InputFormState<String> {
  String _selected = 'US';
  @override
  String read() => _selected;
  @override
  Widget build(BuildContext context) => /* your UI */;
}

// Usage:
AddressInputForm(
  values: AddressInputValues(
    country: (key) => CountryPicker(key: key),
  ),
)
```

**Rule**: if a field is hidden (`FieldVisibility.hidden`), its override widget is not mounted. `read()` uses `hiddenDefaults` for that field regardless of whether an override is provided.

---

## Hidden fields + defaults

Hidden fields must have a value in `hiddenDefaults` if they are non-nullable:

```dart
AddVehicleInputForm(
  visibility: const AddVehicleInputVisibility(
    available: _hidden,
    fuelType: _hidden,
  ),
  hiddenDefaults: const AddVehicleInputDefaults(
    available: true,           // non-nullable — required
    fuelType: FuelType.ELECTRIC,
    // mileage, notes — nullable, omitting is fine (defaults to null)
  ),
)
```

`read()` throws `InputReadException` if a hidden non-nullable field has no default.

---

## Pre-populating (edit forms)

Pass `initialValues` with an existing data object:

```dart
AddVehicleInputForm(
  key: _key,
  initialValues: existingVehicle,  // AddVehicleInput
)
```

Text controllers, enum state, and bool state are all seeded from `initialValues` at `initState`. `didUpdateWidget` does not reset on `initialValues` change.

---

## Layout & label position

```dart
AddVehicleInputForm(
  layout: AddVehicleInputLayout.twoColumn,
  labelPosition: AddVehicleInputLabelPosition.beside,
  labelWidth: 140,  // only applies in 'beside' mode
  gap: 16,
)
```

---

## Custom labels and field info dialogs

Each field in `Labels` accepts a `Widget?` label and a companion `String? *Info`. When `*Info` is set, a small `Icons.info_outline` button appears next to the label. Tapping it opens an `AlertDialog` with that string and an OK button.

```dart
AddVehicleInputForm(
  labels: const AddVehicleInputLabels(
    brand: Text('Make'),
    brandInfo: 'The vehicle manufacturer — e.g. Toyota, BMW, Tesla.',
    year: Text('Model year'),
    yearInfo: 'The 4-digit model year. Must be between 1990 and 2030.',
  ),
)
```

- `null` label → auto-humanized default (`Text('Brand')`)
- `null` info → no icon rendered (zero overhead)
- **`floatingLabel` position**: the icon cannot sit inside `InputDecoration.label`, so it is rendered as a trailing button to the right of the field instead
- `toTableRow()` / `toTableHeaderRow()` on display widgets do not show the info icon (no `BuildContext` available)

The same `*Info` fields exist on display widget labels too:

```dart
VehicleWidget(
  vehicle,
  labels: const VehicleLabels(
    fuelType: Text('Fuel type'),
    fuelTypeInfo: 'The propulsion technology: gasoline, diesel, hybrid, or electric.',
  ),
)
```

---

## Enum/bool widget override

```dart
AddVehicleInputForm(
  widgets: const AddVehicleInputWidgets(
    fuelType: EnumFieldWidget.chips,  // dropdown | chips | radio
    available: BoolFieldWidget.radio, // chips | radio
  ),
)
```

---

## Text field options

```dart
AddVehicleInputForm(
  textConfig: RegisterInputTextConfig(
    username: const TextFieldOptions(maxLength: 20),
    email: TextFieldOptions(
      decoration: (d) => d.copyWith(prefixIcon: const Icon(Icons.email_outlined)),
    ),
    bio: const TextFieldOptions(maxLines: 3),
  ),
)
```

Smart defaults are already baked in at generation time (email → emailAddress keyboard, password → obscured, phone → phone keyboard, url/website → url keyboard).

---

## Date fields

Opt any `Int` or `String` field into date-picking at runtime by providing a `DateInputConfig`:

```dart
EventInputForm(
  dateConfig: EventInputDateConfig(
    startDate: DateInputConfig(
      type: DateType.date,
      mode: DateInputMode.dialog,   // dialog | inline
      pattern: 'yyyy-MM-dd',
      allowKeyboardInput: true,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    ),
  ),
)
```

- `Int` fields → picker returns `DateTime.millisecondsSinceEpoch`
- `String` fields → picker returns `DateFormat(pattern).format(picked)`
- `useCupertino: null` → auto-detects iOS/macOS; `true`/`false` forces the picker

---

## Localization via FormStrings

Override any user-facing string at the form widget level:

```dart
AddVehicleInputForm(
  strings: const FormStrings(
    required: 'Obligatoire',
    chooseAnOption: 'Choisir une option',
    yes: 'Oui',
    no: 'Non',
    cancel: 'Annuler',
    done: 'Terminé',
  ),
)
```

---

## Display widgets (type widgets)

Each GraphQL `type` gets a corresponding display widget:

```dart
VehicleWidget(
  vehicle,
  layout: VehicleLayout.listTile,   // labeledRow | listTile | listTileReversed | expandable
  gap: 16,
  labels: const VehicleLabels(
    brand: Text('Make'),
    brandInfo: 'The vehicle manufacturer.',  // shows an info icon next to the label
  ),
  visibility: const VehicleVisibility(notes: false),
  order: const VehicleOrder(notes: 0),  // renders notes first
)
```

Generate a table row and header:

```dart
Table(
  border: TableBorder.all(),
  children: [
    VehicleWidget(vehicle).toTableHeaderRow(),
    VehicleWidget(vehicle).toTableRow(),
  ],
)
```

---

## Required field indicators

```dart
AddVehicleInputForm(
  requiredIndicator: RequiredIndicator.asterisk, // none|asterisk|requiredText|optionalText
  requiredLabel: const Text('*', style: TextStyle(color: Colors.red)),
  optionalLabel: const Text('optional', style: TextStyle(color: Colors.grey, fontSize: 11)),
)
```

---

## Nested input composition

If an input type embeds another input type (e.g. `PersonInput` contains `AddressInput`), the parent form automatically renders the child form. The child validates independently when the parent calls `read()`.

```dart
PersonInputForm(key: _key)
// read() returns PersonInput with a fully-validated embedded AddressInput
```

---

## Common mistakes

| Mistake | Correct |
|---|---|
| Editing `lib/generated/` files | Never — regenerate instead |
| Using `bool` for visibility | Use `(_) => FieldVisibility.hidden` |
| Validator with signature `(v)` | Signature is `(v, ctx)` |
| Forgetting `hiddenDefaults` for hidden non-nullable field | Provide a default or read() throws |
| Calling `read()` without a `GlobalKey` | Always pass `key: _key` to the form |
| Providing a Values override for a hidden field and expecting it to run | Hidden wins — override widget is not mounted |
