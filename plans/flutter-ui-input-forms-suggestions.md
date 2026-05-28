# Flutter UI Input Forms — Improvement Suggestions

Suggestions for future phases, ordered roughly by value/effort ratio.

---

## High value, low complexity

### 1. `reset()` ✅ implemented (phase 11)
Restores all fields to `initialValues` or empty. Partial reset via `fields: ['fieldName']`.

### 2. `isDirty` getter ✅ implemented (phase 11)
Returns `true` if any field differs from its initial value. Useful for unsaved-changes guards (`PopScope`).

### 3. Scroll to first error ✅ implemented (phase 11)
`read()` automatically scrolls to the first invalid field after validation fails. Uses `Scrollable.ensureVisible` — works with any parent scroll container. Order-aware via `${Input}Order`.

---

## Medium value

### 4. Async validators
**Status:** Not implemented

Validator signatures currently only support synchronous functions (`String? Function(T?, FormContext)?`). Many real-world cases require async validation: username availability checks, remote duplicate detection, server-side business rules.

**Proposed API:**
```dart
class AddVehicleInputValidations {
  final Future<String?> Function(String?, AddVehicleInputFormContext)? brand;
  // or keep sync + add separate async companion:
  final String? Function(String?, AddVehicleInputFormContext)? brand;
  final Future<String?> Function(String?, AddVehicleInputFormContext)? brandAsync;
}
```

**Implementation notes:**
- Flutter's `FormField` validator is synchronous — async validation requires manual state management
- One `bool _${field}Validating` flag + one `String? _${field}AsyncError` per field
- Trigger async validation in `onChanged` (debounced) rather than in the `FormField` validator
- Display async error below the field the same way as regular error text
- `read()` should await all pending async validators before proceeding (or block if any are in-flight)

---

### 5. `submitting` flag ✅ implemented (phase 11)

Every form needs a way to disable all fields and show a loading indicator while an async submit operation runs. Currently callers rebuild the whole widget tree to fake this.

**Proposed API:**
```dart
// on the state class
void setSubmitting(bool value)  // or: bool submitting setter
bool get isSubmitting
```

**Behaviour:**
- `setSubmitting(true)` disables all fields (same as `FieldVisibility.disabled` for every field) and optionally shows a `CircularProgressIndicator` somewhere configurable
- `setSubmitting(false)` restores normal interaction
- `read()` throws if called while `isSubmitting == true`

**Alternative:** expose a `submitting` parameter on the form widget and let the developer control it from outside — simpler, no state mutation API needed.

---

### 6. Field groups
**Status:** Not implemented

Clusters of related fields under a visual header or divider. Purely presentational — no impact on `read()` or validation.

**Proposed API:**
```dart
class AddVehicleInputGroups {
  final List<String>? basicInfo;   // ['brand', 'model', 'year']
  final List<String>? details;     // ['fuelType', 'mileage', 'available']
  const AddVehicleInputGroups({this.basicInfo, this.details});
}
```

Added as `final AddVehicleInputGroups? groups;` on the form widget.

**Behaviour:**
- Fields not assigned to any group render ungrouped (current behaviour)
- Each group renders with a `Text` header above it (auto-humanized from the key name, or overridable via a companion `${groupName}Label` parameter)
- An optional `Divider` between groups (configurable)
- Group order follows the lowest effective order index of its fields

---

## Nice to have

### 7. Inline error summary
**Status:** Not implemented

A generated `${Input}ErrorSummary` widget that renders a list of all current validation error messages. Useful for long forms and accessibility.

**Proposed API:**
```dart
// Standalone widget, reads from the same GlobalKey
AddVehicleInputErrorSummary(formKey: _key)
```

**Behaviour:**
- Hidden when no errors
- Shows after the first `validate()` call
- Each error is a tappable row that scrolls to the offending field via `Scrollable.ensureVisible`
- Updates reactively as the user fixes errors

---

### 8. `FocusNode` exposure
**Status:** Not implemented

Lets callers control focus programmatically — e.g., focus the first field on screen load, or move focus to a specific field after a conditional visibility change.

**Proposed API:**
```dart
class AddVehicleInputFocusNodes {
  final FocusNode? brand;
  final FocusNode? model;
  // one per text field
  const AddVehicleInputFocusNodes({this.brand, this.model});
}
```

Added as `final AddVehicleInputFocusNodes? focusNodes;` on the form widget.

**Behaviour:**
- When a `FocusNode` is provided for a field, it is passed to the generated `TextFormField`
- The caller owns the `FocusNode` lifecycle (`dispose()`)
- Useful for `TextInputAction.next` chains across conditionally visible fields
