import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_field_serializer.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsDateSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterInputsTypeHelpers _types;
  final FlutterInputsFieldSerializer _fields;

  FlutterInputsDateSerializer(this._u, this._config, this._types, this._fields);

  // ── Generated helper methods (go into the state class) ────────────────────────

  String clampDateHelper() => _u.createMethod(
        returnType: 'DateTime',
        methodName: '_clampDate',
        namedArguments: false,
        arguments: ['DateTime date', 'DateTime first', 'DateTime last'],
        statements: [
          _u.inlineIfStatement(condition: 'date.isBefore(first)', statement: 'return first;'),
          _u.inlineIfStatement(condition: 'date.isAfter(last)', statement: 'return last;'),
          'return date;',
        ],
      );

  String isCupertinoHelper() => _u.createMethod(
        returnType: 'bool',
        methodName: '_isCupertino',
        namedArguments: false,
        arguments: ['DateInputConfig config'],
        statements: [
          'return config.useCupertino ?? (Theme.of(context).platform == TargetPlatform.iOS || Theme.of(context).platform == TargetPlatform.macOS);',
        ],
      );

  String pickDateHelper() => _u.createMethod(
        returnType: 'Future<void>',
        methodName: '_pickDate',
        namedArguments: false,
        async: true,
        arguments: ['TextEditingController controller', 'DateInputConfig config'],
        statements: [
          _u.ifStatement(
            condition: '_isCupertino(config)',
            ifBlockStatements: ['await _pickDateCupertino(controller, config);'],
            elseBlockStatements: ['await _pickDateMaterial(controller, config);'],
          ),
        ],
      );

  String pickDateMaterialHelper() => _u.createMethod(
        returnType: 'Future<void>',
        methodName: '_pickDateMaterial',
        namedArguments: false,
        async: true,
        arguments: ['TextEditingController controller', 'DateInputConfig config'],
        statements: [
          'DateTime? current;',
          _u.tryCatchFinally(
            tryStatements: ['current = controller.text.isEmpty ? null : DateFormat(config.pattern).parse(controller.text);'],
            catchVariable: '_',
            catchStatements: ['current = null;'],
          ),
          'final first = config.firstDate ?? DateTime(${_config.defaultDateFirstYear});',
          'final last = config.lastDate ?? DateTime(${_config.defaultDateLastYear});',
          'final initial = _clampDate(current ?? config.initialDate ?? DateTime.now(), first, last);',
          'DateTime? picked;',
          _u.ifStatement(
            condition: 'config.type == DateType.dateTime',
            ifBlockStatements: [
              'final date = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);',
              _u.inlineIfStatement(condition: 'date == null || !mounted', statement: 'return;'),
              'final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));',
              _u.inlineIfStatement(condition: 'time == null', statement: 'return;'),
              'picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);',
            ],
            elseBlockStatements: [
              'picked = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);',
            ],
          ),
          _u.inlineIfStatement(
              condition: 'picked != null',
              statement: 'setState(() => controller.text = DateFormat(config.pattern).format(picked!));'),
        ],
      );

  String pickDateCupertinoHelper() => _u.createMethod(
        returnType: 'Future<void>',
        methodName: '_pickDateCupertino',
        namedArguments: false,
        async: true,
        arguments: ['TextEditingController controller', 'DateInputConfig config'],
        statements: [
          'DateTime? current;',
          _u.tryCatchFinally(
            tryStatements: ['current = controller.text.isEmpty ? null : DateFormat(config.pattern).parse(controller.text);'],
            catchVariable: '_',
            catchStatements: ['current = null;'],
          ),
          'final first = config.firstDate ?? DateTime(${_config.defaultDateFirstYear});',
          'final last = config.lastDate ?? DateTime(${_config.defaultDateLastYear});',
          'DateTime picked = _clampDate(current ?? config.initialDate ?? DateTime.now(), first, last);',
          'final result = await ${_u.callExpression('showCupertinoModalPopup<DateTime?>', [
            'context: context',
            'builder: (ctx) => ${_u.callExpression('Container', [
              'height: 320',
              'color: CupertinoTheme.of(ctx).scaffoldBackgroundColor',
              'child: ${_u.callExpression('Column', [
                _u.listArg('children', [
                  _u.callExpression('Row', [
                    'mainAxisAlignment: MainAxisAlignment.spaceBetween',
                    _u.listArg('children', [
                      _u.callExpression('CupertinoButton', [
                        'child: Text(_form.strings.cancel)',
                        'onPressed: () => Navigator.pop(ctx, null)',
                      ]),
                      _u.callExpression('CupertinoButton', [
                        'child: Text(_form.strings.done)',
                        'onPressed: () => Navigator.pop(ctx, picked)',
                      ]),
                    ]),
                  ]),
                  _u.callExpression('Expanded', [
                    'child: ${_u.callExpression('CupertinoDatePicker', [
                      'mode: config.type == DateType.dateTime ? CupertinoDatePickerMode.dateAndTime : CupertinoDatePickerMode.date',
                      'initialDateTime: picked',
                      'minimumDate: first',
                      'maximumDate: last',
                      'onDateTimeChanged: (dt) => picked = dt',
                    ])}',
                  ]),
                ]),
              ])}',
            ])}',
          ])};',
          _u.inlineIfStatement(condition: 'result == null || !mounted', statement: 'return;'),
          'setState(() => controller.text = DateFormat(config.pattern).format(result));',
        ],
      );

  String parseDateHelper() => _u.createMethod(
        returnType: 'int?',
        methodName: '_parseDate',
        namedArguments: false,
        arguments: ['String text', 'DateInputConfig config'],
        statements: [
          _u.inlineIfStatement(condition: 'text.isEmpty', statement: 'return null;'),
          _u.tryCatchFinally(
            tryStatements: ['return DateFormat(config.pattern).parse(text).millisecondsSinceEpoch;'],
            catchVariable: '_',
            catchStatements: ['return null;'],
          ),
        ],
      );

  // ── Per-field scalar row method (select → date → plain text) ─────────────────

  String scalarRowMethod(GLField f) {
    final name = f.codeName;
    final nullable = f.type.nullable;
    final dartType = _types.dartScalarType(f);
    final isDateEligible = dartType == 'int' || dartType == 'String';
    final isInt = dartType == 'int';

    // --- Select widget expressions ---
    final selectValidators = [
      'final _ctx = _buildContext();',
      'if ((_form.visibility?.$name?.call(_ctx) ?? FieldVisibility.enabled) != FieldVisibility.enabled) return null;',
      if (!nullable) "if (v == null || v.isEmpty) return _form.strings.required;",
      'return _${name}AsyncError;',
    ];
    final errorText = _fields.errorTextWidget();
    final errorBorderDecoration = 'field.hasError ? ${_u.callExpression('BoxDecoration', [
      'border: Border.all(color: Theme.of(context).colorScheme.error)',
      'borderRadius: BorderRadius.circular(4)',
    ])} : null';

    final selectChipsCase = 'return ${_u.callExpression('FormField<String>', [
      'key: _${name}FieldKey',
      'initialValue: _${name}Controller.text',
      'autovalidateMode: AutovalidateMode.onUserInteraction',
      'validator: ${_u.functionLiteral(['v'], selectValidators)}',
      'builder: (field) => ${_u.callExpression('Column', [
        'crossAxisAlignment: CrossAxisAlignment.start',
        _u.listArg('children', [
          'label',
          'const SizedBox(height: 4)',
          _u.callExpression('Wrap', [
            'spacing: 8',
            'children: _selectCfg.options.map((e) => ${_u.callExpression('ChoiceChip', [
              'label: _selectCfg.labelBuilder?.call(e) ?? Text(e.toString())',
              'selected: _${name}Controller.text == e.toString()',
              'side: field.hasError ? BorderSide(color: Theme.of(context).colorScheme.error) : null',
              'onSelected: enabled ? (on) { final v = on ? e.toString() : \'\'; setState(() => _${name}Controller.text = v); field.didChange(v); } : null',
            ])}).toList()',
          ]),
          errorText,
        ]),
      ])}',
    ])};';

    final selectRadioCase = 'return ${_u.callExpression('FormField<String>', [
      'key: _${name}FieldKey',
      'initialValue: _${name}Controller.text',
      'autovalidateMode: AutovalidateMode.onUserInteraction',
      'validator: ${_u.functionLiteral(['v'], selectValidators)}',
      'builder: (field) => ${_u.callExpression('Column', [
        'crossAxisAlignment: CrossAxisAlignment.start',
        _u.listArg('children', [
          'label',
          _u.callExpression('Semantics', [
            "label: field.hasError ? field.errorText ?? '' : null",
            'child: ${_u.callExpression('Container', [
              'decoration: $errorBorderDecoration',
              'child: ${_u.callExpression('Column', [
                'children: _selectCfg.options.map((e) => ${_u.callExpression('RadioListTile<String>', [
                  'contentPadding: EdgeInsets.zero',
                  'title: _selectCfg.labelBuilder?.call(e) ?? Text(e.toString())',
                  'value: e.toString()',
                  'groupValue: _${name}Controller.text.isEmpty ? null : _${name}Controller.text',
                  'onChanged: enabled ? (v) { setState(() => _${name}Controller.text = v ?? \'\'); field.didChange(v ?? \'\'); } : null',
                ])}).toList()',
              ])}',
            ])}',
          ]),
          errorText,
        ]),
      ])}',
    ])};';

    final selectDropdownExpr = _u.callExpression('DropdownButtonFormField<String?>', [
      'key: _${name}FieldKey',
      'decoration: _decoration(label).copyWith(enabled: enabled, prefixIcon: _form.fieldIcons?.$name)',
      'value: _${name}Controller.text.isEmpty ? null : _${name}Controller.text',
      _u.listArg('items', [
        "DropdownMenuItem<String?>(value: null, child: Text(_form.strings.chooseAnOption, style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor)))",
        '..._selectCfg.options.map((e) => DropdownMenuItem<String?>(value: e.toString(), child: _selectCfg.labelBuilder?.call(e) ?? Text(e.toString())))',
      ]),
      'onChanged: enabled ? (v) => setState(() => _${name}Controller.text = v ?? \'\') : null',
      'validator: ${_u.functionLiteral(['v'], selectValidators)}',
    ]);

    final selectBlock = _u.switchStatement(
      expression: '_selectCfg.widget',
      cases: [
        DartCaseStatement(caseValue: 'SelectWidget.chips', statement: selectChipsCase),
        DartCaseStatement(caseValue: 'SelectWidget.radio', statement: selectRadioCase),
      ],
      defaultStatements: ['return _field(label, $selectDropdownExpr);'],
    );

    // --- Body: select → date (int/String only) → plain ---
    final statements = <String>[
      'final _selectCfg = _form.selectConfig?.$name;',
      _u.ifStatement(condition: '_selectCfg != null', ifBlockStatements: [selectBlock]),
    ];

    if (!isDateEligible) {
      // double / other scalar — no date branch
      statements.add('return _field(label, ${_fields.textFormFieldExpr(f, 'enabled')});');
      return _u.createMethod(
        returnType: 'Widget',
        methodName: '_${name}ScalarRow',
        namedArguments: false,
        arguments: ['Widget label', 'bool enabled'],
        statements: statements,
      );
    }

    // Date branch (int / String fields) — same logic as the old dateRowMethod
    final regularExpr = isInt ? _fields.intRegularExpr(f, 'enabled') : _fields.stringRegularExpr(f, 'enabled');

    final dateValidators = <String>[
      'final _ctx = _buildContext();',
      'if ((_form.visibility?.$name?.call(_ctx) ?? FieldVisibility.enabled) != FieldVisibility.enabled) return null;',
      if (!nullable)
        _u.inlineIfStatement(condition: 'v == null || v.isEmpty', statement: 'return _form.strings.required;'),
      if (nullable)
        _u.inlineIfStatement(condition: 'v == null || v.isEmpty', statement: 'return null;'),
      _u.tryCatchFinally(
        tryStatements: ["DateFormat(_form.dateConfig!.$name!.pattern).parse(v);"],
        catchVariable: '_',
        catchStatements: ['return _form.strings.invalidDate;'],
      ),
      'return _${name}AsyncError;',
    ];

    final dialogField = _u.callExpression('TextFormField', [
      'key: _${name}FieldKey',
      'controller: _${name}Controller',
      'enabled: enabled',
      'readOnly: !(_form.dateConfig!.$name!.allowKeyboardInput)',
      'keyboardType: _form.dateConfig!.$name!.allowKeyboardInput ? TextInputType.datetime : TextInputType.none',
      'inputFormatters: _form.dateConfig!.$name!.allowKeyboardInput ? [DateInputFormatter(_form.dateConfig!.$name!.pattern)] : const []',
      'onTap: _form.dateConfig!.$name!.allowKeyboardInput ? null : () => _pickDate(_${name}Controller, _form.dateConfig!.$name!)',
      'onChanged: (_) => _onFieldChanged()',
      'decoration: _textDecoration(label, null, ${_u.callExpression('IconButton', [
        "tooltip: _form.dateConfig!.$name!.type == DateType.dateTime ? _form.strings.pickDateAndTime : _form.strings.pickDate",
        'icon: const Icon(Icons.calendar_today_outlined)',
        'onPressed: enabled ? () => _pickDate(_${name}Controller, _form.dateConfig!.$name!) : null',
      ])}, _form.fieldIcons?.$name)',
      'validator: ${_u.functionLiteral(['v'], dateValidators)}',
    ]);

    // errorText is already declared above for the select branch (identical content)
    const parsedDateDecl = 'DateTime? _parsedDate;';
    final parsedDateInit = _u.tryCatchFinally(
      tryStatements: [
        '_parsedDate = _${name}Controller.text.isEmpty ? null : DateFormat(_form.dateConfig!.$name!.pattern).parse(_${name}Controller.text);',
      ],
      catchVariable: '_',
      catchStatements: ['_parsedDate = null;'],
    );
    final initialDateLocal =
        'final _initialDate = _clampDate(_parsedDate ?? _form.dateConfig!.$name!.initialDate ?? DateTime.now(), _form.dateConfig!.$name!.firstDate ?? DateTime(${_config.defaultDateFirstYear}), _form.dateConfig!.$name!.lastDate ?? DateTime(${_config.defaultDateLastYear}));';

    final onCupertinoDateTimeChanged =
        '(dt) => setState(() { '
        '_${name}Controller.text = DateFormat(_form.dateConfig!.$name!.pattern).format(dt); '
        'field.didChange(_${name}Controller.text); '
        '})';

    final cupertinoCalendar = _u.callExpression('SizedBox', [
      'height: 220',
      'child: ${_u.callExpression('CupertinoDatePicker', [
        'mode: _form.dateConfig!.$name!.type == DateType.dateTime ? CupertinoDatePickerMode.dateAndTime : CupertinoDatePickerMode.date',
        'initialDateTime: _initialDate',
        'minimumDate: _form.dateConfig!.$name!.firstDate ?? DateTime(${_config.defaultDateFirstYear})',
        'maximumDate: _form.dateConfig!.$name!.lastDate ?? DateTime(${_config.defaultDateLastYear})',
        'onDateTimeChanged: $onCupertinoDateTimeChanged',
      ])}',
    ]);

    final onMaterialDateChanged =
        '(dt) async { '
        'DateTime picked = dt; '
        'if (_form.dateConfig!.$name!.type == DateType.dateTime && mounted) { '
        'final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dt)); '
        'if (time != null) picked = DateTime(dt.year, dt.month, dt.day, time.hour, time.minute); '
        '} '
        'setState(() { '
        '_${name}CalendarOpen = false; '
        '_${name}Controller.text = DateFormat(_form.dateConfig!.$name!.pattern).format(picked); '
        'field.didChange(_${name}Controller.text); '
        '}); '
        '}';

    final materialCalendar = _u.callExpression('CalendarDatePicker', [
      'initialDate: _initialDate',
      'firstDate: _form.dateConfig!.$name!.firstDate ?? DateTime(${_config.defaultDateFirstYear})',
      'lastDate: _form.dateConfig!.$name!.lastDate ?? DateTime(${_config.defaultDateLastYear})',
      'onDateChanged: $onMaterialDateChanged',
    ]);

    final inlineField = _u.callExpression('FormField<String>', [
      'key: _${name}FieldKey',
      'initialValue: _${name}Controller.text',
      'autovalidateMode: AutovalidateMode.onUserInteraction',
      'validator: ${_u.functionLiteral(['v'], dateValidators)}',
      'builder: ${_u.functionLiteral(['field'], [
        parsedDateDecl,
        parsedDateInit,
        initialDateLocal,
        'return ${_u.callExpression('Column', [
          'crossAxisAlignment: CrossAxisAlignment.start',
          _u.listArg('children', [
            _u.callExpression('InkWell', [
              'onTap: enabled ? () => setState(() => _${name}CalendarOpen = !_${name}CalendarOpen) : null',
              'child: ${_u.callExpression('InputDecorator', [
                'decoration: _decoration(label).copyWith(errorText: field.errorText, prefixIcon: _form.fieldIcons?.$name, suffixIcon: Icon(_${name}CalendarOpen ? Icons.keyboard_arrow_up_outlined : Icons.calendar_today_outlined))',
                'child: Text(_${name}Controller.text.isEmpty ? \'\' : _${name}Controller.text)',
              ])}',
            ]),
            _u.callExpression('Visibility', [
              'visible: _${name}CalendarOpen',
              'maintainState: false',
              'child: _isCupertino(_form.dateConfig!.$name!) ? $cupertinoCalendar : $materialCalendar',
            ]),
            errorText,
          ]),
        ])};',
      ])}',
    ]);

    statements.addAll([
      'final config = _form.dateConfig?.$name;',
      _u.ifStatement(
        condition: 'config == null',
        ifBlockStatements: ['return _field(label, $regularExpr);'],
      ),
      _u.ifStatement(
        condition: 'config.mode == DateInputMode.inline',
        ifBlockStatements: ['return $inlineField;'],
      ),
      'return _field(label, $dialogField);',
    ]);

    return _u.createMethod(
      returnType: 'Widget',
      methodName: '_${name}ScalarRow',
      namedArguments: false,
      arguments: ['Widget label', 'bool enabled'],
      statements: statements,
    );
  }
}
