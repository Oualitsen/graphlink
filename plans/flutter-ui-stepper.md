# Flutter UI Stepper Layout

## Status: Planned — ready to implement

---

## Core idea

Inputs that contain sub-inputs can be rendered as a `Stepper` by setting
`layout: ${InputName}Layout.stepper`. The schema structure drives the step
structure — no explicit step declaration needed.

---

## Step structure (derived from schema, in declaration order)

| Source | Becomes | Validation on Next |
|---|---|---|
| All scalar / enum / bool / list fields on the parent input | One implicit step (omitted if none exist) | `_formKey.currentState?.validate()` |
| Each `SubInput!` or `SubInput?` field | One step, renders `${SubType}Form` | try `_${name}Key.currentState!.read()`, catch `InputReadException` |
| Each `[SubInput!]!` field | One step — **caller must provide a `Values` override for meaningful content** | If `Values` override present: try `_${name}OverrideKey.currentState!.read()`, catch `InputReadException` → block. No override: always passes. |
| Sub-input tagged `@glSkipOnClient` | Step is not generated | — |

Order follows schema declaration order. Not configurable.

---

## Decisions (resolved)

- **Scalar step default title**: humanized input name (e.g. `MedicalRecordInput` → `"Medical Record"`)
- **Validation on "Next"**: validate AND read — blocks navigation if invalid or unreadable
  - Sub-input step: `try _${name}Key.currentState!.read() catch InputReadException → block`
  - Scalar step: `_formKey.currentState?.validate() → block if false`
  - List-of-input step: always passes
- **List-of-input step**: passive by default (`Text('N items')`); caller must supply a `Values` override for interactive content. Step is always generated regardless. If a `Values` override is present, its `read()` is called on Next and blocks if it throws.
- **`StepperType`**: exposed as a param, default `StepperType.vertical`
- **Navigation**: linear — must pass current step before proceeding

---

## Layout enum

`stepper` is added to the existing layout enum:

```dart
enum AddPatientInputLayout { column, twoColumn, stepper }
```

---

## Companion class — `${Input}StepConfig`

Generated when the input has at least one sub-input field.
One slot per step bucket, in declaration order.

```dart
class MedicalRecordInputStepConfig {
  final InputStepOptions? scalarFields;    // implicit scalar step (omitted if no scalar fields)
  final InputStepOptions? deseaseHistory;  // sub-input step
  final InputStepOptions? pathologies;     // list-of-input step
  final InputStepOptions? techniques;
  const MedicalRecordInputStepConfig({
    this.scalarFields,
    this.deseaseHistory,
    this.pathologies,
    this.techniques,
  });
}
```

Added to the form widget as `final ${inputName}StepConfig? stepConfig;`.

---

## Shared once-generated class — `InputStepOptions`

```dart
class InputStepOptions {
  final Widget? title;      // overrides auto-humanized default
  final Widget? subtitle;
  final bool isSkippable;   // bypasses validate+read check on Next
  const InputStepOptions({
    this.title,
    this.subtitle,
    this.isSkippable = false,
  });
}
```

---

## Widget class additions

```dart
final ${inputName}StepConfig? stepConfig;  // only generated when sub-inputs exist
final StepperType stepperType;
```

Constructor params:
```dart
this.stepConfig,
this.stepperType = StepperType.vertical,
```

---

## State additions

```dart
int _currentStep = 0;
```

---

## Architectural note — `Form` wrapper

**Current**: `build()` always returns `Form(key: _formKey, child: child)` wrapping everything.

**Stepper change**: `Form(key: _formKey)` must wrap only the scalar step's content —
NOT the whole `Stepper`. Sub-input steps have their own internal `Form` via `${SubType}Form`.

```
// Column layout (unchanged):
Form(key: _formKey, child: Column(...))

// Stepper layout:
Stepper(
  steps: [
    Step(content: Form(key: _formKey, child: Column(children: _scalarRows()))),  // scalar step
    Step(content: DeseaseHistoryInputForm(key: _deseaseHistoryKey, ...)),         // sub-input step
    Step(content: Text('${_pathologies.length} items')),                          // list-of-input step
  ],
)
```

Flutter's `Stepper` builds all steps eagerly, so all `Form` widgets are mounted
and their keys are valid when `_onStepContinue` fires.

---

## Build method — stepper case

```dart
case ${inputName}Layout.stepper:
  return Stepper(
    type: _form.stepperType,
    currentStep: _currentStep,
    onStepContinue: _onStepContinue,
    onStepCancel: _onStepCancel,
    onStepTapped: (i) => setState(() => _currentStep = i),
    steps: _buildSteps(),
  );
```

Note: stepper returns directly — no outer `Form` wrapper.
All other layouts keep the existing `Form(key: _formKey, child: child)` return.

---

## `_scalarRows()` — new helper

Returns only the scalar / enum / bool / plain-list field rows.
Used by the scalar step in stepper layout.
Reuses the same widget expressions as `_visibleRows()` but filtered to
non-sub-input, non-list-of-input fields.

`_visibleRows()` remains unchanged for column/twoColumn layouts.

---

## `_buildSteps()` — generated per input

```dart
List<Step> _buildSteps() {
  final steps = <Step>[];

  // Scalar fields step (if any exist)
  steps.add(Step(
    title: _form.stepConfig?.scalarFields?.title
        ?? const Text('Medical Record'),  // humanized input name
    subtitle: _form.stepConfig?.scalarFields?.subtitle,
    isActive: _currentStep >= 0,
    content: Form(key: _formKey, child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _intersperse(_scalarRows(), _form.gap),
    )),
  ));

  // Sub-input step
  steps.add(Step(
    title: _form.stepConfig?.deseaseHistory?.title
        ?? const Text('Desease History'),
    subtitle: _form.stepConfig?.deseaseHistory?.subtitle,
    isActive: _currentStep >= 1,
    content: DeseaseHistoryInputForm(
      key: _deseaseHistoryKey,
      strings: _form.strings,
      initialValues: _form.initialValues?.deseaseHistory,
    ),
  ));

  // List-of-input step
  steps.add(Step(
    title: _form.stepConfig?.pathologies?.title
        ?? const Text('Pathologies'),
    subtitle: _form.stepConfig?.pathologies?.subtitle,
    isActive: _currentStep >= 2,
    content: _form.values?.pathologies?.call(_pathologiesOverrideKey)
        ?? Text('${_pathologies.length} items'),
  ));

  return steps;
}
```

---

## Navigation — `_onStepContinue` and `_onStepCancel`

```dart
void _onStepContinue() {
  if (_form.stepConfig?.[currentStepField]?.isSkippable ?? false) {
    if (_currentStep < _totalSteps - 1) setState(() => _currentStep++);
    return;
  }
  if (_validateAndReadCurrentStep()) {
    if (_currentStep < _totalSteps - 1) setState(() => _currentStep++);
  }
}

void _onStepCancel() {
  if (_currentStep > 0) setState(() => _currentStep--);
}
```

---

## `_validateAndReadCurrentStep()` — generated as switch on step index

```dart
bool _validateAndReadCurrentStep() {
  switch (_currentStep) {
    case 0: // scalar step
      return _formKey.currentState?.validate() ?? false;
    case 1: // deseaseHistory sub-input step
      try { _deseaseHistoryKey.currentState!.read(); return true; }
      on InputReadException { return false; }
    case 2: // pathologies list-of-input step
      if (_form.values?.pathologies != null) {
        try { _pathologiesOverrideKey.currentState!.read(); return true; }
        on InputReadException { return false; }
      }
      return true; // no override — bare state, nothing to validate
    default:
      return true;
  }
}
```

---

## `read()` and `validate()` — unchanged

`read()` delegates to `validate()` which validates ALL forms regardless of
`_currentStep`. The stepper's per-step validation is additive UX.

`isSkippable` only affects "can the user tap Next without reading this step" —
it does NOT bypass the final `read()`.

---

## Key files to touch

| File | Change |
|---|---|
| `flutter_inputs_state_serializer.dart` | Stepper build case, `_buildSteps`, `_scalarRows`, `_onStepContinue`, `_onStepCancel`, `_validateAndReadCurrentStep`, `_currentStep` state var, `Form` wrapper split |
| `flutter_inputs_companion_serializer.dart` | `serializeStepConfigClass` |
| `flutter_inputs_shared_serializer.dart` | `serializeSharedInputStepOptions` |
| `flutter_inputs_serializer.dart` | Wire step config, `stepperType` param |
| `flutter_inputs_type_helpers.dart` | Step bucket classification helpers if needed |
