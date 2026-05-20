import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_ui_entity.dart' show GlInputEntity;
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/utils.dart' as gl_utils;
import 'flutter_inputs_companion_serializer.dart';
import 'flutter_inputs_date_serializer.dart';
import 'flutter_inputs_field_serializer.dart';
import 'flutter_inputs_shared_serializer.dart';
import 'flutter_inputs_state_serializer.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsSerializer {
  final GLParser _parser;
  final DartSerializer _dartSerializer;
  final FlutterConfig _config;

  late final _u = DartCodeGenUtils();
  late final _types = FlutterInputsTypeHelpers(_parser, _dartSerializer, _config);
  late final _shared = const FlutterInputsSharedSerializer();
  late final _companions = FlutterInputsCompanionSerializer(_u, _types);
  late final _fields = FlutterInputsFieldSerializer(_u, _config, _types);
  late final _date = FlutterInputsDateSerializer(_u, _types, _fields);
  late final _state = FlutterInputsStateSerializer(_u, _types, _fields, _date);

  FlutterInputsSerializer(this._parser, this._dartSerializer, this._config);

  // ── File names ────────────────────────────────────────────────────────────────

  bool shouldSkip(GLInputDefinition def) =>
      _config.inputsToSkip.contains(def.token) ||
      gl_utils.shouldSkip(def, CodeGenerationMode.client);

  String getFormFileNameFor(GLInputDefinition def) =>
      '${def.token.toSnakeCase()}_form.dart';

  // ── Shared files (delegated) ──────────────────────────────────────────────────

  String serializeSharedInputFormWidget(String importPrefix) =>
      _shared.serializeSharedInputFormWidget(importPrefix);

  String serializeSharedInputReadException() => _shared.serializeSharedInputReadException();
  String serializeSharedFieldWidgets() => _shared.serializeSharedFieldWidgets();
  String serializeSharedRequiredIndicator() => _shared.serializeSharedRequiredIndicator();
  String serializeSharedTextFieldOptions() => _shared.serializeSharedTextFieldOptions();
  String serializeSharedFormStrings() => _shared.serializeSharedFormStrings();
  String serializeSharedDateInputConfig() => _shared.serializeSharedDateInputConfig();
  String serializeSharedDateInputFormatter() => _shared.serializeSharedDateInputFormatter();
  String serializeSharedBooleanLabels() => _shared.serializeSharedBooleanLabels();
  String serializeSharedFieldVisibility() => _shared.serializeSharedFieldVisibility();
  String serializeSharedSimpleFieldForm() => _shared.serializeSharedSimpleFieldForm();

  // ── Per-input entry point ─────────────────────────────────────────────────────

  String serializeInputForm(GLInputDefinition def, String importPrefix) {
    if (shouldSkip(def)) return '';

    final entity = GlInputEntity(def, _parser);
    final inputName = entity.name;
    final fields = entity.fields;

    final listFields = fields.where(_types.isListField).toList();
    final enumFields = fields.where(_types.isEnumField).toList();
    final boolFields = fields.where(_types.isBoolField).toList();
    final textFields = fields.where(_types.isTextField).toList();
    final intFields = textFields.where((f) => _types.dartScalarType(f) == 'int').toList();
    final stringDateFields = textFields.where((f) => _types.dartScalarType(f) == 'String').toList();
    final dateEligibleFields = [...intFields, ...stringDateFields];
    final inputFields = fields.where(_types.isInputField).toList();
    final inputListFields = listFields.where(_types.isInputListField).toList();
    final formFields = [...textFields, ...enumFields, ...boolFields, ...inputFields];
    final enumListFields = listFields.where(_types.isEnumListField).toList();

    final buffer = StringBuffer();

    final imports = <String>{
      "import 'package:flutter/material.dart';",
      "import '$importPrefix/inputs/${inputName.toSnakeCase()}.dart';",
      "import '$importPrefix/widgets/inputs/input_form_widget.dart';",
      "import '$importPrefix/widgets/inputs/input_read_exception.dart';",
      ...entity.enumDataImports(importPrefix),
      ...entity.enumLabelImports(importPrefix),
      if (boolFields.isNotEmpty) "import '$importPrefix/widgets/inputs/boolean_labels.dart';",
      if (enumFields.isNotEmpty || boolFields.isNotEmpty) "import '$importPrefix/widgets/inputs/field_widgets.dart';",
      if (textFields.isNotEmpty) "import '$importPrefix/widgets/inputs/text_field_options.dart';",
      if (dateEligibleFields.isNotEmpty) ...{
        "import 'package:flutter/cupertino.dart';",
        "import 'package:intl/intl.dart';",
        "import '$importPrefix/widgets/inputs/date_input_config.dart';",
        "import '$importPrefix/widgets/inputs/date_input_formatter.dart';",
      },
      "import '$importPrefix/widgets/inputs/field_visibility.dart';",
      "import '$importPrefix/widgets/inputs/required_indicator.dart';",
      "import '$importPrefix/widgets/inputs/form_strings.dart';",
      for (final f in inputFields) ...{
        "import '$importPrefix/inputs/${f.type.firstType.token.toSnakeCase()}.dart';",
        "import '$importPrefix/widgets/inputs/${f.type.firstType.token.toSnakeCase()}_form.dart';",
      },
      for (final f in inputListFields)
        "import '$importPrefix/inputs/${f.type.inlineType.firstType.token.toSnakeCase()}.dart';",
    };
    for (final imp in imports) { buffer.writeln(imp); }
    buffer.writeln();

    final validatableFields = [...textFields, ...enumFields, ...boolFields];
    final contextFields = fields.where((f) => !_types.isInputField(f)).toList();
    buffer.writeln(_companions.serializeFormContextClass(inputName, contextFields));
    buffer.writeln();
    buffer.writeln(_companions.serializeDropdownLabelsClass(inputName, enumFields, boolFields, enumListFields));
    buffer.writeln();
    buffer.writeln(_companions.serializeLabelsClass(inputName, entity.fields));
    buffer.writeln();
    buffer.writeln(_companions.serializeValuesClass(inputName, entity.fields));
    buffer.writeln();
    buffer.writeln(_companions.serializeVisibilityClass(inputName, entity.fields));
    buffer.writeln();
    buffer.writeln(_companions.serializeDefaultsClass(inputName, formFields));
    buffer.writeln();
    buffer.writeln(_companions.serializeValidationsClass(inputName, validatableFields, enumFields, boolFields));
    buffer.writeln();
    buffer.writeln(_companions.serializeOrderClass(inputName, entity.fields));
    buffer.writeln();
    if (enumFields.isNotEmpty || boolFields.isNotEmpty) {
      buffer.writeln(_companions.serializeWidgetsClass(inputName, enumFields, boolFields));
      buffer.writeln();
    }
    if (textFields.isNotEmpty) {
      buffer.writeln(_companions.serializeTextConfigClass(inputName, textFields));
      buffer.writeln();
    }
    if (dateEligibleFields.isNotEmpty) {
      buffer.writeln(_companions.serializeDateConfigClass(inputName, dateEligibleFields));
      buffer.writeln();
    }
    buffer.writeln('enum ${inputName}Layout { column, twoColumn }');
    buffer.writeln();
    buffer.writeln('enum ${inputName}LabelPosition { beside, above, floatingLabel }');
    buffer.writeln();
    buffer.writeln(_state.serializeWidgetClass(inputName, listFields, formFields, enumFields, boolFields, textFields, dateEligibleFields));
    buffer.writeln();
    buffer.write(_state.serializeStateClass(inputName, fields, listFields, textFields, enumFields, boolFields, intFields, dateEligibleFields, inputFields));

    return buffer.toString();
  }
}
