import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_date_serializer.dart';
import 'flutter_inputs_field_serializer.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsStateSerializer {
  final DartCodeGenUtils _u;
  final FlutterInputsTypeHelpers _types;
  final FlutterInputsFieldSerializer _fields;
  final FlutterInputsDateSerializer _date;

  FlutterInputsStateSerializer(this._u, this._types, this._fields, this._date);

  // ── Widget class ──────────────────────────────────────────────────────────────

  String serializeWidgetClass(
      String inputName, List<GLField> listFields, List<GLField> formFields,
      List<GLField> enumFields, List<GLField> boolFields, List<GLField> textFields,
      List<GLField> dateEligibleFields) {
    final gap = _types.gapStr();
    final hasDropdownLabels = enumFields.isNotEmpty || boolFields.isNotEmpty || listFields.any(_types.isEnumListField);

    final listFieldDecls = <String>[];
    final listParams = <String>[];
    for (final f in listFields) {
      if (_types.isEnumListField(f)) {
        listFieldDecls.add('final List<${_types.listItemTypeNonNull(f)}> ${f.name};');
        listParams.add('this.${f.name} = ${_types.typedEmptyList(f)}');
      } else if (_types.isScalarListField(f)) {
        listFieldDecls.add('final List<${_types.listItemTypeNonNull(f)}> ${f.name};');
        listFieldDecls.add('final List<${_types.listItemTypeNonNull(f)}>? ${f.name}Options;');
        listParams.add('this.${f.name} = ${_types.typedEmptyList(f)}');
        listParams.add('this.${f.name}Options');
      } else {
        listFieldDecls.add('final ${_types.listDartType(f)} ${f.name};');
        listParams.add(f.type.nullable ? 'this.${f.name}' : 'required this.${f.name}');
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
        'final ${inputName}Layout layout;',
        'final ${inputName}LabelPosition labelPosition;',
        'final double labelWidth;',
        'final double gap;',
        'final RequiredIndicator requiredIndicator;',
        'final Widget? requiredLabel;',
        'final Widget? optionalLabel;',
        'final FormStrings strings;',
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
            'this.layout = ${inputName}Layout.column',
            'this.labelPosition = ${inputName}LabelPosition.floatingLabel',
            'this.labelWidth = 120',
            'this.gap = $gap',
            'this.requiredIndicator = RequiredIndicator.asterisk',
            'this.requiredLabel',
            'this.optionalLabel',
            'this.strings = const FormStrings()',
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

    final stateVarDecls = <String>[
      'final _formKey = GlobalKey<FormState>();',
      '${formName} get _form => widget as ${formName};',
      if (textFields.isNotEmpty) '// text controllers',
      ...textFields.map((f) => 'late final TextEditingController _${f.name}Controller;'),
      if (passwordFields.isNotEmpty) '// password visibility state',
      ...passwordFields.map((f) => 'bool _${f.name}Obscured = true;'),
      if (enumFields.isNotEmpty) '// enum state',
      ...enumFields.map((f) => '${f.type.firstType.token}? _${f.name};'),
      if (boolFields.isNotEmpty) '// boolean state',
      ...boolFields.map((f) => '${_types.boolStateType(f)} _${f.name}${_types.boolStateInit(f)};'),
      if (listFields.isNotEmpty) '// list state',
      ...listFields.map((f) {
        if (_types.isEnumListField(f) || _types.isScalarListField(f)) {
          return 'late List<${_types.listItemTypeNonNull(f)}> _${f.name};';
        }
        return f.type.nullable
            ? '${_types.listDartType(f)} _${f.name};'
            : 'late ${_types.listDartType(f)} _${f.name};';
      }),
      if (dateEligibleFields.isNotEmpty) '// inline calendar open state',
      ...dateEligibleFields.map((f) => 'bool _${f.name}CalendarOpen = false;'),
      if (inputFields.isNotEmpty) '// nested input keys',
      ...inputFields.map((f) => 'final _${f.name}Key = GlobalKey<${f.type.firstType.token}FormState>();'),
      '// field override keys',
      ...fields.where((f) => !_types.isInputField(f)).map((f) =>
          'final _${f.name}OverrideKey = GlobalKey<InputFormState<${_types.valuesFieldType(f)}>>();'),
    ];

    final initStatements = <String>[
      'super.initState();',
      ...textFields.map((f) => '_${f.name}Controller = TextEditingController(text: ${_types.initialTextExpr(f)});'),
      ...enumFields.map((f) => '_${f.name} = _form.initialValues?.${f.name};'),
      ...boolFields.map((f) => '_${f.name} = ${_types.initialBoolExpr(f)};'),
      ...listFields.map((f) {
        if (_types.isEnumListField(f) || _types.isScalarListField(f)) {
          return '_${f.name} = List.of(_form.${f.name});';
        }
        return f.type.nullable
            ? '_${f.name} = _form.${f.name} != null ? List.of(_form.${f.name}!) : null;'
            : '_${f.name} = List.of(_form.${f.name});';
      }),
    ];

    final didUpdateStatements = <String>[
      'super.didUpdateWidget(oldWidget);',
      'final oldForm = oldWidget as ${formName};',
      ...listFields.map((f) {
        if (_types.isEnumListField(f) || _types.isScalarListField(f)) {
          return _u.inlineIfStatement(
            condition: '_form.${f.name} != oldForm.${f.name}',
            statement: '_${f.name} = List.of(_form.${f.name});',
          );
        }
        return f.type.nullable
            ? _u.inlineIfStatement(
                condition: '_form.${f.name} != oldForm.${f.name}',
                statement: '_${f.name} = _form.${f.name} != null ? List.of(_form.${f.name}!) : null;',
              )
            : _u.inlineIfStatement(
                condition: '_form.${f.name} != oldForm.${f.name}',
                statement: '_${f.name} = List.of(_form.${f.name});',
              );
      }),
    ];

    final disposeStatements = <String>[
      ...textFields.map((f) => '_${f.name}Controller.dispose();'),
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
        _serializeBuildMethod(inputName),
        _serializeReadMethod(inputName, textFields, enumFields, boolFields, listFields, inputFields),
        _serializeVisibleRowsMethod(inputName, fields, textFields, enumFields, boolFields, listFields, dateEligibleFields, inputFields),
        _buildContextMethod(inputName, fields.where((f) => !_types.isInputField(f)).toList()),
        ...enumFields.map(_fields.enumRowMethod),
        ...boolFields.map(_fields.boolRowMethod),
        ...dateEligibleFields.map(_date.dateRowMethod),
        ...inputFields.map(_inputFieldRowMethod),
        _requiredLabelHelper(inputName),
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

  String _serializeBuildMethod(String inputName) {
    final switchStmt = _u.switchStatement(
      expression: '_form.layout',
      cases: [
        DartCaseStatement(
          caseValue: '${inputName}Layout.column',
          statement: 'child = Column(children: _intersperse(rows, _form.gap));',
        ),
      ],
      defaultStatements: [
        'child = ${_u.callExpression('LayoutBuilder', [
          'builder: ${_u.functionLiteral(['context', 'constraints'], [
            'final childWidth = (constraints.maxWidth - _form.gap) / 2;',
            'return ${_u.callExpression('Wrap', ['spacing: _form.gap', 'runSpacing: _form.gap', 'children: rows.map((w) => SizedBox(width: childWidth, child: w)).toList()'  ])};',
          ])}',
        ])};',
      ],
    );
    return _u.createMethod(
      override: true,
      returnType: 'Widget',
      methodName: 'build',
      namedArguments: false,
      arguments: ['BuildContext context'],
      statements: [
        'final rows = _visibleRows();',
        'Widget child;',
        switchStmt,
        'return ${_u.callExpression('Form', ['key: _formKey', 'child: child'])};',
      ],
    );
  }

  String _serializeReadMethod(
    String inputName,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
  ) {
    final allFormFields = [...textFields, ...enumFields, ...boolFields, ...inputFields];
    // Vis decls for form fields + list fields — all needed for the hidden-wins check.
    final visDecls = [...allFormFields, ...listFields].map((f) =>
        'final _${f.name}Vis = vis.${f.name}?.call(_ctx) ?? FieldVisibility.enabled;').toList();

    // Hidden wins: check visibility first, then override, then controller/state.
    final nonInputAssignments = [...textFields, ...enumFields, ...boolFields].map((f) {
      final name = f.name.token;
      final visibleExpr = _visibleReadExpr(f, textFields, enumFields, boolFields);
      final hiddenExpr = _hiddenReadExpr(f);
      return '$name: _${name}Vis == FieldVisibility.hidden '
          '? $hiddenExpr '
          ': _form.values?.$name != null '
              '? _${name}OverrideKey.currentState!.read() '
              ': $visibleExpr';
    }).toList();

    // Input fields: no values override — use nested key directly.
    final inputAssignments = inputFields.map((f) {
      final name = f.name.token;
      final hiddenExpr = _hiddenReadExpr(f);
      return '$name: _${name}Vis != FieldVisibility.hidden ? _${name}Key.currentState!.read() : $hiddenExpr';
    }).toList();

    // List fields: hidden wins — if hidden fall back to state, otherwise check override.
    // No hiddenDefaults for list fields by design; hidden list fields return current state.
    final listAssignments = listFields.map((f) {
      final name = f.name.token;
      return '$name: _${name}Vis != FieldVisibility.hidden && _form.values?.$name != null '
          '? _${name}OverrideKey.currentState!.read() '
          ': _$name';
    }).toList();

    final fieldAssignments = [...nonInputAssignments, ...inputAssignments];

    return _u.createMethod(
      override: true,
      returnType: inputName,
      methodName: 'read',
      arguments: [],
      namedArguments: false,
      statements: [
        'final vis = _form.visibility ?? const ${inputName}Visibility();',
        'final def = _form.hiddenDefaults ?? const ${inputName}Defaults();',
        'final _ctx = _buildContext();',
        ...visDecls,
        _u.ifStatement(
          condition: '!(_formKey.currentState?.validate() ?? false)',
          ifBlockStatements: ["throw InputReadException('Validation failed');"],
        ),
        'return ${_u.callExpression(inputName, [...fieldAssignments, ...listAssignments])};',
      ],
    );
  }

  String _serializeVisibleRowsMethod(
    String inputName,
    List<GLField> fields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> dateEligibleFields,
    List<GLField> inputFields,
  ) {
    final directFields = {
      ...listFields.where((f) => _types.isEnumListField(f) || _types.isScalarListField(f)),
    };
    final rowMethodFields = {...enumFields, ...boolFields, ...dateEligibleFields, ...inputFields};

    final visDecls = fields.map((f) =>
        'final _${f.name}Vis = vis.${f.name}?.call(_ctx) ?? FieldVisibility.enabled;').toList();

    final rowLines = fields.asMap().entries.map((entry) {
      final i = entry.key;
      final f = entry.value;
      final humanLabel = _types.humanize(f.name.token);
      final enabledExpr = '_${f.name}Vis == FieldVisibility.enabled';
      final fieldWidget = _fields.fieldWidgetExpr(f, textFields, enumFields, boolFields, listFields, enabledExpr);
      final defaultIdx = 1000 + i;
      final isRequired = !f.type.nullable;
      final labelStmt = "final label = _requiredLabel(_form.labels?.${f.name} ?? const Text('$humanLabel'), $isRequired);";

      // Input fields have no Values override — they use their own nested key.
      if (inputFields.contains(f)) {
        return _u.ifStatement(
          condition: '_${f.name}Vis != FieldVisibility.hidden',
          ifBlockStatements: [
            labelStmt,
            "entries.add(MapEntry(ord.${f.name} ?? $defaultIdx, _${f.name}InputRow(label, $enabledExpr)));",
          ],
        );
      }
      // All other fields: try the builder override first, fall back to generated widget.
      if (dateEligibleFields.contains(f)) {
        return _u.ifStatement(
          condition: '_${f.name}Vis != FieldVisibility.hidden',
          ifBlockStatements: [
            labelStmt,
            "entries.add(MapEntry(ord.${f.name} ?? $defaultIdx, _form.values?.${f.name}?.call(_${f.name}OverrideKey) ?? _${f.name}DateRow(label, $enabledExpr)));",
          ],
        );
      }
      if (rowMethodFields.contains(f)) {
        return _u.ifStatement(
          condition: '_${f.name}Vis != FieldVisibility.hidden',
          ifBlockStatements: [
            labelStmt,
            "entries.add(MapEntry(ord.${f.name} ?? $defaultIdx, _form.values?.${f.name}?.call(_${f.name}OverrideKey) ?? _${f.name}Row(label, $enabledExpr)));",
          ],
        );
      }
      if (directFields.contains(f)) {
        return _u.ifStatement(
          condition: '_${f.name}Vis != FieldVisibility.hidden',
          ifBlockStatements: [
            labelStmt,
            "entries.add(MapEntry(ord.${f.name} ?? $defaultIdx, _form.values?.${f.name}?.call(_${f.name}OverrideKey) ?? $fieldWidget));",
          ],
        );
      }
      return _u.ifStatement(
        condition: '_${f.name}Vis != FieldVisibility.hidden',
        ifBlockStatements: [
          labelStmt,
          "entries.add(MapEntry(ord.${f.name} ?? $defaultIdx, _field(label, _form.values?.${f.name}?.call(_${f.name}OverrideKey) ?? $fieldWidget)));",
        ],
      );
    }).toList();

    return _u.createMethod(
      returnType: 'List<Widget>',
      methodName: '_visibleRows',
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
    final name = f.name.token;
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
    final name = f.name.token;
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
        arguments: ['Widget label', 'TextFieldOptions? opts', 'Widget? suffixIcon'],
        statements: [
          'var d = _decoration(label);',
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
        '${f.name}: ${_types.formContextFieldInitExpr(f)}').toList();
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
    final name = f.name.token;
    final childType = f.type.firstType.token;

    final childForm = _u.callExpression('${childType}Form', [
      'key: _${name}Key',
      'initialValues: _form.initialValues?.$name',
      'strings: _form.strings',
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
