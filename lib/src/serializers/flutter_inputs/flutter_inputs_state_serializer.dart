import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_date_serializer.dart';
import 'flutter_inputs_field_serializer.dart';
import 'flutter_inputs_type_helpers.dart';

enum _StepType { scalar, subInput, inputList }

class _StepBucket {
  final int index;
  final _StepType type;
  final GLField? field;
  const _StepBucket(this.index, this.type, this.field);
}

class FlutterInputsStateSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterInputsTypeHelpers _types;
  final FlutterInputsFieldSerializer _fields;
  final FlutterInputsDateSerializer _date;

  FlutterInputsStateSerializer(this._u, this._config, this._types, this._fields, this._date);

  // ── Widget class ──────────────────────────────────────────────────────────────

  String serializeWidgetClass(
      String inputName, List<GLField> listFields, List<GLField> formFields,
      List<GLField> enumFields, List<GLField> boolFields, List<GLField> textFields,
      List<GLField> dateEligibleFields,
      List<GLField> inputFields, List<GLField> inputListFields) {
    final hasSubInputs = inputFields.isNotEmpty || inputListFields.isNotEmpty;
    final gap = _types.gapStr();
    final hasDropdownLabels = enumFields.isNotEmpty || boolFields.isNotEmpty || listFields.any(_types.isEnumListField);

    final listFieldDecls = <String>[];
    final listParams = <String>[];
    for (final f in listFields) {
      if (_types.isEnumListField(f)) {
        listFieldDecls.add('final List<${_types.listItemTypeNonNull(f)}> ${f.codeName};');
        listParams.add('this.${f.codeName} = ${_types.typedEmptyList(f)}');
      } else if (_types.isScalarListField(f)) {
        listFieldDecls.add('final List<${_types.listItemTypeNonNull(f)}> ${f.codeName};');
        listFieldDecls.add('final List<${_types.listItemTypeNonNull(f)}>? ${f.codeName}Options;');
        listParams.add('this.${f.codeName} = ${_types.typedEmptyList(f)}');
        listParams.add('this.${f.codeName}Options');
      } else {
        listFieldDecls.add('final ${_types.listDartType(f)} ${f.codeName};');
        listParams.add(f.type.nullable ? 'this.${f.codeName}' : 'required this.${f.codeName}');
      }
    }

    return _u.createClass(
      className: '${inputName}Form',
      extendsClassName: 'InputFormWidget<$inputName>',
      statements: [
        ...listFieldDecls,
        'final $inputName? initialValues;',
        if (hasDropdownLabels) 'final ${inputName}DropdownLabels? dropdownLabels;',
        'final ${inputName}Labels? labels;',
        'final ${inputName}Values? values;',
        'final ${inputName}Visibility? visibility;',
        'final ${inputName}Order? order;',
        'final ${inputName}Defaults? hiddenDefaults;',
        'final ${inputName}Validations? validations;',
        if (enumFields.isNotEmpty || boolFields.isNotEmpty) 'final ${inputName}Widgets? widgets;',
        if (textFields.isNotEmpty) 'final ${inputName}TextConfig? textConfig;',
        if (dateEligibleFields.isNotEmpty) 'final ${inputName}DateConfig? dateConfig;',
        if (textFields.isNotEmpty) 'final ${inputName}SelectConfig? selectConfig;',
        if (textFields.isNotEmpty) 'final ${inputName}FocusNodes? focusNodes;',
        if (textFields.isNotEmpty || enumFields.isNotEmpty) 'final ${inputName}FieldIcons? fieldIcons;',
        'final ${inputName}Layout layout;',
        'final ${inputName}LabelPosition labelPosition;',
        'final double labelWidth;',
        'final double gap;',
        'final RequiredIndicator requiredIndicator;',
        'final Widget? requiredLabel;',
        'final Widget? optionalLabel;',
        'final FormStrings strings;',
        'final MainAxisSize columnMainAxisSize;',
        if (hasSubInputs) 'final ${inputName}StepConfig? stepConfig;',
        if (hasSubInputs) 'final StepperType stepperType;',
        if (hasSubInputs) 'final Widget Function(BuildContext, ControlsDetails)? stepControlsBuilder;',
        if (hasSubInputs) 'final MainAxisAlignment stepControlsAlignment;',
        if (hasSubInputs) 'final StepperStrings stepperStrings;',
        '/// Called synchronously on every field change with a live snapshot of all field values.\n'
            '/// Use for instant reactive UI — visibility decisions, computed labels, live summaries.\n'
            'final void Function(${inputName}FormContext)? onContextChange;',
        '/// Called after [debounceDuration] with the result of [tryRead].\n'
            '/// Delivers `null` when the form is not yet parseable (required fields empty,\n'
            '/// invalid format, enum not selected). Delivers `$inputName` when the form\n'
            '/// is complete enough to submit. Note: custom [validations] are NOT run here —\n'
            '/// they only run on [read]. Use [onContextChange] to inspect raw field values\n'
            '/// when the form is incomplete.\n'
            'final void Function($inputName?)? onChange;',
        '/// How long to wait after the last field change before firing [onChange]. Default: 300ms.\n'
            'final Duration debounceDuration;',
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Form',
          namedArguments: true,
          arguments: [
            'super.key',
            'this.initialValues',
            ...listParams,
            if (hasDropdownLabels) 'this.dropdownLabels',
            'this.labels',
            'this.values',
            'this.visibility',
            'this.order',
            'this.hiddenDefaults',
            'this.validations',
            if (enumFields.isNotEmpty || boolFields.isNotEmpty) 'this.widgets',
            if (textFields.isNotEmpty) 'this.textConfig',
            if (dateEligibleFields.isNotEmpty) 'this.dateConfig',
            if (textFields.isNotEmpty) 'this.selectConfig',
            if (textFields.isNotEmpty) 'this.focusNodes',
            if (textFields.isNotEmpty || enumFields.isNotEmpty) 'this.fieldIcons',
            'this.layout = ${inputName}Layout.${_config.defaultFormLayout.name}',
            'this.labelPosition = ${inputName}LabelPosition.${_config.defaultLabelPosition.name}',
            'this.labelWidth = ${_config.defaultLabelWidth % 1 == 0 ? _config.defaultLabelWidth.toInt() : _config.defaultLabelWidth}',
            'this.gap = $gap',
            'this.requiredIndicator = RequiredIndicator.${_config.defaultRequiredIndicator.name}',
            'this.requiredLabel',
            'this.optionalLabel',
            'this.strings = const FormStrings()',
            'this.columnMainAxisSize = MainAxisSize.min',
            if (hasSubInputs) 'this.stepConfig',
            if (hasSubInputs) 'this.stepperType = StepperType.${_config.defaultStepperOrientation.name}',
            if (hasSubInputs) 'this.stepControlsBuilder',
            if (hasSubInputs) 'this.stepControlsAlignment = MainAxisAlignment.spaceBetween',
            if (hasSubInputs) 'this.stepperStrings = const StepperStrings()',
            'this.onContextChange',
            'this.onChange',
            'this.debounceDuration = const Duration(milliseconds: ${_config.defaultDebounceDuration})',
          ],
        ),
        _u.createMethod(
          override: true,
          returnType: 'State<InputFormWidget<$inputName>>',
          methodName: 'createState',
          arguments: [],
          namedArguments: false,
          statements: ['return ${inputName}FormState();'],
        ),
      ],
    );
  }

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
    final stepBuckets = _buildStepBuckets(fields, hasScalarFields, inputFields, inputListFields);

    final validatableFields = [...textFields, ...enumFields, ...boolFields];

    final stateVarDecls = <String>[
      'final _formKey = GlobalKey<FormState>();',
      '${formName} get _form => widget as ${formName};',
      'Timer? _debounceTimer;',
      'bool _isResetting = false;',
      'bool _submitting = false;',
      'bool _asyncNotifying = false;',
      'final _errorsNotifier = ValueNotifier<Map<String, String>>({});',
      if (validatableFields.isNotEmpty) '// async validation state',
      ...validatableFields.map((f) => 'bool _${f.codeName}Validating = false;'),
      ...validatableFields.map((f) => 'String? _${f.codeName}AsyncError;'),
      ...validatableFields.map((f) => 'Timer? _${f.codeName}AsyncTimer;'),
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
      ...inputFields.map((f) => 'final _${f.codeName}Key = GlobalKey<${_types.resolveTypeCodeName(f.type.firstType.token)}FormState>();'),
      '// field keys — used by _scrollToFirstError to locate first invalid field',
      ...fields.where((f) => textFields.contains(f) || enumFields.contains(f) || boolFields.contains(f))
          .map((f) => 'final _${f.codeName}FieldKey = GlobalKey<FormFieldState>();'),
      '// field override keys',
      ...fields.where((f) => !_types.isInputField(f)).map((f) =>
          'final _${f.codeName}OverrideKey = GlobalKey<InputFormState<${_types.valuesFieldType(f)}>>();'),
    ];

    final initStatements = <String>[
      'super.initState();',
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
      'final oldForm = oldWidget as ${formName};',
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
        _serializeResetMethod(textFields, enumFields, boolFields, listFields, inputFields, hasSubInputs),
        _serializeIsDirtyGetter(textFields, enumFields, boolFields, listFields, inputFields),
        _serializeScrollToFirstErrorMethod(inputName, fields, textFields, enumFields, boolFields),
        _updateErrorsNotifierMethod(inputName, fields, textFields, enumFields, boolFields),
        _scrollToFieldMethod(inputName, fields, textFields, enumFields, boolFields),
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
        _serializeBuildResultMethod(inputName, textFields, enumFields, boolFields, listFields, inputFields),
        _serializeReadMethod(inputName),
        _serializeTryReadMethod(inputName),
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
        if (hasSubInputs) _serializeBuildStepsMethod(inputName, stepBuckets, hasScalarFields),
        if (hasSubInputs && hasScalarFields) _serializeScalarRowsMethod(inputName, fields, textFields, enumFields, boolFields, listFields),
        if (hasSubInputs) _serializeValidateAndReadCurrentStepMethod(inputName, stepBuckets),
        if (hasSubInputs) _serializeOnStepContinueMethod(stepBuckets.length),
        if (hasSubInputs) _serializeOnStepCancelMethod(),
        if (hasSubInputs) _serializeBuildStepControlsMethod(stepBuckets.length),
        _serializeVisibleRowsMethod('_visibleRows', inputName, fields, textFields, enumFields, boolFields, listFields, inputFields),
        _buildContextMethod(inputName, fields.where((f) => !_types.isInputField(f)).toList()),
        ...enumFields.map(_fields.enumRowMethod),
        ...boolFields.map(_fields.boolRowMethod),
        ...textFields.map(_date.scalarRowMethod),
        ...inputFields.map(_inputFieldRowMethod),
        _requiredLabelHelper(inputName),
        _labelWithInfoHelper(inputName),
        _withFloatingInfoHelper(inputName),
        _onFieldChangedMethod(),
        _notifyContextChangeMethod(),
        _scheduleOnChangeMethod(),
        _scheduleAllAsyncValidationsMethod(validatableFields),
        ..._asyncSchedulerMethods(validatableFields, textFields),
        if (_needsFieldHelper(textFields, enumFields, boolFields, inputListFields)) _fieldHelper(inputName),
        if (_types.needsSwitchBoolHelper(boolFields)) _switchBoolFieldHelper(inputName),
        if (_types.needsCheckboxBoolHelper(boolFields)) _checkboxBoolFieldHelper(inputName),
        if (_needsDecorationHelper(textFields, enumFields, boolFields)) _decorationHelper(inputName),
        if (textFields.isNotEmpty) _textDecorationHelper(inputName),
        if (dateEligibleFields.isNotEmpty) _date.clampDateHelper(),
        if (dateEligibleFields.isNotEmpty) _date.isCupertinoHelper(),
        if (dateEligibleFields.isNotEmpty) _date.pickDateHelper(),
        if (dateEligibleFields.isNotEmpty) _date.pickDateMaterialHelper(),
        if (dateEligibleFields.isNotEmpty) _date.pickDateCupertinoHelper(),
        if (intFields.isNotEmpty) _date.parseDateHelper(),
        _intersperseHelper(),
      ],
    );
  }

  // ── Build / read / visible rows ───────────────────────────────────────────────

  String _serializeResetMethod(
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
    bool hasSubInputs,
  ) {
    final passwordFields = textFields.where(_types.isPasswordField).toList();
    final dateEligibleFields = textFields.where(
        (f) => _types.dartScalarType(f) == 'int' || _types.dartScalarType(f) == 'String').toList();

    // Helper: wraps a reset statement so it only runs when fields is null (full reset)
    // or when the named field is explicitly listed.
    String ifField(GLField f, String stmt) => _u.ifStatement(
          condition: "fields == null || fields.contains('${f.codeName}')",
          ifBlockStatements: [stmt],
        );

    final setStateBody = _u.block([
      ...textFields.map((f) => ifField(f, '_${f.codeName}Controller.text = ${_types.initialTextExpr(f)};')),
      // password and calendar are tied to their field — reset together with it
      ...passwordFields.map((f) => ifField(f, '_${f.codeName}Obscured = true;')),
      ...dateEligibleFields.map((f) => ifField(f, '_${f.codeName}CalendarOpen = false;')),
      ...enumFields.map((f) => ifField(f, '_${f.codeName} = _form.initialValues?.${f.codeName};')),
      ...boolFields.map((f) => ifField(f, '_${f.codeName} = ${_types.initialBoolExpr(f)};')),
      ...listFields.map((f) {
        final stmt = _types.isEnumListField(f) || _types.isScalarListField(f)
            ? '_${f.codeName} = List.of(_form.${f.codeName});'
            : f.type.nullable
                ? '_${f.codeName} = _form.${f.codeName} != null ? List.of(_form.${f.codeName}!) : null;'
                : '_${f.codeName} = List.of(_form.${f.codeName});';
        return ifField(f, stmt);
      }),
      // stepper position — full reset only
      if (hasSubInputs) _u.inlineIfStatement(condition: 'fields == null', statement: '_currentStep = 0;'),
    ]);

    // After setState: clear validation state and reset sub-forms.
    // Full reset → clear entire form validation + all sub-forms.
    // Partial reset → only reset explicitly listed sub-input keys; leave validation as-is
    //                 so errors on untouched fields remain visible.
    final validatableForReset = [...textFields, ...enumFields, ...boolFields];
    final postResetStatements = [
      '_debounceTimer?.cancel();',
      // Cancel any in-flight async validators and clear their shadow errors.
      ...validatableForReset.map((f) => '_${f.codeName}AsyncTimer?.cancel();'),
      ...validatableForReset.map((f) => '_${f.codeName}AsyncError = null;'),
      ...validatableForReset.map((f) => '_${f.codeName}Validating = false;'),
      _u.ifStatement(
        condition: 'fields == null',
        ifBlockStatements: [
          '_formKey.currentState?.reset();',
          ...inputFields.map((f) => '_${f.codeName}Key.currentState?.reset();'),
        ],
        elseBlockStatements: [
          ...inputFields.map((f) => _u.inlineIfStatement(
                condition: "fields.contains('${f.codeName}')",
                statement: '_${f.codeName}Key.currentState?.reset();',
              )),
        ],
      ),
    ];

    return _u.createMethod(
      override: true,
      returnType: 'void',
      methodName: 'reset',
      namedArguments: true,
      arguments: ['List<String>? fields'],
      statements: [
        _u.tryCatchFinally(
          tryStatements: [
            '_isResetting = true;',
            'setState(() $setStateBody);',
            ...postResetStatements,
          ],
          finallyStatements: ['_isResetting = false;'],
        ),
      ],
    );
  }

  String _serializeIsDirtyGetter(
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
  ) {
    final checks = <String>[];

    for (final f in textFields) {
      checks.add("if (_${f.codeName}Controller.text != (${_types.initialTextExpr(f)})) return true;");
    }
    for (final f in enumFields) {
      checks.add("if (_${f.codeName} != _form.initialValues?.${f.codeName}) return true;");
    }
    for (final f in boolFields) {
      checks.add("if (_${f.codeName} != (${_types.initialBoolExpr(f)})) return true;");
    }
    for (final f in listFields) {
      if (_types.isEnumListField(f) || _types.isScalarListField(f)) {
        // Order-insensitive comparison — chips selections are unordered
        checks.add(
          "if (_${f.codeName}.length != _form.${f.codeName}.length || !_${f.codeName}.toSet().containsAll(_form.${f.codeName})) return true;",
        );
      } else if (_types.isInputListField(f)) {
        checks.add("if (_${f.codeName}OverrideKey.currentState?.isDirty ?? false) return true;");
      }
    }
    for (final f in inputFields) {
      checks.add("if (_${f.codeName}Key.currentState?.isDirty ?? false) return true;");
    }

    final body = _u.block([...checks, 'return false;']);
    return '@override\nbool get isDirty $body';
  }

  String _serializeScrollToFirstErrorMethod(
    String inputName,
    List<GLField> fields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
  ) {
    final scrollableFields = fields
        .where((f) => textFields.contains(f) || enumFields.contains(f) || boolFields.contains(f))
        .toList();

    if (scrollableFields.isEmpty) {
      return _u.createMethod(
        returnType: 'void',
        methodName: '_scrollToFirstError',
        arguments: [],
        namedArguments: false,
        statements: [],
      );
    }

    final addEntries = scrollableFields.map((f) {
      final defaultIdx = 1000 + fields.indexOf(f);
      return "entries.add(MapEntry(ord.${f.codeName} ?? $defaultIdx, _${f.codeName}FieldKey));";
    }).toList();

    return _u.createMethod(
      returnType: 'void',
      methodName: '_scrollToFirstError',
      arguments: [],
      namedArguments: false,
      statements: [
        'final ord = _form.order ?? const ${inputName}Order();',
        'final entries = <MapEntry<int, GlobalKey<FormFieldState>>>[];',
        ...addEntries,
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        _u.forEachLoop(
          variable: 'e',
          iterable: 'entries',
          statements: [
            'final ctx = e.value.currentContext;',
            _u.ifStatement(
              condition: 'ctx != null && (e.value.currentState?.hasError ?? false)',
              ifBlockStatements: [
                'Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);',
                'return;',
              ],
            ),
          ],
        ),
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
              'onStepTapped: (i) { if (i <= _currentStep) setState(() => _currentStep = i); }',
              'controlsBuilder: _form.stepControlsBuilder ?? _buildStepControls',
              'steps: _buildSteps()',
            ])};',
          ],
        ),
        'final rows = _visibleRows();',
        _u.ifStatement(
          condition: '_form.layout == ${inputName}Layout.column',
          ifBlockStatements: [columnReturn],
        ),
        twoColumnReturn,
      ],
    );
  }

  String _serializeBuildResultMethod(
    String inputName,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
  ) {
    final allFormFields = [...textFields, ...enumFields, ...boolFields, ...inputFields];
    final visDecls = [...allFormFields, ...listFields].map((f) =>
        'final _${f.codeName}Vis = vis.${f.codeName}?.call(_ctx) ?? FieldVisibility.enabled;').toList();

    final nonInputAssignments = [...textFields, ...enumFields, ...boolFields].map((f) {
      final name = f.codeName;
      final visibleExpr = _visibleReadExpr(f, textFields, enumFields, boolFields);
      final hiddenExpr = _hiddenReadExpr(f);
      return '$name: _${name}Vis == FieldVisibility.hidden '
          '? $hiddenExpr '
          ': _form.values?.$name != null '
              '? _${name}OverrideKey.currentState!.read() '
              ': $visibleExpr';
    }).toList();

    final inputAssignments = inputFields.map((f) {
      final name = f.codeName;
      final hiddenExpr = _hiddenReadExpr(f);
      return '$name: _${name}Vis != FieldVisibility.hidden ? _${name}Key.currentState!.read() : $hiddenExpr';
    }).toList();

    final listAssignments = listFields.map((f) {
      final name = f.codeName;
      return '$name: _${name}Vis != FieldVisibility.hidden && _form.values?.$name != null '
          '? _${name}OverrideKey.currentState!.read() '
          ': _$name';
    }).toList();

    return _u.createMethod(
      returnType: inputName,
      methodName: '_buildResult',
      arguments: [],
      namedArguments: false,
      statements: [
        'final vis = _form.visibility ?? const ${inputName}Visibility();',
        'final def = _form.hiddenDefaults ?? const ${inputName}Defaults();',
        'final _ctx = _buildContext();',
        ...visDecls,
        'return ${_u.callExpression(inputName, [...nonInputAssignments, ...inputAssignments, ...listAssignments])};',
      ],
    );
  }

  String _serializeReadMethod(String inputName) => _u.createMethod(
        override: true,
        returnType: inputName,
        methodName: 'read',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.ifStatement(
            condition: '_submitting',
            ifBlockStatements: ["throw InputReadException('Form is submitting');"],
          ),
          _u.ifStatement(
            condition: '_isAsyncValidating',
            ifBlockStatements: ["throw InputReadException('Async validation in progress');"],
          ),
          _u.ifStatement(
            condition: '!validate()',
            ifBlockStatements: [
              '_scrollToFirstError();',
              "throw InputReadException('Validation failed');",
            ],
          ),
          'return _buildResult();',
        ],
      );

  String _serializeTryReadMethod(String inputName) => _u.createMethod(
        returnType: '$inputName?',
        methodName: 'tryRead',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.tryCatchFinally(
            tryStatements: ['return _buildResult();'],
            catchVariable: '_',
            catchStatements: ['return null;'],
          ),
        ],
      );

  String _serializeValidateMethod(List<GLField> inputFields) {
    return _u.createMethod(
      override: true,
      returnType: 'bool',
      methodName: 'validate',
      arguments: [],
      namedArguments: false,
      statements: [
        'if (_isAsyncValidating) return false;',
        'var _valid = _formKey.currentState?.validate() ?? false;',
        // Use &= (non-short-circuit) so every sub-form is validated even if a previous one failed.
        // currentState is null when a sub-form is hidden/unmounted — ?? true treats it as valid.
        ...inputFields.map((f) =>
            '_valid &= _${f.codeName}Key.currentState?.validate() ?? true;'),
        '_updateErrorsNotifier();',
        'return _valid;',
      ],
    );
  }


  String _serializeVisibleRowsMethod(
    String methodName,
    String inputName,
    List<GLField> fields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
  ) {
    final visDecls = fields.map((f) =>
        'final _${f.codeName}Vis = vis.${f.codeName}?.call(_ctx) ?? FieldVisibility.enabled;').toList();

    final rowLines = _buildFieldLines(
      inputName,
      fields, textFields, enumFields, boolFields, listFields, inputFields,
      (f, idx, w) => "entries.add(MapEntry(ord.${f.codeName} ?? $idx, $w))",
    );

    return _u.createMethod(
      returnType: 'List<Widget>',
      methodName: methodName,
      arguments: [],
      namedArguments: false,
      statements: [
        'final vis = _form.visibility ?? const ${inputName}Visibility();',
        'final ord = _form.order ?? const ${inputName}Order();',
        'final _ctx = _buildContext();',
        'final entries = <MapEntry<int, Widget>>[];',
        ...visDecls,
        ...rowLines,
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return entries.map((e) => e.value).toList();',
      ],
    );
  }

  // ── read() expression helpers ─────────────────────────────────────────────────

  String _visibleReadExpr(GLField f, List<GLField> textFields, List<GLField> enumFields,
      List<GLField> boolFields) {
    final name = f.codeName;
    final dartType = _types.dartScalarType(f);
    final nullable = f.type.nullable;

    if (textFields.contains(f)) {
      if (dartType == 'int') {
        return nullable
            ? '_form.dateConfig?.$name != null ? _parseDate(_${name}Controller.text, _form.dateConfig!.$name!) : int.tryParse(_${name}Controller.text)'
            : '_form.dateConfig?.$name != null ? (_parseDate(_${name}Controller.text, _form.dateConfig!.$name!) ?? (throw InputReadException(\'$name: invalid date\'))) : int.parse(_${name}Controller.text)';
      }
      if (dartType == 'double') {
        return nullable ? 'double.tryParse(_${name}Controller.text)' : 'double.parse(_${name}Controller.text)';
      }
      return nullable
          ? '_${name}Controller.text.isEmpty ? null : _${name}Controller.text'
          : '_${name}Controller.text';
    }

    if (enumFields.contains(f)) {
      return nullable
          ? '_$name'
          : "_$name ?? (throw InputReadException('$name: no value selected'))";
    }

    if (boolFields.contains(f)) {
      final needsNullCheck = !nullable && _types.isTristateField(f);
      return needsNullCheck
          ? "_$name ?? (throw InputReadException('$name: no value selected'))"
          : '_$name';
    }

    return '_${name}Key.currentState!.read()';
  }

  String _hiddenReadExpr(GLField f) {
    final name = f.codeName;
    return f.type.nullable
        ? 'def.$name'
        : "def.$name ?? (throw InputReadException('$name: default required when hidden'))";
  }

  // ── Layout helper generators (emitted into the state class) ──────────────────

  String _requiredLabelHelper(String inputName) => _u.createMethod(
        returnType: 'Widget',
        methodName: '_requiredLabel',
        namedArguments: false,
        arguments: ['Widget label', 'bool required'],
        statements: [
          _u.switchStatement(
            expression: '_form.requiredIndicator',
            cases: [
              DartCaseStatement(
                caseValue: 'RequiredIndicator.asterisk',
                statement: 'return required ? ${_u.callExpression('Row', [
                  'mainAxisSize: MainAxisSize.min',
                  _u.listArg('children', [
                    'label',
                    'const SizedBox(width: 2)',
                    "_form.requiredLabel ?? Text(' *', semanticsLabel: _form.strings.requiredText, style: TextStyle(color: Theme.of(context).colorScheme.error))",
                  ]),
                ])} : label;',
              ),
              DartCaseStatement(
                caseValue: 'RequiredIndicator.requiredText',
                statement: 'return required ? ${_u.callExpression('Row', [
                  'mainAxisSize: MainAxisSize.min',
                  _u.listArg('children', [
                    'label',
                    'const SizedBox(width: 4)',
                    "_form.requiredLabel ?? Text(_form.strings.requiredText, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))",
                  ]),
                ])} : label;',
              ),
              DartCaseStatement(
                caseValue: 'RequiredIndicator.optionalText',
                statement: 'return !required ? ${_u.callExpression('Row', [
                  'mainAxisSize: MainAxisSize.min',
                  _u.listArg('children', [
                    'label',
                    'const SizedBox(width: 4)',
                    "_form.optionalLabel ?? Text(_form.strings.optionalText, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12))",
                  ]),
                ])} : label;',
              ),
            ],
            defaultStatements: ['return label;'],
          ),
        ],
      );

  String _labelWithInfoHelper(String inputName) => _u.createMethod(
        returnType: 'Widget',
        methodName: '_labelWithInfo',
        namedArguments: false,
        arguments: ['Widget label', 'String? info'],
        statements: [
          'if (info == null) return label;',
          'if (_form.labelPosition == ${inputName}LabelPosition.floatingLabel) return label;',
          'return ${_u.callExpression('Row', [
            'mainAxisSize: MainAxisSize.min',
            _u.listArg('children', [
              'label',
              _u.callExpression('IconButton', [
                'icon: const Icon(Icons.info_outline, size: 16)',
                'padding: EdgeInsets.zero',
                'constraints: const BoxConstraints()',
                "onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(content: Text(info), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))]))",
              ]),
            ]),
          ])};',
        ],
      );

  String _withFloatingInfoHelper(String inputName) => _u.createMethod(
        returnType: 'Widget',
        methodName: '_withFloatingInfo',
        namedArguments: false,
        arguments: ['Widget field', 'String? info'],
        statements: [
          'if (info == null || _form.labelPosition != ${inputName}LabelPosition.floatingLabel) return field;',
          'return ${_u.callExpression('Row', [
            'crossAxisAlignment: CrossAxisAlignment.center',
            _u.listArg('children', [
              'Expanded(child: field)',
              _u.callExpression('IconButton', [
                'icon: const Icon(Icons.info_outline, size: 16)',
                'padding: EdgeInsets.zero',
                'constraints: const BoxConstraints()',
                "onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(content: Text(info), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))]))",
              ]),
            ]),
          ])};',
        ],
      );

  String _fieldHelper(String inputName) => _u.createMethod(
        returnType: 'Widget',
        methodName: '_field',
        namedArguments: false,
        arguments: ['Widget label', 'Widget input'],
        statements: [
          _u.switchStatement(
            expression: '_form.labelPosition',
            cases: [
              DartCaseStatement(
                caseValue: '${inputName}LabelPosition.beside',
                statement: 'return ${_u.callExpression('Row', [
                  'crossAxisAlignment: CrossAxisAlignment.center',
                  _u.listArg('children', ['SizedBox(width: _form.labelWidth, child: label)', 'Expanded(child: input)']),
                ])};',
              ),
              DartCaseStatement(
                caseValue: '${inputName}LabelPosition.above',
                statement: 'return ${_u.callExpression('Column', [
                  'crossAxisAlignment: CrossAxisAlignment.start',
                  _u.listArg('children', ['label', 'const SizedBox(height: 4)', 'input']),
                ])};',
              ),
            ],
            defaultStatements: ['return input;'],
          ),
        ],
      );

  String _switchBoolFieldHelper(String inputName) => _u.createMethod(
        returnType: 'Widget',
        methodName: '_switchBoolField',
        namedArguments: false,
        arguments: ['Widget label', 'bool value', 'void Function(bool)? onChanged'],
        statements: [
          _u.switchStatement(
            expression: '_form.labelPosition',
            cases: [
              DartCaseStatement(
                caseValue: '${inputName}LabelPosition.floatingLabel',
                statement: 'return ${_u.callExpression('SwitchListTile', [
                  'contentPadding: EdgeInsets.zero',
                  'title: label',
                  'value: value',
                  'onChanged: onChanged',
                ])};',
              ),
              DartCaseStatement(
                caseValue: '${inputName}LabelPosition.beside',
                statement: 'return ${_u.callExpression('Row', [
                  'crossAxisAlignment: CrossAxisAlignment.center',
                  _u.listArg('children', ['SizedBox(width: _form.labelWidth, child: label)', 'Switch(value: value, onChanged: onChanged)']),
                ])};',
              ),
            ],
            defaultStatements: [
              'return ${_u.callExpression('Column', [
                'crossAxisAlignment: CrossAxisAlignment.start',
                _u.listArg('children', ['label', 'const SizedBox(height: 4)', 'Switch(value: value, onChanged: onChanged)']),
              ])};',
            ],
          ),
        ],
      );

  String _checkboxBoolFieldHelper(String inputName) => _u.createMethod(
        returnType: 'Widget',
        methodName: '_checkboxBoolField',
        namedArguments: false,
        arguments: ['Widget label', 'bool? value', 'bool tristate', 'void Function(bool?)? onChanged'],
        statements: [
          _u.switchStatement(
            expression: '_form.labelPosition',
            cases: [
              DartCaseStatement(
                caseValue: '${inputName}LabelPosition.floatingLabel',
                statement: 'return ${_u.callExpression('CheckboxListTile', [
                  'contentPadding: EdgeInsets.zero',
                  'title: label',
                  'value: value',
                  'tristate: tristate',
                  'onChanged: onChanged',
                ])};',
              ),
              DartCaseStatement(
                caseValue: '${inputName}LabelPosition.beside',
                statement: 'return ${_u.callExpression('Row', [
                  'crossAxisAlignment: CrossAxisAlignment.center',
                  _u.listArg('children', ['SizedBox(width: _form.labelWidth, child: label)', 'Checkbox(value: value, tristate: tristate, onChanged: onChanged)']),
                ])};',
              ),
            ],
            defaultStatements: [
              'return ${_u.callExpression('Column', [
                'crossAxisAlignment: CrossAxisAlignment.start',
                _u.listArg('children', ['label', 'const SizedBox(height: 4)', 'Checkbox(value: value, tristate: tristate, onChanged: onChanged)']),
              ])};',
            ],
          ),
        ],
      );

  String _decorationHelper(String inputName) => _u.createMethod(
        returnType: 'InputDecoration',
        methodName: '_decoration',
        namedArguments: false,
        arguments: ['Widget label'],
        statements: [
          'return ${_u.ternaryOp(condition: '_form.labelPosition == ${inputName}LabelPosition.floatingLabel', positiveStatement: 'InputDecoration(label: label)', negativeStatement: 'const InputDecoration()')};',
        ],
      );

  String _textDecorationHelper(String inputName) => _u.createMethod(
        returnType: 'InputDecoration',
        methodName: '_textDecoration',
        namedArguments: false,
        arguments: ['Widget label', 'TextFieldOptions? opts', 'Widget? suffixIcon', '[Widget? prefixIcon]'],
        statements: [
          'var d = _decoration(label);',
          'final _pi = prefixIcon ?? opts?.prefixIcon;',
          _u.inlineIfStatement(condition: '_pi != null', statement: 'd = d.copyWith(prefixIcon: _pi);'),
          _u.inlineIfStatement(condition: 'opts?.suffixIcon != null', statement: 'd = d.copyWith(suffixIcon: opts!.suffixIcon);'),
          _u.inlineIfStatement(condition: 'suffixIcon != null', statement: 'd = d.copyWith(suffixIcon: suffixIcon);'),
          'return opts?.decoration?.call(d) ?? d;',
        ],
      );

  String _intersperseHelper() => _u.createMethod(
        returnType: 'List<Widget>',
        methodName: '_intersperse',
        namedArguments: false,
        arguments: ['List<Widget> widgets', 'double gap'],
        statements: [
          _u.inlineIfStatement(condition: 'widgets.isEmpty', statement: 'return [];'),
          'final result = <Widget>[];',
          _u.forLoop(
            init: 'var i = 0',
            condition: 'i < widgets.length',
            increment: 'i++',
            statements: [
              'result.add(widgets[i]);',
              _u.inlineIfStatement(condition: 'i < widgets.length - 1', statement: 'result.add(SizedBox(height: gap));'),
            ],
          ),
          'return result;',
        ],
      );

  // ── Build context snapshot ────────────────────────────────────────────────────

  String _buildContextMethod(String inputName, List<GLField> contextFields) {
    final args = contextFields.map((f) =>
        '${f.codeName}: ${_types.formContextFieldInitExpr(f)}').toList();
    return _u.createMethod(
      returnType: '${inputName}FormContext',
      methodName: '_buildContext',
      arguments: [],
      namedArguments: false,
      statements: [
        'return ${_u.callExpression('${inputName}FormContext', args)};',
      ],
    );
  }

  // ── Nested input field row ────────────────────────────────────────────────────

  String _inputFieldRowMethod(GLField f) {
    final name = f.codeName;
    final childType = _types.resolveTypeCodeName(f.type.firstType.token);

    final childForm = _u.callExpression('${childType}Form', [
      'key: _${name}Key',
      'initialValues: _form.initialValues?.$name',
      'strings: _form.strings',
      'requiredIndicator: _form.requiredIndicator',
      'requiredLabel: _form.requiredLabel',
      'optionalLabel: _form.optionalLabel',
      'labelPosition: ${childType}LabelPosition.values.byName(_form.labelPosition.name)',
      'labelWidth: _form.labelWidth',
      'gap: _form.gap',
      // bubble sub-form field changes up to the parent's onChange / onContextChange
      'onContextChange: (_) => _onFieldChanged()',
    ]);

    return _u.createMethod(
      returnType: 'Widget',
      methodName: '_${name}InputRow',
      namedArguments: false,
      arguments: ['Widget label', 'bool enabled'],
      statements: [
        'final _child = ${_u.callExpression('Column', [
          'crossAxisAlignment: CrossAxisAlignment.start',
          _u.listArg('children', [
            'DefaultTextStyle(style: Theme.of(context).textTheme.labelLarge ?? const TextStyle(fontWeight: FontWeight.bold), child: Padding(padding: const EdgeInsets.only(bottom: 8), child: label))',
            childForm,
          ]),
        ])};',
        'return enabled ? _child : IgnorePointer(ignoring: true, child: Opacity(opacity: 0.38, child: _child));',
      ],
    );
  }

  String _onFieldChangedMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_onFieldChanged',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.inlineIfStatement(condition: '!mounted', statement: 'return;'),
          '_notifyContextChange();',
          '_scheduleOnChange();',
          'if (!_asyncNotifying) _scheduleAllAsyncValidations();',
          '_updateErrorsNotifier();',
        ],
      );

  String _notifyContextChangeMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_notifyContextChange',
        arguments: [],
        namedArguments: false,
        statements: ['_form.onContextChange?.call(_buildContext());'],
      );

  String _scheduleOnChangeMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_scheduleOnChange',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.inlineIfStatement(condition: '_form.onChange == null', statement: 'return;'),
          '_debounceTimer?.cancel();',
          '_debounceTimer = Timer(_form.debounceDuration, () ${_u.block([
            _u.inlineIfStatement(condition: 'mounted', statement: '_form.onChange?.call(tryRead());'),
          ])});',
        ],
      );

  // ── Stepper support ───────────────────────────────────────────────────────────

  /// Builds the ordered list of step buckets at generator time.
  /// Scalar step first (if any scalar fields exist), then sub-inputs and
  /// list-of-inputs interleaved in schema declaration order.
  List<_StepBucket> _buildStepBuckets(
      List<GLField> fields, bool hasScalarFields,
      List<GLField> inputFields, List<GLField> inputListFields) {
    final buckets = <_StepBucket>[];
    var idx = 0;
    if (hasScalarFields) buckets.add(_StepBucket(idx++, _StepType.scalar, null));
    for (final f in fields) {
      if (inputFields.contains(f)) {
        buckets.add(_StepBucket(idx++, _StepType.subInput, f));
      } else if (inputListFields.contains(f)) {
        buckets.add(_StepBucket(idx++, _StepType.inputList, f));
      }
    }
    return buckets;
  }

  // ── Explicit step group methods ───────────────────────────────────────────────

  /// Shared field-iteration logic used by both _visibleRows and _visibleRowMap.
  /// [accumulate] receives (field, defaultOrderIdx, widgetExpr) and returns
  /// the accumulation statement string — the only thing that differs between the two.
  List<String> _buildFieldLines(
    String inputName,
    List<GLField> fields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
    String Function(GLField f, int defaultIdx, String widgetExpr) accumulate,
  ) {
    final directFields = {
      ...listFields.where((f) => _types.isEnumListField(f) || _types.isScalarListField(f)),
    };
    final rowMethodFields = {...enumFields, ...boolFields, ...inputFields};

    return fields.asMap().entries.map((entry) {
      final i = entry.key;
      final f = entry.value;
      final humanLabel = _types.humanize(f.name.token);
      final enabledExpr = '!_submitting && _${f.codeName}Vis == FieldVisibility.enabled';
      final fieldWidget = _fields.fieldWidgetExpr(f, textFields, enumFields, boolFields, listFields, enabledExpr);
      final defaultIdx = 1000 + i;
      final isRequired = !f.type.nullable;
      final labelStmt = "final _rl = _requiredLabel(_form.labels?.${f.codeName} ?? const Text('$humanLabel'), $isRequired); final label = _form.labelPosition == ${inputName}LabelPosition.floatingLabel ? _rl : _labelWithInfo(_rl, _form.labels?.${f.codeName}Info);";

      final String widgetExpr;
      if (inputFields.contains(f)) {
        widgetExpr = '_${f.codeName}InputRow(label, $enabledExpr)';
      } else if (textFields.contains(f)) {
        widgetExpr = '_form.values?.${f.codeName}?.call(_${f.codeName}OverrideKey) ?? _${f.codeName}ScalarRow(label, $enabledExpr)';
      } else if (rowMethodFields.contains(f)) {
        widgetExpr = '_form.values?.${f.codeName}?.call(_${f.codeName}OverrideKey) ?? _${f.codeName}Row(label, $enabledExpr)';
      } else if (directFields.contains(f)) {
        widgetExpr = '_form.values?.${f.codeName}?.call(_${f.codeName}OverrideKey) ?? $fieldWidget';
      } else {
        widgetExpr = '_field(label, _form.values?.${f.codeName}?.call(_${f.codeName}OverrideKey) ?? $fieldWidget)';
      }

      return _u.ifStatement(
        condition: '_${f.codeName}Vis != FieldVisibility.hidden',
        ifBlockStatements: [labelStmt, '${accumulate(f, defaultIdx, "_withFloatingInfo($widgetExpr, _form.labels?.${f.codeName}Info)")};'],
      );
    }).toList();
  }

  String _serializeBuildStepsMethod(
      String inputName, List<_StepBucket> buckets, bool hasScalarFields) {
    final humanizedInputName = _humanizeInputName(inputName);
    final stepExprs = buckets.map((b) {
      final idx = b.index;
      final stateExpr =
          '_currentStep > $idx ? StepState.complete : _currentStep == $idx ? StepState.editing : StepState.indexed';

      if (b.type == _StepType.scalar) {
        return _u.callExpression('Step', [
          'title: _form.stepConfig?.scalarFields?.title ?? const Text(\'$humanizedInputName\')',
          'subtitle: _form.stepConfig?.scalarFields?.subtitle',
          'isActive: _currentStep >= $idx',
          'state: $stateExpr',
          'content: ${_u.callExpression('Form', [
            'key: _formKey',
            'child: ${_u.callExpression('Column', [
              'mainAxisSize: MainAxisSize.min',
              'crossAxisAlignment: CrossAxisAlignment.stretch',
              'children: _intersperse(_scalarRows(), _form.gap)',
            ])}',
          ])}',
        ]);
      }

      final f = b.field!;
      final name = f.codeName;
      final humanLabel = _types.humanize(f.name.token);

      if (b.type == _StepType.subInput) {
        final childType = _types.resolveTypeCodeName(f.type.firstType.token);
        return _u.callExpression('Step', [
          'title: _form.stepConfig?.$name?.title ?? const Text(\'$humanLabel\')',
          'subtitle: _form.stepConfig?.$name?.subtitle',
          'isActive: _currentStep >= $idx',
          'state: $stateExpr',
          'content: ${_u.callExpression('${childType}Form', [
            'key: _${name}Key',
            'strings: _form.strings',
            'initialValues: _form.initialValues?.$name',
            'requiredIndicator: _form.requiredIndicator',
            'requiredLabel: _form.requiredLabel',
            'optionalLabel: _form.optionalLabel',
            'labelPosition: ${childType}LabelPosition.values.byName(_form.labelPosition.name)',
            'labelWidth: _form.labelWidth',
            'gap: _form.gap',
            'onContextChange: (_) => _onFieldChanged()',
          ])}',
        ]);
      }

      // inputList
      final lengthExpr = f.type.nullable ? '_$name?.length ?? 0' : '_$name.length';
      return _u.callExpression('Step', [
        'title: _form.stepConfig?.$name?.title ?? const Text(\'$humanLabel\')',
        'subtitle: _form.stepConfig?.$name?.subtitle',
        'isActive: _currentStep >= $idx',
        'state: $stateExpr',
        'content: _form.values?.$name?.call(_${name}OverrideKey) ?? Text(\'\${$lengthExpr} items\')',
      ]);
    }).toList();

    final stepsList = '[${stepExprs.map((e) => '\n  $e,').join('')}\n]';
    return _u.createMethod(
      returnType: 'List<Step>',
      methodName: '_buildSteps',
      arguments: [],
      namedArguments: false,
      statements: ['return $stepsList;'],
    );
  }

  String _serializeScalarRowsMethod(
      String inputName,
      List<GLField> fields,
      List<GLField> textFields,
      List<GLField> enumFields,
      List<GLField> boolFields,
      List<GLField> listFields) {
    final scalarFields = fields
        .where((f) => !_types.isInputField(f) && !_types.isInputListField(f))
        .toList();
    final scalarListFields = listFields
        .where((f) => !_types.isInputListField(f))
        .toList();
    return _serializeVisibleRowsMethod(
      '_scalarRows',
      inputName,
      scalarFields,
      textFields,
      enumFields,
      boolFields,
      scalarListFields,
      [],
    );
  }

  String _serializeValidateAndReadCurrentStepMethod(
      String inputName, List<_StepBucket> buckets) {
    final cases = buckets.map((b) {
      final idx = b.index;
      List<String> validateStatements;
      if (b.type == _StepType.scalar) {
        validateStatements = [
          'return _formKey.currentState?.validate() ?? false;',
        ];
      } else if (b.type == _StepType.subInput) {
        validateStatements = [
          _u.tryCatchFinally(
            tryStatements: ['_${b.field!.name}Key.currentState!.read();', 'return true;'],
            catchVariable: '_',
            catchStatements: ['return false;'],
          ),
        ];
      } else {
        // inputList — only validate if a Values override is present
        validateStatements = [
          _u.ifStatement(
            condition: '_form.values?.${b.field!.name} != null',
            ifBlockStatements: [
              _u.tryCatchFinally(
                tryStatements: ['_${b.field!.name}OverrideKey.currentState!.read();', 'return true;'],
                catchVariable: '_',
                catchStatements: ['return false;'],
              ),
            ],
          ),
          'return true;',
        ];
      }

      return DartCaseStatement(
        caseValue: '$idx',
        statement: _u.block(validateStatements),
      );
    }).toList();

    return _u.createMethod(
      returnType: 'bool',
      methodName: '_validateAndReadCurrentStep',
      arguments: [],
      namedArguments: false,
      statements: [
        _u.switchStatement(
          expression: '_currentStep',
          cases: cases,
          defaultStatements: ['return true;'],
          generateBreaks: false,
        ),
      ],
    );
  }

  String _serializeOnStepContinueMethod(int totalSteps) => _u.createMethod(
        returnType: 'void',
        methodName: '_onStepContinue',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.ifStatement(
            condition: '_validateAndReadCurrentStep()',
            ifBlockStatements: [
              _u.ifStatement(
                condition: '_currentStep < ${totalSteps - 1}',
                ifBlockStatements: ['setState(() => _currentStep++);'],
              ),
            ],
          ),
        ],
      );

  String _serializeOnStepCancelMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_onStepCancel',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.ifStatement(
            condition: '_currentStep > 0',
            ifBlockStatements: ['setState(() => _currentStep--);'],
          ),
        ],
      );

  String _serializeBuildStepControlsMethod(int totalSteps) => _u.createMethod(
        returnType: 'Widget',
        methodName: '_buildStepControls',
        namedArguments: false,
        arguments: ['BuildContext context', 'ControlsDetails details'],
        statements: [
          'final isFirst = details.stepIndex == 0;',
          'final isLast = details.stepIndex == ${totalSteps - 1};',
          'return ${_u.callExpression('Row', [
            'mainAxisAlignment: _form.stepControlsAlignment',
            _u.listArg('children', [
              // Back — hidden on first step, always takes space to keep Next stable
              _u.callExpression('Visibility', [
                'visible: !isFirst',
                'maintainSize: true',
                'maintainAnimation: true',
                'maintainState: true',
                'child: ${_u.callExpression('TextButton', [
                  'onPressed: details.onStepCancel',
                  'child: Text(_form.stepperStrings.back)',
                ])}',
              ]),
              // Next / Submit
              _u.callExpression('ElevatedButton', [
                'onPressed: _submitting ? null : details.onStepContinue',
                'child: Text(isLast ? _form.stepperStrings.submit : _form.stepperStrings.next)',
              ]),
            ]),
          ])};',
        ],
      );

  String _humanizeInputName(String inputName) {
    final withoutSuffix = inputName.endsWith('Input')
        ? inputName.substring(0, inputName.length - 5)
        : inputName;
    return _types.humanize(withoutSuffix);
  }

  // ── Async validation scheduling ───────────────────────────────────────────────

  String _scheduleAllAsyncValidationsMethod(List<GLField> validatableFields) =>
      _u.createMethod(
        returnType: 'void',
        methodName: '_scheduleAllAsyncValidations',
        arguments: [],
        namedArguments: false,
        statements: validatableFields.map((f) {
          final cap = '${f.codeName[0].toUpperCase()}${f.codeName.substring(1)}';
          return '_schedule${cap}AsyncValidation();';
        }).toList(),
      );

  List<String> _asyncSchedulerMethods(List<GLField> validatableFields, List<GLField> textFields) =>
      validatableFields.map((f) {
        final name = f.codeName;
        final cap = '${name[0].toUpperCase()}${name.substring(1)}';
        final valueExpr = textFields.contains(f) ? '_${name}Controller.text' : '_$name';
        return _u.createMethod(
          returnType: 'void',
          methodName: '_schedule${cap}AsyncValidation',
          arguments: [],
          namedArguments: false,
          statements: [
            '_${name}AsyncTimer?.cancel();',
            'if (_form.validations?.$name == null) return;',
            '_${name}AsyncTimer = Timer(_form.debounceDuration, () async ${_u.block([
              'if (!mounted) return;',
              '_asyncNotifying = true;',
              'setState(() { _${name}Validating = true; _${name}AsyncError = null; });',
              '_asyncNotifying = false;',
              'final _r = await _form.validations!.$name!($valueExpr, _buildContext());',
              'if (!mounted) return;',
              '_asyncNotifying = true;',
              'setState(() { _${name}Validating = false; _${name}AsyncError = _r; });',
              '_asyncNotifying = false;',
              '_${name}FieldKey.currentState?.validate();',
              '_updateErrorsNotifier();',
            ])});',
          ],
        );
      }).toList();

  // ── Error summary support ─────────────────────────────────────────────────────

  String _updateErrorsNotifierMethod(
    String inputName,
    List<GLField> allFields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
  ) {
    final scrollableFields = allFields
        .where((f) => textFields.contains(f) || enumFields.contains(f) || boolFields.contains(f))
        .toList();

    if (scrollableFields.isEmpty) {
      return _u.createMethod(
        returnType: 'void', methodName: '_updateErrorsNotifier',
        arguments: [], namedArguments: false, statements: [],
      );
    }

    final addEntries = scrollableFields.map((f) {
      final defaultIdx = 1000 + allFields.indexOf(f);
      return _u.ifStatement(
        condition: "_${f.codeName}FieldKey.currentState?.hasError == true",
        ifBlockStatements: [
          "entries.add(MapEntry(ord.${f.codeName} ?? $defaultIdx, MapEntry('${f.codeName}', _${f.codeName}FieldKey.currentState!.errorText!)));",
        ],
      );
    }).toList();

    return _u.createMethod(
      returnType: 'void',
      methodName: '_updateErrorsNotifier',
      arguments: [],
      namedArguments: false,
      statements: [
        'final ord = _form.order ?? const ${inputName}Order();',
        'final entries = <MapEntry<int, MapEntry<String, String>>>[];',
        ...addEntries,
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        '_errorsNotifier.value = Map.fromEntries(entries.map((e) => e.value));',
      ],
    );
  }

  String _scrollToFieldMethod(
    String inputName,
    List<GLField> allFields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
  ) {
    final scrollableFields = allFields
        .where((f) => textFields.contains(f) || enumFields.contains(f) || boolFields.contains(f))
        .toList();

    final cases = scrollableFields.map((f) => DartCaseStatement(
      caseValue: "'${f.codeName}'",
      statement: _u.block([
        'final ctx = _${f.codeName}FieldKey.currentContext;',
        'if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);',
      ]),
    )).toList();

    return _u.createMethod(
      returnType: 'void',
      methodName: 'scrollToField',
      namedArguments: false,
      arguments: ['String fieldName'],
      statements: [
        _u.switchStatement(expression: 'fieldName', cases: cases, defaultStatements: []),
      ],
    );
  }

  String serializeErrorSummaryClass(
    String inputName,
    List<GLField> allFields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
  ) {
    final scrollableFields = allFields
        .where((f) => textFields.contains(f) || enumFields.contains(f) || boolFields.contains(f))
        .toList();

    final labelCases = scrollableFields
        .map((f) => "case '${f.codeName}': return '${_types.humanize(f.name.token)}';")

        .join('\n      ');

    return '''
class ${inputName}ErrorSummary extends StatefulWidget {
  final GlobalKey<${inputName}FormState> formKey;
  const ${inputName}ErrorSummary({required this.formKey, super.key});

  @override
  State<${inputName}ErrorSummary> createState() => _${inputName}ErrorSummaryState();
}

class _${inputName}ErrorSummaryState extends State<${inputName}ErrorSummary> {
  @override
  void initState() {
    super.initState();
    // Trigger a rebuild once the form state is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  String _label(String field) {
    switch (field) {
      $labelCases
      default: return field;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.formKey.currentState;
    if (state == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: state.errorsNotifier,
      builder: (context, _) {
        final errors = state.errorsNotifier.value;
        if (errors.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: errors.entries.map((e) => Semantics(
            liveRegion: true,
            child: InkWell(
              onTap: () => widget.formKey.currentState?.scrollToField(e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '\${_label(e.key)}: \${e.value}',
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )).toList(),
        );
      },
    );
  }
}''';
  }

  // _field is used by: text fields, enum fields, tristate bool, date fields, and input list fields (catch-all).
  bool _needsFieldHelper(List<GLField> textFields, List<GLField> enumFields,
      List<GLField> boolFields, List<GLField> inputListFields) =>
      textFields.isNotEmpty ||
      enumFields.isNotEmpty ||
      boolFields.any(_types.isTristateField) ||
      inputListFields.isNotEmpty;

  // _decoration is used by: text fields (via _textDecoration), enum dropdowns, tristate bool, date fields.
  bool _needsDecorationHelper(
      List<GLField> textFields, List<GLField> enumFields, List<GLField> boolFields) =>
      textFields.isNotEmpty ||
      enumFields.isNotEmpty ||
      boolFields.any(_types.isTristateField);
}
