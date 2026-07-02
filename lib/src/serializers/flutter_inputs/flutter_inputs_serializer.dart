import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
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
  final String importPrefix;

  late final _u = DartCodeGenUtils();
  late final _types = FlutterInputsTypeHelpers(_parser, _dartSerializer, _config);
  late final _shared = FlutterInputsSharedSerializer(_config);
  late final _companions = FlutterInputsCompanionSerializer(_u, _types);
  late final _fields = FlutterInputsFieldSerializer(_u, _config, _types);
  late final _date = FlutterInputsDateSerializer(_u, _config, _types, _fields);
  late final _state = FlutterInputsStateSerializer(_u, _config, _types, _fields, _date);

  FlutterInputsSerializer(this._parser, this._dartSerializer, this._config, this.importPrefix);

  // ── File names ────────────────────────────────────────────────────────────────

  bool shouldSkip(GLInputDefinition def) =>
      _config.inputsToSkip.contains(def.token) ||
      gl_utils.shouldSkip(def, CodeGenerationMode.client);

  String getFormFileNameFor(GLInputDefinition def) =>
      '${def.codeName.toSnakeCase()}_form.dart';

  // ── Shared files (delegated) ──────────────────────────────────────────────────

  String serializeSharedInputFormWidget() =>
      _shared.serializeSharedInputFormWidget();

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
  String serializeSharedInputStepOptions() => _shared.serializeSharedInputStepOptions();
  String serializeSharedStepperStrings() => _shared.serializeSharedStepperStrings();
  String serializeSharedInputStepGroup() => _shared.serializeSharedInputStepGroup();
  String serializeSharedSelectFieldConfig() => _shared.serializeSharedSelectFieldConfig();

  // ── Agent header ─────────────────────────────────────────────────────────────

  String _serializeAgentHeader(
    String inputName,
    List<GLField> fields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
    List<GLField> inputListFields,
    List<GLField> dateEligibleFields,
    bool hasSubInputs,
  ) {
    final sep = '// ${'=' * 77}';
    final buf = StringBuffer();

    buf.writeln(sep);
    buf.writeln('// AGENT GUIDE — ${inputName}Form');
    buf.writeln(sep);
    buf.writeln('// Widget:  ${inputName}Form(key: _key, ...)');
    buf.writeln('// State:   GlobalKey<${inputName}FormState>');
    buf.writeln('//');

    // ── Fields ─────────────────────────────────────────────────────────────────
    buf.writeln('// FIELDS (schema order):');
    final pad = fields.map((f) => f.name.token.length).fold<int>(0, (a, b) => a > b ? a : b) + 2;
    for (final f in fields) {
      final name = f.name.token.padRight(pad);
      final String typeDesc;
      if (_types.isInputField(f)) {
        final base = f.type.firstType.token;
        typeDesc = f.type.nullable ? '$base?  (nested input)' : '$base  (nested input)';
      } else if (_types.isInputListField(f)) {
        typeDesc = 'List<${f.type.inlineType.firstType.token}>  (input list)';
      } else if (_types.isEnumListField(f)) {
        final t = f.type.inlineType.firstType.token;
        typeDesc = 'List<$t>  (enum list)  → DropdownLabels.$name';
      } else if (_types.isScalarListField(f)) {
        typeDesc = '${_types.listDartType(f)}  (scalar list)  → ${f.name}Options param';
      } else if (_types.isEnumField(f)) {
        final base = f.type.firstType.token;
        final q = f.type.nullable ? '?' : '';
        typeDesc = '$base$q  (enum)  → Widgets: SelectWidget.{dropdown,chips,radio}';
      } else if (_types.isBoolField(f)) {
        final t = _types.boolStateType(f);
        typeDesc = '$t  (bool)  → Widgets: BoolFieldWidget.{chips,radio}';
      } else {
        final base = _types.dartScalarType(f);
        final q = f.type.nullable ? '?' : '';
        typeDesc = '$base$q';
      }
      buf.writeln('//   $name$typeDesc');
    }

    // ── State API ──────────────────────────────────────────────────────────────
    buf.writeln('//');
    buf.writeln('// STATE API:');
    buf.writeln('//   read()                  → $inputName   throws InputReadException on failure');
    buf.writeln('//   tryRead()               → $inputName?  never throws');
    buf.writeln('//   validate()              → bool');
    buf.writeln("//   reset({List<String>?})  restore all fields (or named subset) to initialValues");
    buf.writeln('//   isDirty                 → bool');
    buf.writeln('//   setSubmitting(bool)     disables / re-enables all fields');
    buf.writeln('//   scrollToField(String)   programmatically scroll to a named field');
    buf.writeln('//   errorsNotifier          ValueNotifier<Map<String,String>>');

    // ── Companion classes ──────────────────────────────────────────────────────
    buf.writeln('//');
    buf.writeln('// COMPANION CLASSES (all optional, passed to the constructor):');
    buf.writeln('//   ${inputName}Labels         per-field label widgets + info-dialog tooltips');
    buf.writeln('//   ${inputName}Values         replace any field with a custom InputFormWidget<T>');
    buf.writeln('//   ${inputName}Visibility     FieldVisibility callbacks (enabled / disabled / hidden)');
    buf.writeln('//   ${inputName}Defaults       default values for hidden fields');
    buf.writeln('//   ${inputName}Validations    async-capable per-field validators');
    buf.writeln('//   ${inputName}Order          render-order overrides');

    final enumListFields = listFields.where(_types.isEnumListField).toList();
    if (enumFields.isNotEmpty || boolFields.isNotEmpty || enumListFields.isNotEmpty) {
      buf.writeln('//   ${inputName}DropdownLabels label overrides for enum / bool / list-of-enum options');
    }
    if (enumFields.isNotEmpty || boolFields.isNotEmpty) {
      buf.writeln('//   ${inputName}Widgets        per-field widget style (dropdown / chips / radio); .{field}Avatar for chip avatars');
    }
    if (textFields.isNotEmpty) {
      buf.writeln('//   ${inputName}TextConfig     TextFieldOptions per text/scalar field (includes .prefixIcon/.suffixIcon)');
      buf.writeln('//   ${inputName}SelectConfig   turn any text/int/float field into a pick-one widget');
    }
    if (textFields.isNotEmpty || enumFields.isNotEmpty) {
      buf.writeln('//   ${inputName}FieldIcons     prefixIcon per text/dropdown field (wins over TextFieldOptions.prefixIcon)');
    }
    if (dateEligibleFields.isNotEmpty) {
      buf.writeln('//   ${inputName}DateConfig     make int/string fields into date pickers');
    }
    if (hasSubInputs) {
      buf.writeln('//   ${inputName}StepConfig     per-step title/subtitle for stepper layout');
    }

    // ── Layout ─────────────────────────────────────────────────────────────────
    buf.writeln('//');
    buf.writeln('// LAYOUT:');
    final layouts = hasSubInputs ? '{column, twoColumn, stepper}' : '{column, twoColumn}';
    buf.writeln('//   layout        → ${inputName}Layout.$layouts');
    buf.writeln('//   labelPosition → ${inputName}LabelPosition.{beside, above, floatingLabel}');

    // ── Error summary ──────────────────────────────────────────────────────────
    buf.writeln('//');
    buf.writeln('// ERROR SUMMARY WIDGET: ${inputName}ErrorSummary(formKey: _key)');
    buf.writeln(sep);
    buf.writeln();

    return buf.toString();
  }

  // ── Per-input entry point ─────────────────────────────────────────────────────

  String serializeInputForm(GLInputDefinition def) {
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
    final hasSubInputs = inputFields.isNotEmpty || inputListFields.isNotEmpty;
    final hasScalarFields = fields.any((f) => !_types.isInputField(f) && !_types.isInputListField(f));

    final header = _serializeAgentHeader(inputName, fields, textFields, enumFields, boolFields,
        listFields, inputFields, inputListFields, dateEligibleFields, hasSubInputs);

    final enumTokens = <GLToken>{
      for (final f in fields)
        if (!f.type.isList && _parser.enums.containsKey(f.type.firstType.token))
          _parser.enums[f.type.firstType.token]!,
      for (final f in fields)
        if (f.type.isList && _parser.enums.containsKey(f.type.inlineType.firstType.token))
          _parser.enums[f.type.inlineType.firstType.token]!,
    };
    final nestedInputTokens = <GLToken>{
      for (final f in inputFields)
        if (_parser.inputs[f.type.firstType.token] != null) _parser.inputs[f.type.firstType.token]!,
      for (final f in inputListFields)
        if (_parser.inputs[f.type.inlineType.firstType.token] != null) _parser.inputs[f.type.inlineType.firstType.token]!,
    };
    final importDeps = <GLToken>[def, ...enumTokens, ...nestedInputTokens];

    final imports = <String>{
      'dart:async',
      'package:flutter/material.dart',
      '$importPrefix/widgets/inputs/input_form_widget.dart',
      '$importPrefix/widgets/inputs/input_read_exception.dart',
      for (final f in fields)
        if (!f.type.isList && _parser.enums.containsKey(f.type.firstType.token))
          '$importPrefix/widgets/enums/${_parser.enums[f.type.firstType.token]!.codeName.toSnakeCase()}_labels.dart',
      for (final f in fields)
        if (f.type.isList && _parser.enums.containsKey(f.type.inlineType.firstType.token))
          '$importPrefix/widgets/enums/${_parser.enums[f.type.inlineType.firstType.token]!.codeName.toSnakeCase()}_labels.dart',
      if (boolFields.isNotEmpty) '$importPrefix/widgets/inputs/boolean_labels.dart',
      if (enumFields.isNotEmpty || boolFields.isNotEmpty || textFields.isNotEmpty) '$importPrefix/widgets/inputs/field_widgets.dart',
      if (textFields.isNotEmpty) '$importPrefix/widgets/inputs/text_field_options.dart',
      if (textFields.isNotEmpty) '$importPrefix/widgets/inputs/select_field_config.dart',
      if (dateEligibleFields.isNotEmpty) ...{
        'package:flutter/cupertino.dart',
        'package:intl/intl.dart',
        '$importPrefix/widgets/inputs/date_input_config.dart',
        '$importPrefix/widgets/inputs/date_input_formatter.dart',
      },
      '$importPrefix/widgets/inputs/field_visibility.dart',
      '$importPrefix/widgets/inputs/required_indicator.dart',
      '$importPrefix/widgets/inputs/form_strings.dart',
      for (final f in inputFields)
        '$importPrefix/widgets/inputs/${(_parser.inputs[f.type.firstType.token]?.codeName ?? f.type.firstType.token).toSnakeCase()}_form.dart',
      if (hasSubInputs) '$importPrefix/widgets/inputs/input_step_options.dart',
      if (hasSubInputs) '$importPrefix/widgets/inputs/stepper_strings.dart',
    };

    final buffer = StringBuffer();
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
    if (textFields.isNotEmpty) {
      buffer.writeln(_companions.serializeSelectConfigClass(inputName, textFields));
      buffer.writeln();
      buffer.writeln(_companions.serializeFocusNodesClass(inputName, textFields));
      buffer.writeln();
    }
    if (textFields.isNotEmpty || enumFields.isNotEmpty) {
      final fieldIcons = _companions.serializeFieldIconsClass(inputName, textFields, enumFields);
      if (fieldIcons.isNotEmpty) {
        buffer.writeln(fieldIcons);
        buffer.writeln();
      }
    }
    if (hasSubInputs) {
      buffer.writeln(_companions.serializeStepConfigClass(inputName, hasScalarFields, inputFields, inputListFields));
      buffer.writeln();
    }
    buffer.writeln('enum ${inputName}Layout { column, twoColumn${hasSubInputs ? ', stepper' : ''} }');
    buffer.writeln();
    buffer.writeln('enum ${inputName}LabelPosition { beside, above, floatingLabel }');
    buffer.writeln();
    buffer.writeln(_state.serializeWidgetClass(inputName, listFields, formFields, enumFields, boolFields, textFields, dateEligibleFields, inputFields, inputListFields));
    buffer.writeln();
    buffer.write(_state.serializeStateClass(inputName, fields, listFields, textFields, enumFields, boolFields, intFields, dateEligibleFields, inputFields));
    buffer.writeln();
    buffer.writeln(_state.serializeErrorSummaryClass(inputName, fields, textFields, enumFields, boolFields));

    final file = _dartSerializer.serializeGlClass(GLClassModel(
      imports: imports.toList(),
      importDepencies: importDeps,
      body: buffer.toString(),
    ));

    return '$header$file';
  }
}
