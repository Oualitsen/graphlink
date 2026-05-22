# Flutter UI Upload Input Fields

## Status: Planned — not started

---

## Overview

Generate file-picker form fields for input fields whose scalar type is annotated with `@glUpload`.
Upload fields can be standalone (`Upload`) or lists (`[Upload!]!`).
Platform targets: Android, iOS, Web (with drag-and-drop), Desktop.

---

## Open questions (resolve before implementing)

1. **Non-nullable single upload** — should `read()` throw `InputReadException` when nothing is picked, or should the validator handle it?
2. **List upload initial values** — passed as constructor param like other list fields?
3. **`initialValues` for upload fields** — `XFile` cannot roundtrip from a URL; skip pre-population or accept a separate path/URL string?
4. **Drag-and-drop package** — use `desktop_drop` (handles web + desktop) or hand-roll with `dart:html`?

---

## 1. Constraint — relax `checkUploadScalarUsage`

`gl_grammar_upload_extension.dart` currently throws if `@glUpload` appears in input fields.
This restriction is for the network-layer multipart transport and does not apply to UI generation.
Relax the check to allow `@glUpload` scalars in input fields.
The network serializer is unaffected.

---

## 2. Type mapping

`@glUpload` scalars map to `XFile` from `package:cross_file` (transitive dep of `file_picker`).
Inject dynamically into `typeMap` for scalars that carry `@glUpload` at generator startup,
rather than hard-coding a scalar name in `defaultTypeMap`.

---

## 3. Detection — `FlutterInputsTypeHelpers`

```dart
bool isUploadField(GLField f)      // non-list field whose scalar has @glUpload
bool isUploadListField(GLField f)  // list field  whose inner scalar has @glUpload
```

Upload fields are their own classification bucket — not text, enum, bool, or nested input.

---

## 4. Shared once-generated file — `file_picker_config.dart`

```dart
enum FileSourceType { any, image, video, audio, custom }

class FilePickerConfig {
  final FileSourceType sourceType;
  final List<String>? allowedExtensions; // used when sourceType == custom
  final bool allowCamera;               // mobile only, ignored on web/desktop
  final Widget? placeholder;
  final Widget Function(XFile file)? previewBuilder;
  final Widget Function(XFile file)? chipBuilder; // list fields
  const FilePickerConfig({
    this.sourceType = FileSourceType.any,
    this.allowedExtensions,
    this.allowCamera = true,
    this.placeholder,
    this.previewBuilder,
    this.chipBuilder,
  });
}
```

---

## 5. Companion class — `${Input}FileConfig`

Generated when the input has at least one upload field.

```dart
class AddPatientInputFileConfig {
  final FilePickerConfig? photo;        // single upload field
  final FilePickerConfig? attachments;  // list upload field
  const AddPatientInputFileConfig({this.photo, this.attachments});
}
```

Added to the form widget as `final ${inputName}FileConfig? fileConfig;`.

---

## 6. State variables

```dart
XFile? _photo;                    // nullable single upload
XFile _avatar;                    // non-nullable single upload (late + initialized)
late List<XFile> _attachments;    // list upload, seeded from constructor param
```

---

## 7. Widget — platform strategy

| Platform      | Tap to pick              | Drag & drop                        |
|---------------|--------------------------|------------------------------------|
| Android / iOS | `file_picker` (sheet)    | No                                 |
| Web           | `file_picker` (HTML)     | Yes — `DragTarget` + `dart:html`   |
| Desktop       | `file_picker` (dialog)   | Yes — `desktop_drop` package       |

`kIsWeb` and `Platform.isAndroid/isIOS` used to branch.
A `_wrapWithDragDrop(widget, fieldName)` helper is generated into the state class;
it is a no-op on mobile.

---

## 8. Generated row method — `_photoUploadRow(Widget label, bool enabled)`

**Single field:**
```dart
Column(children: [
  label,
  _wrapWithDragDrop(
    InkWell(
      onTap: enabled ? () => _pickFile('photo', config) : null,
      child: _photo == null
          ? config.placeholder ?? const Icon(Icons.upload_file)
          : config.previewBuilder?.call(_photo!) ?? Text(_photo!.name),
    ),
    'photo',
  ),
  if (_photo != null)
    IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _photo = null)),
])
```

**List field:** chips per picked file + "Add" button.

---

## 9. `_pickFile` helper (generated into state)

```dart
Future<void> _pickFile(String fieldName, FilePickerConfig config, bool multiple) async {
  final result = await FilePicker.platform.pickFiles(
    type: _toFileType(config.sourceType),
    allowedExtensions: config.allowedExtensions,
    allowMultiple: multiple,
    withData: kIsWeb,
  );
  if (result == null || !mounted) return;
  setState(() { /* assign XFile(s) to the right field */ });
}
```

---

## 10. `read()` integration

- Upload fields are excluded from `validate()` — no text validators
- `_buildResult()` reads directly from state: `photo: _photo`
- Non-nullable with null state → `throw InputReadException('photo: no file selected')`
- List upload: always reads from `_attachments` state (no `hiddenDefaults`)

---

## 11. Generated imports

When upload fields are present the generated form file gets:

```dart
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
// web drag-drop only:
import 'dart:html' as html; // ignore: avoid_web_libraries_in_flutter
```

---

## Key files to touch

| File | Change |
|---|---|
| `gl_grammar_upload_extension.dart` | Relax `checkUploadScalarUsage` for input fields |
| `gl_serializer.dart` | Inject `XFile` into `typeMap` for `@glUpload` scalars at init |
| `flutter_inputs_type_helpers.dart` | Add `isUploadField`, `isUploadListField` |
| `flutter_inputs_companion_serializer.dart` | Add `serializeFileConfigClass` |
| `flutter_inputs_field_serializer.dart` | Add upload row method |
| `flutter_inputs_state_serializer.dart` | State vars, `_pickFile`, `_wrapWithDragDrop`, `read()` integration |
| `flutter_inputs_shared_serializer.dart` | Add `serializeSharedFilePickerConfig` |
| `flutter_inputs_serializer.dart` | Wire up upload fields, imports |
