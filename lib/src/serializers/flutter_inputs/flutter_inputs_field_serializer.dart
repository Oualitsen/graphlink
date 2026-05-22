import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsFieldSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterInputsTypeHelpers _types;

  FlutterInputsFieldSerializer(this._u, this._config, this._types);

  // ── Field widget dispatch ─────────────────────────────────────────────────────

  String fieldWidgetExpr(GLField f, List<GLField> textFields, List<GLField> enumFields,
      List<GLField> boolFields, List<GLField> listFields, String enabledExpr) {
    if (listFields.contains(f)) {
      if (_types.isEnumListField(f)) return enumListWidgetExpr(f, enabledExpr);
      if (_types.isScalarListField(f)) return scalarListWidgetExpr(f, enabledExpr);
      return "Text('\${_${f.name}.length} items')";
    }
    if (textFields.contains(f)) return textFormFieldExpr(f, enabledExpr);
    if (enumFields.contains(f)) return enumDropdownExpr(f, enabledExpr);
    if (boolFields.contains(f)) return boolFieldExpr(f, enabledExpr);
    return 'const SizedBox.shrink()';
  }

  // ── Text fields ───────────────────────────────────────────────────────────────

  String textFormFieldExpr(GLField f, String enabledExpr) {
    final dartType = _types.dartScalarType(f);
    if (dartType == 'int') return intRegularExpr(f, enabledExpr);
    if (dartType == 'String') return stringRegularExpr(f, enabledExpr);

    final name = f.name.token;
    final nullable = f.type.nullable;
    final validators = _validatorStatements(name, [
      if (!nullable)
        _u.inlineIfStatement(condition: 'v == null || v.isEmpty', statement: 'return _form.strings.required;'),
      if (dartType == 'double') ...[
        if (nullable)
          _u.inlineIfStatement(condition: 'v != null && v.isNotEmpty && double.tryParse(v) == null', statement: 'return _form.strings.mustBeNumber;')
        else
          _u.inlineIfStatement(condition: 'double.tryParse(v) == null', statement: 'return _form.strings.mustBeNumber;'),
      ],
    ]);

    return _u.callExpression('TextFormField', [
      'controller: _${name}Controller',
      'enabled: $enabledExpr',
      'obscureText: _form.textConfig?.$name?.obscureText ?? false',
      'keyboardType: _form.textConfig?.$name?.keyboardType ?? ${_types.smartKeyboardTypeExpr(f)}',
      'textInputAction: _form.textConfig?.$name?.textInputAction ?? TextInputAction.next',
      'textCapitalization: _form.textConfig?.$name?.textCapitalization ?? TextCapitalization.none',
      'autocorrect: _form.textConfig?.$name?.autocorrect ?? ${_types.smartAutocorrect(f)}',
      'enableSuggestions: _form.textConfig?.$name?.enableSuggestions ?? ${_types.smartEnableSuggestions(f)}',
      'maxLength: _form.textConfig?.$name?.maxLength',
      'maxLines: _form.textConfig?.$name?.maxLines ?? 1',
      'decoration: _textDecoration(label, _form.textConfig?.$name, null)',
      'onChanged: (_) => _onFieldChanged()',
      'validator: ${_u.functionLiteral(['v'], validators)}',
    ]);
  }

  String intRegularExpr(GLField f, String enabledExpr) {
    final name = f.name.token;
    final nullable = f.type.nullable;
    final validators = _validatorStatements(name, [
      if (!nullable) "if (v == null || v.isEmpty) return _form.strings.required;",
      if (nullable)
        _u.inlineIfStatement(
          condition: 'v != null && v.isNotEmpty && int.tryParse(v) == null',
          statement: 'return _form.strings.mustBeWholeNumber;',
        )
      else
        _u.inlineIfStatement(
          condition: 'int.tryParse(v) == null',
          statement: 'return _form.strings.mustBeWholeNumber;',
        ),
    ]);
    return _u.callExpression('TextFormField', [
      'controller: _${name}Controller',
      'enabled: $enabledExpr',
      'keyboardType: TextInputType.number',
      'decoration: _textDecoration(label, _form.textConfig?.$name, null)',
      'onChanged: (_) => _onFieldChanged()',
      'validator: ${_u.functionLiteral(['v'], validators)}',
    ]);
  }

  String stringRegularExpr(GLField f, String enabledExpr) {
    final name = f.name.token;
    final nullable = f.type.nullable;
    final isPassword = _types.isPasswordField(f);
    final validators = _validatorStatements(name, [
      if (!nullable) "if (v == null || v.isEmpty) return _form.strings.required;",
    ]);

    final obscureExpr = isPassword ? '_${name}Obscured' : '_form.textConfig?.$name?.obscureText ?? false';
    final suffixIconExpr = isPassword
        ? _u.callExpression('IconButton', [
            "tooltip: _${name}Obscured ? _form.strings.showPassword : _form.strings.hidePassword",
            'icon: Icon(_${name}Obscured ? Icons.visibility_off : Icons.visibility)',
            'onPressed: () => setState(() => _${name}Obscured = !_${name}Obscured)',
          ])
        : 'null';

    return _u.callExpression('TextFormField', [
      'controller: _${name}Controller',
      'enabled: $enabledExpr',
      'obscureText: $obscureExpr',
      'keyboardType: _form.textConfig?.$name?.keyboardType ?? ${_types.smartKeyboardTypeExpr(f)}',
      'textInputAction: _form.textConfig?.$name?.textInputAction ?? TextInputAction.next',
      'textCapitalization: _form.textConfig?.$name?.textCapitalization ?? TextCapitalization.none',
      'autocorrect: _form.textConfig?.$name?.autocorrect ?? ${_types.smartAutocorrect(f)}',
      'enableSuggestions: _form.textConfig?.$name?.enableSuggestions ?? ${_types.smartEnableSuggestions(f)}',
      'maxLength: _form.textConfig?.$name?.maxLength',
      'maxLines: _form.textConfig?.$name?.maxLines ?? 1',
      'decoration: _textDecoration(label, _form.textConfig?.$name, $suffixIconExpr)',
      'onChanged: (_) => _onFieldChanged()',
      'validator: ${_u.functionLiteral(['v'], validators)}',
    ]);
  }

  // ── Enum fields ───────────────────────────────────────────────────────────────

  String enumDropdownExpr(GLField f, String enabledExpr) {
    final name = f.name.token;
    final enumType = f.type.firstType.token;
    final nullable = f.type.nullable;
    final validators = _validatorStatements(name, [
      if (!nullable) "if (v == null) return _form.strings.required;",
    ]);

    return _u.callExpression('DropdownButtonFormField<$enumType?>', [
      'decoration: _decoration(label).copyWith(enabled: $enabledExpr)',
      'value: _$name',
      _u.listArg('items', [
        "DropdownMenuItem<$enumType?>(value: null, child: _form.dropdownLabels?.$name?.unselected ?? Text(_form.strings.chooseAnOption, style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor)))",
        '...$enumType.values.map((e) => DropdownMenuItem<$enumType?>(value: e, child: _form.dropdownLabels?.$name?.call(e) ?? Text(e.name)))',
      ]),
      'onChanged: $enabledExpr ? (v) => setState(() => _$name = v) : null',
      'validator: ${_u.functionLiteral(['v'], validators)}',
    ]);
  }

  String enumRowMethod(GLField f) {
    final name = f.name.token;
    final enumType = f.type.firstType.token;
    final nullable = f.type.nullable;
    final dropdownExpr = enumDropdownExpr(f, 'enabled');
    final validators = _validatorStatements(name, [
      if (!nullable) "if (v == null) return _form.strings.required;",
    ]);
    final errorText = _errorTextWidget();

    final chipsCase = 'return ${_u.callExpression('FormField<$enumType?>', [
      'initialValue: _$name',
      'autovalidateMode: AutovalidateMode.onUserInteraction',
      'validator: ${_u.functionLiteral(['v'], validators)}',
      'builder: (field) => ${_u.callExpression('Column', [
        'crossAxisAlignment: CrossAxisAlignment.start',
        _u.listArg('children', [
          'label',
          'const SizedBox(height: 4)',
          _u.callExpression('Wrap', [
            'spacing: 8',
            'children: $enumType.values.map((e) => ${_u.callExpression('ChoiceChip', [
              'key: ValueKey(e)',
              'label: _form.dropdownLabels?.$name?.call(e) ?? Text(e.name)',
              'selected: field.value == e',
              'side: field.hasError ? BorderSide(color: Theme.of(context).colorScheme.error) : null',
              'onSelected: enabled ? (on) { final v = on ? e : null; setState(() => _$name = v); field.didChange(v); } : null',
            ])}).toList()',
          ]),
          errorText,
        ]),
      ])}',
    ])};';

    final radioCase = 'return ${_u.callExpression('FormField<$enumType?>', [
      'initialValue: _$name',
      'autovalidateMode: AutovalidateMode.onUserInteraction',
      'validator: ${_u.functionLiteral(['v'], validators)}',
      'builder: (field) => ${_u.callExpression('Column', [
        'crossAxisAlignment: CrossAxisAlignment.start',
        _u.listArg('children', [
          'label',
          _u.callExpression('Semantics', [
            "label: field.hasError ? field.errorText ?? '' : null",
            'child: ${_u.callExpression('Container', [
              'decoration: field.hasError ? ${_u.callExpression('BoxDecoration', [
                'border: Border.all(color: Theme.of(context).colorScheme.error)',
                'borderRadius: BorderRadius.circular(4)',
              ])} : null',
              'child: ${_u.callExpression('Column', [
                'children: $enumType.values.map((e) => ${_u.callExpression('RadioListTile<$enumType?>', [
                  'key: ValueKey(e)',
                  'contentPadding: EdgeInsets.zero',
                  'title: _form.dropdownLabels?.$name?.call(e) ?? Text(e.name)',
                  'value: e',
                  'groupValue: field.value',
                  'onChanged: enabled ? (v) { setState(() => _$name = v); field.didChange(v); } : null',
                ])}).toList()',
              ])}',
            ])}',
          ]),
          errorText,
        ]),
      ])}',
    ])};';

    return _u.createMethod(
      returnType: 'Widget',
      methodName: '_${name}Row',
      namedArguments: false,
      arguments: ['Widget label', 'bool enabled'],
      statements: [
        _u.switchStatement(
          expression: '_form.widgets?.$name',
          cases: [
            DartCaseStatement(caseValue: 'EnumFieldWidget.chips', statement: chipsCase),
            DartCaseStatement(caseValue: 'EnumFieldWidget.radio', statement: radioCase),
          ],
          defaultStatements: ['return _field(label, $dropdownExpr);'],
        ),
      ],
    );
  }

  // ── Bool fields ───────────────────────────────────────────────────────────────

  String boolFieldExpr(GLField f, String enabledExpr) {
    final name = f.name.token;
    final nullable = f.type.nullable;

    if (nullable) {
      if (_config.nullableBooleanWidget == NullableBooleanWidget.tristate) {
        return _boolTristateDropdownExpr(f, enabledExpr);
      }
      return _checkboxFormFieldExpr(name, nullable: true, enabledExpr: enabledExpr);
    }

    if (_config.booleanWidget == BooleanWidget.tristate) return _boolTristateDropdownExpr(f, enabledExpr);
    if (_config.booleanWidget == BooleanWidget.checkbox) return _checkboxFormFieldExpr(name, nullable: false, enabledExpr: enabledExpr);
    return _switchFormFieldExpr(name, enabledExpr);
  }

  String boolRowMethod(GLField f) {
    final name = f.name.token;
    final fieldType = _types.boolStateType(f);
    final defaultReturn = _types.isTristateField(f)
        ? 'return _field(label, ${boolFieldExpr(f, 'enabled')});'
        : 'return ${boolFieldExpr(f, 'enabled')};';

    final errorText = _errorTextWidget();
    final errorBorderDecoration = 'field.hasError ? ${_u.callExpression('BoxDecoration', [
      'border: Border.all(color: Theme.of(context).colorScheme.error)',
      'borderRadius: BorderRadius.circular(4)',
    ])} : null';
    const errorContainerSemantics = "field.hasError ? field.errorText ?? '' : null";
    final validators = _validatorStatements(name, []);

    if (fieldType == 'bool?') {
      final chipsCase = 'return ${_u.callExpression('FormField<bool?>', [
        'initialValue: _$name',
        'autovalidateMode: AutovalidateMode.onUserInteraction',
        'validator: ${_u.functionLiteral(['v'], validators)}',
        'builder: (field) => ${_u.callExpression('Column', [
          'crossAxisAlignment: CrossAxisAlignment.start',
          _u.listArg('children', [
            'label',
            'const SizedBox(height: 4)',
            _u.callExpression('Wrap', [
              'spacing: 8',
              _u.listArg('children', [
                _u.callExpression('ChoiceChip', [
                  'key: const ValueKey(true)',
                  'label: tl',
                  'selected: field.value == true',
                  'side: field.hasError ? BorderSide(color: Theme.of(context).colorScheme.error) : null',
                  'onSelected: enabled ? (on) { setState(() => _$name = on ? true : null); field.didChange(on ? true : null); } : null',
                ]),
                _u.callExpression('ChoiceChip', [
                  'key: const ValueKey(false)',
                  'label: fl',
                  'selected: field.value == false',
                  'side: field.hasError ? BorderSide(color: Theme.of(context).colorScheme.error) : null',
                  'onSelected: enabled ? (on) { setState(() => _$name = on ? false : null); field.didChange(on ? false : null); } : null',
                ]),
              ]),
            ]),
            errorText,
          ]),
        ])}',
      ])};';

      final radioCase = 'return ${_u.callExpression('FormField<bool?>', [
        'initialValue: _$name',
        'autovalidateMode: AutovalidateMode.onUserInteraction',
        'validator: ${_u.functionLiteral(['v'], validators)}',
        'builder: (field) => ${_u.callExpression('Column', [
          'crossAxisAlignment: CrossAxisAlignment.start',
          _u.listArg('children', [
            'label',
            _u.callExpression('Semantics', [
              'label: $errorContainerSemantics',
              'child: ${_u.callExpression('Container', [
                'decoration: $errorBorderDecoration',
                'child: ${_u.callExpression('Column', [
                  _u.listArg('children', [
                    _u.callExpression('RadioListTile<bool?>', [
                      'key: const ValueKey(true)',
                      'contentPadding: EdgeInsets.zero',
                      'title: tl',
                      'value: true',
                      'groupValue: field.value',
                      'onChanged: enabled ? (v) { setState(() => _$name = v); field.didChange(v); } : null',
                    ]),
                    _u.callExpression('RadioListTile<bool?>', [
                      'key: const ValueKey(false)',
                      'contentPadding: EdgeInsets.zero',
                      'title: fl',
                      'value: false',
                      'groupValue: field.value',
                      'onChanged: enabled ? (v) { setState(() => _$name = v); field.didChange(v); } : null',
                    ]),
                  ]),
                ])}',
              ])}',
            ]),
            errorText,
          ]),
        ])}',
      ])};';

      return _u.createMethod(
        returnType: 'Widget',
        methodName: '_${name}Row',
        namedArguments: false,
        arguments: ['Widget label', 'bool enabled'],
        statements: [
          "final tl = _form.dropdownLabels?.$name?.trueLabel ?? Text(_form.strings.yes);",
          "final fl = _form.dropdownLabels?.$name?.falseLabel ?? Text(_form.strings.no);",
          _u.switchStatement(
            expression: '_form.widgets?.$name',
            cases: [
              DartCaseStatement(caseValue: 'BoolFieldWidget.chips', statement: chipsCase),
              DartCaseStatement(caseValue: 'BoolFieldWidget.radio', statement: radioCase),
            ],
            defaultStatements: [defaultReturn],
          ),
        ],
      );
    } else {
      final chipsCase = 'return ${_u.callExpression('FormField<bool>', [
        'initialValue: _$name',
        'autovalidateMode: AutovalidateMode.onUserInteraction',
        'validator: ${_u.functionLiteral(['v'], validators)}',
        'builder: (field) => ${_u.callExpression('Column', [
          'crossAxisAlignment: CrossAxisAlignment.start',
          _u.listArg('children', [
            'label',
            'const SizedBox(height: 4)',
            _u.callExpression('Wrap', [
              'spacing: 8',
              _u.listArg('children', [
                _u.callExpression('ChoiceChip', [
                  'key: const ValueKey(true)',
                  'label: tl',
                  'selected: field.value ?? false',
                  'side: field.hasError ? BorderSide(color: Theme.of(context).colorScheme.error) : null',
                  'onSelected: enabled ? (on) { if (on) { setState(() => _$name = true); field.didChange(true); } } : null',
                ]),
                _u.callExpression('ChoiceChip', [
                  'key: const ValueKey(false)',
                  'label: fl',
                  'selected: !(field.value ?? false)',
                  'side: field.hasError ? BorderSide(color: Theme.of(context).colorScheme.error) : null',
                  'onSelected: enabled ? (on) { if (on) { setState(() => _$name = false); field.didChange(false); } } : null',
                ]),
              ]),
            ]),
            errorText,
          ]),
        ])}',
      ])};';

      final radioCase = 'return ${_u.callExpression('FormField<bool>', [
        'initialValue: _$name',
        'autovalidateMode: AutovalidateMode.onUserInteraction',
        'validator: ${_u.functionLiteral(['v'], validators)}',
        'builder: (field) => ${_u.callExpression('Column', [
          'crossAxisAlignment: CrossAxisAlignment.start',
          _u.listArg('children', [
            'label',
            _u.callExpression('Semantics', [
              'label: $errorContainerSemantics',
              'child: ${_u.callExpression('Container', [
                'decoration: $errorBorderDecoration',
                'child: ${_u.callExpression('Column', [
                  _u.listArg('children', [
                    _u.callExpression('RadioListTile<bool>', [
                      'key: const ValueKey(true)',
                      'contentPadding: EdgeInsets.zero',
                      'title: tl',
                      'value: true',
                      'groupValue: field.value',
                      'onChanged: enabled ? (v) { setState(() => _$name = v!); field.didChange(v); } : null',
                    ]),
                    _u.callExpression('RadioListTile<bool>', [
                      'key: const ValueKey(false)',
                      'contentPadding: EdgeInsets.zero',
                      'title: fl',
                      'value: false',
                      'groupValue: field.value',
                      'onChanged: enabled ? (v) { setState(() => _$name = v!); field.didChange(v); } : null',
                    ]),
                  ]),
                ])}',
              ])}',
            ]),
            errorText,
          ]),
        ])}',
      ])};';

      return _u.createMethod(
        returnType: 'Widget',
        methodName: '_${name}Row',
        namedArguments: false,
        arguments: ['Widget label', 'bool enabled'],
        statements: [
          "final tl = _form.dropdownLabels?.$name?.trueLabel ?? Text(_form.strings.yes);",
          "final fl = _form.dropdownLabels?.$name?.falseLabel ?? Text(_form.strings.no);",
          _u.switchStatement(
            expression: '_form.widgets?.$name',
            cases: [
              DartCaseStatement(caseValue: 'BoolFieldWidget.chips', statement: chipsCase),
              DartCaseStatement(caseValue: 'BoolFieldWidget.radio', statement: radioCase),
            ],
            defaultStatements: [defaultReturn],
          ),
        ],
      );
    }
  }

  // ── List fields ───────────────────────────────────────────────────────────────

  String _listOnSelected(String name, String enabledExpr) {
    final body = _u.functionLiteral(['on'], [
      'setState(() ${_u.block([
        _u.ifStatement(
          condition: 'on',
          ifBlockStatements: ['_$name.add(e);'],
          elseBlockStatements: ['_$name.remove(e);'],
        ),
      ])});',
    ]);
    return '$enabledExpr ? $body : null';
  }

  String _listOnChanged(String name) {
    final body = _u.functionLiteral(['on'], [
      'setState(() ${_u.block([
        _u.ifStatement(
          condition: 'on == true',
          ifBlockStatements: ['_$name.add(e);'],
          elseBlockStatements: ['_$name.remove(e);'],
        ),
      ])});',
    ]);
    return body;
  }

  String enumListWidgetExpr(GLField f, String enabledExpr) {
    final name = f.name.token;
    final enumType = f.type.inlineType.firstType.token;
    if (_config.listWidget == ListWidget.checkboxes) {
      return _u.callExpression('Column', [
        'crossAxisAlignment: CrossAxisAlignment.start',
        _u.listArg('children', [
          'label',
          '...$enumType.values.map((e) => ${_u.callExpression('CheckboxListTile', [
            'contentPadding: EdgeInsets.zero',
            'enabled: $enabledExpr',
            'title: _form.dropdownLabels?.$name?.call(e) ?? Text(e.name)',
            'value: _$name.contains(e)',
            'onChanged: ${_listOnChanged(name)}',
          ])}).toList()',
        ]),
      ]);
    }
    return _u.callExpression('Column', [
      'crossAxisAlignment: CrossAxisAlignment.start',
      _u.listArg('children', [
        'label',
        'const SizedBox(height: 4)',
        _u.callExpression('Wrap', [
          'spacing: 8',
          'children: $enumType.values.map((e) => ${_u.callExpression('FilterChip', [
            'label: _form.dropdownLabels?.$name?.call(e) ?? Text(e.name)',
            'selected: _$name.contains(e)',
            'onSelected: ${_listOnSelected(name, enabledExpr)}',
          ])}).toList()',
        ]),
      ]),
    ]);
  }

  String scalarListWidgetExpr(GLField f, String enabledExpr) {
    final name = f.name.token;
    if (_config.listWidget == ListWidget.checkboxes) {
      return _u.callExpression('Column', [
        'crossAxisAlignment: CrossAxisAlignment.start',
        _u.listArg('children', [
          'label',
          '...(_form.${name}Options ?? []).map((e) => ${_u.callExpression('CheckboxListTile', [
            'contentPadding: EdgeInsets.zero',
            'enabled: $enabledExpr',
            'title: Text(e.toString())',
            'value: _$name.contains(e)',
            'onChanged: ${_listOnChanged(name)}',
          ])}).toList()',
        ]),
      ]);
    }
    return _u.callExpression('Column', [
      'crossAxisAlignment: CrossAxisAlignment.start',
      _u.listArg('children', [
        'label',
        'const SizedBox(height: 4)',
        _u.callExpression('Wrap', [
          'spacing: 8',
          'children: (_form.${name}Options ?? []).map((e) => ${_u.callExpression('FilterChip', [
            'label: Text(e.toString())',
            'selected: _$name.contains(e)',
            'onSelected: ${_listOnSelected(name, enabledExpr)}',
          ])}).toList()',
        ]),
      ]),
    ]);
  }

  // ── Private helpers ───────────────────────────────────────────────────────────

  String _switchFormFieldExpr(String name, String enabledExpr) {
    return _u.callExpression('FormField<bool>', [
      'initialValue: _$name',
      'validator: (v) { final _ctx = _buildContext(); if ((_form.visibility?.$name?.call(_ctx) ?? FieldVisibility.enabled) != FieldVisibility.enabled) return null; return _form.validations?.$name?.call(v, _ctx); }',
      'builder: (field) => ${_u.callExpression('_switchBoolField', [
        'label',
        'field.value ?? false',
        '$enabledExpr ? (v) { setState(() => _$name = v); field.didChange(v); } : null',
      ])}',
    ]);
  }

  String _checkboxFormFieldExpr(String name, {required bool nullable, required String enabledExpr}) {
    final fieldType = nullable ? 'bool?' : 'bool';
    final onChanged = nullable
        ? '$enabledExpr ? (v) { setState(() => _$name = v); field.didChange(v); } : null'
        : '$enabledExpr ? (v) { if (v != null) { setState(() => _$name = v); field.didChange(v); } } : null';
    return _u.callExpression('FormField<$fieldType>', [
      'initialValue: _$name',
      'validator: (v) { final _ctx = _buildContext(); if ((_form.visibility?.$name?.call(_ctx) ?? FieldVisibility.enabled) != FieldVisibility.enabled) return null; return _form.validations?.$name?.call(v, _ctx); }',
      'builder: (field) => ${_u.callExpression('_checkboxBoolField', [
        'label',
        'field.value',
        '$nullable',
        onChanged,
      ])}',
    ]);
  }

  String _boolTristateDropdownExpr(GLField f, String enabledExpr) {
    final name = f.name.token;
    final nullable = f.type.nullable;
    final validators = _validatorStatements(name, [
      if (!nullable) "if (v == null) return _form.strings.required;",
    ]);

    return _u.callExpression('DropdownButtonFormField<bool?>', [
      'decoration: _decoration(label).copyWith(enabled: $enabledExpr)',
      'value: _$name',
      _u.listArg('items', [
        "DropdownMenuItem<bool?>(value: null, child: _form.dropdownLabels?.$name?.unselected ?? Text(_form.strings.chooseAnOption, style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor)))",
        "DropdownMenuItem<bool?>(value: true, child: _form.dropdownLabels?.$name?.trueLabel ?? Text(_form.strings.yes))",
        "DropdownMenuItem<bool?>(value: false, child: _form.dropdownLabels?.$name?.falseLabel ?? Text(_form.strings.no))",
      ]),
      'onChanged: $enabledExpr ? (v) => setState(() => _$name = v) : null',
      'validator: ${_u.functionLiteral(['v'], validators)}',
    ]);
  }

  /// Builds the validator statement list: disabled-guard, custom checks, context-aware validation call.
  List<String> _validatorStatements(String name, List<String> checks) => [
    'final _ctx = _buildContext();',
    'if ((_form.visibility?.$name?.call(_ctx) ?? FieldVisibility.enabled) != FieldVisibility.enabled) return null;',
    ...checks,
    'return _form.validations?.$name?.call(v, _ctx);',
  ];

  String _errorTextWidget() => _u.inlineIfStatement(
        condition: 'field.errorText != null',
        statement: _u.callExpression('Semantics', [
          'liveRegion: true',
          'child: ${_u.callExpression('Padding', [
            'padding: const EdgeInsets.only(top: 4, left: 4)',
            'child: Text(field.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))',
          ])}',
        ]),
      );
}
