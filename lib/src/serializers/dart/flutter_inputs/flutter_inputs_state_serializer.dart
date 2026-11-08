import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_date_serializer.dart';
import 'flutter_inputs_draft_serializer.dart';
import 'flutter_inputs_field_serializer.dart';
import 'flutter_inputs_error_summary_serializer.dart';
import 'flutter_inputs_layout_helpers_serializer.dart';
import 'flutter_inputs_reset_serializer.dart';
import 'flutter_inputs_read_serializer.dart';
import 'flutter_inputs_rows_serializer.dart';
import 'flutter_inputs_change_serializer.dart';
import 'flutter_inputs_stepper_serializer.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsStateSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterInputsTypeHelpers _types;
  final FlutterInputsFieldSerializer _fields;
  final FlutterInputsDateSerializer _date;
  final FlutterInputsDraftSerializer _drafts;

  late final _reset = FlutterInputsResetSerializer(_u, _config, _types);
  late final _read = FlutterInputsReadSerializer(_u, _config, _types);
  late final _rows = FlutterInputsRowsSerializer(_u, _config, _types, _fields, _drafts);
  late final _change = FlutterInputsChangeSerializer(_u, _config);
  late final _layout = FlutterInputsLayoutHelpersSerializer(_u, _config, _types);
  late final _stepper = FlutterInputsStepperSerializer(_u, _config, _types, _drafts);
  late final _errors = FlutterInputsErrorSummarySerializer(_u, _types);

  FlutterInputsStateSerializer(this._u, this._config, this._types, this._fields, this._date, this._drafts);


  // ── State class ───────────────────────────────────────────────────────────────

  String serializeStateClass(
    String inputName,
    List<GLField> fields,
    List<GLField> listFields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> intFields,
    List<GLField> dateEligibleFields,
    List<GLField> inputFields,
  ) {
    final formName = '${inputName}Form';
    final stateName = '${inputName}FormState';
    final passwordFields = textFields.where(_types.isPasswordField).toList();
    final inputListFields = listFields.where(_types.isInputListField).toList();

    final hasSubInputs = inputFields.isNotEmpty || inputListFields.isNotEmpty;
    final hasScalarFields = fields.any((f) => !_types.isInputField(f) && !_types.isInputListField(f));

    // Build ordered step buckets: scalar step first, then sub-inputs and
    // list-of-inputs interleaved in schema declaration order.
    final stepBuckets = _stepper.buildStepBuckets(fields, hasScalarFields, inputFields, inputListFields);

    final validatableFields = [...textFields, ...enumFields, ...boolFields];

    final stateVarDecls = <String>[
      _u.constDecl('_formKey', 'GlobalKey<FormState>()'),
      '${formName} get _form => widget as ${formName};',
      'Timer? _debounceTimer;',
      'bool _isResetting = false;',
      'bool _submitting = false;',
      'bool _asyncNotifying = false;',
      _u.constDecl('_errorsNotifier', 'ValueNotifier<Map<String, String>>({})'),
      if (validatableFields.isNotEmpty) '// async validation state',
      ...validatableFields.map((f) => 'bool _${f.codeName}Validating = false;'),
      ...validatableFields.map((f) => 'String? _${f.codeName}AsyncError;'),
      ...validatableFields.map((f) => 'Timer? _${f.codeName}AsyncTimer;'),
      if (_config.persistDrafts) ...FlutterInputsDraftSerializer.stateVarDecls,
      if (hasSubInputs) 'int _currentStep = 0;',
      if (textFields.isNotEmpty) '// text controllers',
      ...textFields.map((f) => 'late final TextEditingController _${f.codeName}Controller;'),
      if (passwordFields.isNotEmpty) '// password visibility state',
      ...passwordFields.map((f) => 'bool _${f.codeName}Obscured = true;'),
      if (enumFields.isNotEmpty) '// enum state',
      ...enumFields.map((f) => '${_types.resolveTypeCodeName(f.type.firstType.token)}? _${f.codeName};'),
      if (boolFields.isNotEmpty) '// boolean state',
      ...boolFields.map((f) => '${_types.boolStateType(f)} _${f.codeName}${_types.boolStateInit(f)};'),
      if (listFields.isNotEmpty) '// list state',
      ...listFields.map((f) {
        if (_types.isEnumListField(f) || _types.isScalarListField(f)) {
          return 'late List<${_types.listItemTypeNonNull(f)}> _${f.codeName};';
        }
        return f.type.nullable
            ? '${_types.listDartType(f)} _${f.codeName};'
            : 'late ${_types.listDartType(f)} _${f.codeName};';
      }),
      if (dateEligibleFields.isNotEmpty) '// inline calendar open state',
      ...dateEligibleFields.map((f) => 'bool _${f.codeName}CalendarOpen = false;'),
      if (inputFields.isNotEmpty) '// nested input keys',
      ...inputFields.map((f) => _u.constDecl('_${f.codeName}Key', 'GlobalKey<InputFormState<${_types.resolveTypeCodeName(f.type.firstType.token)}>>()')),
      '// field keys — used by _scrollToFirstError to locate first invalid field',
      ...fields.where((f) => textFields.contains(f) || enumFields.contains(f) || boolFields.contains(f))
          .map((f) => _u.constDecl('_${f.codeName}FieldKey', 'GlobalKey<FormFieldState>()')),
      '// field override keys',
      ...fields.where((f) => !_types.isInputField(f)).map((f) =>
          _u.constDecl('_${f.codeName}OverrideKey', 'GlobalKey<InputFormState<${_types.valuesFieldType(f)}>>()')),
    ];

    final initStatements = <String>[
      'super.initState();',
      if (_config.persistDrafts) _drafts.initStatement(),
      ...textFields.map((f) => '_${f.codeName}Controller = TextEditingController(text: ${_types.initialTextExpr(f)});'),
      ...enumFields.map((f) => '_${f.codeName} = _form.initialValues?.${f.codeName};'),
      ...boolFields.map((f) => '_${f.codeName} = ${_types.initialBoolExpr(f)};'),
      ...listFields.map((f) {
        if (_types.isEnumListField(f) || _types.isScalarListField(f)) {
          return '_${f.codeName} = List.of(_form.${f.codeName});';
        }
        return f.type.nullable
            ? '_${f.codeName} = _form.${f.codeName} != null ? List.of(_form.${f.codeName}!) : null;'
            : '_${f.codeName} = List.of(_form.${f.codeName});';
      }),
    ];

    final didUpdateStatements = <String>[
      'super.didUpdateWidget(oldWidget);',
      if (listFields.isNotEmpty) _u.constDecl('oldForm', 'oldWidget as ${formName}'),
      ...listFields.map((f) {
        if (_types.isEnumListField(f) || _types.isScalarListField(f)) {
          return _u.inlineIfStatement(
            condition: '_form.${f.codeName} != oldForm.${f.codeName}',
            statement: '_${f.codeName} = List.of(_form.${f.codeName});',
          );
        }
        return f.type.nullable
            ? _u.inlineIfStatement(
                condition: '_form.${f.codeName} != oldForm.${f.codeName}',
                statement: '_${f.codeName} = _form.${f.codeName} != null ? List.of(_form.${f.codeName}!) : null;',
              )
            : _u.inlineIfStatement(
                condition: '_form.${f.codeName} != oldForm.${f.codeName}',
                statement: '_${f.codeName} = List.of(_form.${f.codeName});',
              );
      }),
    ];

    final disposeStatements = <String>[
      '_debounceTimer?.cancel();',
      if (_config.persistDrafts) ...FlutterInputsDraftSerializer.disposeStatements,
      ...validatableFields.map((f) => '_${f.codeName}AsyncTimer?.cancel();'),
      '_errorsNotifier.dispose();',
      ...textFields.map((f) => '_${f.codeName}Controller.dispose();'),
      'super.dispose();',
    ];

    return _u.createClass(
      className: stateName,
      extendsClassName: 'InputFormState<$inputName>',
      statements: [
        ...stateVarDecls,
        _u.createMethod(
            override: true, returnType: 'void', methodName: 'initState',
            arguments: [], namedArguments: false, statements: initStatements),
        _u.createMethod(
            override: true, returnType: 'void', methodName: 'didUpdateWidget',
            namedArguments: false,
            arguments: ['InputFormWidget<$inputName> oldWidget'],
            statements: didUpdateStatements),
        _u.createMethod(
            override: true, returnType: 'void', methodName: 'dispose',
            arguments: [], namedArguments: false, statements: disposeStatements),
        _reset.serializeResetMethod(textFields, enumFields, boolFields, listFields, inputFields, hasSubInputs),
        _reset.serializeIsDirtyGetter(textFields, enumFields, boolFields, listFields, inputFields),
        _errors.serializeScrollToFirstErrorMethod(inputName, fields, textFields, enumFields, boolFields),
        _errors.updateErrorsNotifierMethod(inputName, fields, textFields, enumFields, boolFields),
        _errors.scrollToFieldMethod(inputName, fields, textFields, enumFields, boolFields),
        '@override\nbool get isSubmitting => _submitting;',
        validatableFields.isEmpty
            ? 'bool get _isAsyncValidating => false;'
            : 'bool get _isAsyncValidating => ${validatableFields.map((f) => '_${f.codeName}Validating').join(' || ')};',
        'ValueNotifier<Map<String, String>> get errorsNotifier => _errorsNotifier;',
        _u.createMethod(
          override: true,
          returnType: 'void',
          methodName: 'setSubmitting',
          namedArguments: false,
          arguments: ['bool value'],
          statements: [
            'setState(() => _submitting = value);',
            // propagate to sub-input forms so stepper child forms are also disabled
            ...inputFields.map((f) => '_${f.codeName}Key.currentState?.setSubmitting(value);'),
            // cancel any in-flight async validation when submitting
            ...validatableFields.map((f) => '_${f.codeName}AsyncTimer?.cancel();'),
          ],
        ),
        _serializeBuildMethod(inputName, hasSubInputs),
        _serializeValidateMethod(inputFields),
        _read.serializeBuildResultMethod(inputName, textFields, enumFields, boolFields, listFields, inputFields),
        _read.serializeReadMethod(inputName),
        _read.serializeTryReadMethod(inputName),
        _u.createMethod(
          override: true,
          returnType: 'void',
          methodName: 'setState',
          namedArguments: false,
          arguments: ['VoidCallback fn'],
          statements: [
            'super.setState(fn);',
            _u.inlineIfStatement(condition: '!_isResetting', statement: '_onFieldChanged();'),
          ],
        ),
        if (hasSubInputs) _stepper.serializeBuildStepsMethod(inputName, stepBuckets, hasScalarFields),
        if (hasSubInputs && hasScalarFields) _rows.serializeScalarRowsMethod(inputName, fields, textFields, enumFields, boolFields, listFields),
        if (hasSubInputs) _stepper.serializeValidateAndReadCurrentStepMethod(inputName, stepBuckets),
        if (hasSubInputs) _stepper.serializeOnStepContinueMethod(stepBuckets.length),
        if (hasSubInputs) _stepper.serializeOnStepCancelMethod(),
        if (hasSubInputs) _stepper.serializeBuildStepControlsMethod(stepBuckets.length),
        _rows.serializeVisibleRowsMethod('_visibleRows', inputName, fields, textFields, enumFields, boolFields, listFields, inputFields),
        _rows.buildContextMethod(inputName, fields.where((f) => !_types.isInputField(f)).toList()),
        ...enumFields.map(_fields.enumRowMethod),
        ...boolFields.map(_fields.boolRowMethod),
        ...textFields.map(_date.scalarRowMethod),
        ...inputFields.map(_rows.inputFieldRowMethod),
        _layout.requiredLabelHelper(inputName),
        _layout.labelWithInfoHelper(inputName),
        _layout.withFloatingInfoHelper(inputName),
        _change.onFieldChangedMethod(),
        _change.notifyContextChangeMethod(),
        _change.scheduleOnChangeMethod(),
        _change.scheduleAllAsyncValidationsMethod(validatableFields),
        ..._change.asyncSchedulerMethods(validatableFields, textFields),
        if (_layout.needsFieldHelper(textFields, enumFields, boolFields, inputListFields)) _layout.fieldHelper(inputName),
        if (_types.needsSwitchBoolHelper(boolFields)) _layout.switchBoolFieldHelper(inputName),
        if (_types.needsCheckboxBoolHelper(boolFields)) _layout.checkboxBoolFieldHelper(inputName),
        if (_layout.needsDecorationHelper(textFields, enumFields, boolFields)) _layout.decorationHelper(inputName),
        if (textFields.isNotEmpty) _layout.textDecorationHelper(inputName),
        if (textFields.isNotEmpty) _layout.clearButtonHelper(),
        if (dateEligibleFields.isNotEmpty) _date.clampDateHelper(),
        if (dateEligibleFields.isNotEmpty) _date.isCupertinoHelper(),
        if (dateEligibleFields.isNotEmpty) _date.pickDateHelper(),
        if (dateEligibleFields.isNotEmpty) _date.pickDateMaterialHelper(),
        if (dateEligibleFields.isNotEmpty) _date.pickDateCupertinoHelper(),
        if (intFields.isNotEmpty) _date.parseDateHelper(),
        _layout.intersperseHelper(),
        if (_config.persistDrafts)
          ..._drafts.stateMethods(inputName, fields, textFields, enumFields, boolFields, listFields),
      ],
    );
  }


  String _serializeBuildMethod(String inputName, bool hasSubInputs) {
    final columnReturn = 'return ${_u.callExpression('Form', [
      'key: _formKey',
      'child: ${_u.callExpression('Column', [
        'mainAxisSize: _form.columnMainAxisSize',
        'crossAxisAlignment: CrossAxisAlignment.stretch',
        'children: _intersperse(rows, _form.gap)',
      ])}',
    ])};';

    final twoColumnReturn = 'return ${_u.callExpression('Form', [
      'key: _formKey',
      'child: ${_u.callExpression('LayoutBuilder', [
        'builder: ${_u.functionLiteral(['context', 'constraints'], [
          'final childWidth = (constraints.maxWidth - _form.gap) / 2;',
          'return ${_u.callExpression('Wrap', [
            'spacing: _form.gap',
            'runSpacing: _form.gap',
            'children: rows.map((w) => SizedBox(width: childWidth, child: w)).toList()',
          ])};',
        ])}',
      ])}',
    ])};';

    return _u.createMethod(
      override: true,
      returnType: 'Widget',
      methodName: 'build',
      namedArguments: false,
      arguments: ['BuildContext context'],
      statements: [
        // Schema-derived stepper — sub-input forms drive the steps
        if (hasSubInputs) _u.ifStatement(
          condition: '_form.layout == ${inputName}Layout.stepper',
          ifBlockStatements: [
            'return ${_u.callExpression('Stepper', [
              'type: _form.stepperType',
              'currentStep: _currentStep',
              'onStepContinue: _onStepContinue',
              'onStepCancel: _onStepCancel',
              'onStepTapped: ${_u.functionLiteral(['i'], [
                _u.inlineIfStatement(condition: 'i <= _currentStep', statement: 'setState(() => _currentStep = i);'),
              ])}',
              'controlsBuilder: _form.stepControlsBuilder ?? _buildStepControls',
              'steps: _buildSteps()',
            ])};',
          ],
        ),
        _u.constDecl('rows', '_visibleRows()'),
        _u.ifStatement(
          condition: '_form.layout == ${inputName}Layout.column',
          ifBlockStatements: [columnReturn],
        ),
        twoColumnReturn,
      ],
    );
  }

  String _serializeValidateMethod(List<GLField> inputFields) {
    return _u.createMethod(
      override: true,
      returnType: 'bool',
      methodName: 'validate',
      arguments: [],
      namedArguments: false,
      statements: [
        _u.inlineIfStatement(condition: '_isAsyncValidating', statement: 'return false;'),
        'var valid = _formKey.currentState?.validate() ?? false;',
        // Use &= (non-short-circuit) so every sub-form is validated even if a previous one failed.
        // currentState is null when a sub-form is hidden/unmounted — ?? true treats it as valid.
        ...inputFields.map((f) =>
            'valid &= _${f.codeName}Key.currentState?.validate() ?? true;'),
        '_updateErrorsNotifier();',
        'return valid;',
      ],
    );
  }



  /// Shared field-iteration logic used by both _visibleRows and _visibleRowMap.
  /// [accumulate] receives (field, defaultOrderIdx, widgetExpr) and returns
  /// the accumulation statement string — the only thing that differs between the two.
}
