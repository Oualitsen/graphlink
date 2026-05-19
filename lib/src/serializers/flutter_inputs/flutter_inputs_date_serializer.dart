import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_field_serializer.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsDateSerializer {
  final DartCodeGenUtils _u;
  final FlutterInputsTypeHelpers _types;
  final FlutterInputsFieldSerializer _fields;

  FlutterInputsDateSerializer(this._u, this._types, this._fields);

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
          'final current = controller.text.isEmpty ? null : () { try { return DateFormat(config.pattern).parse(controller.text); } catch (_) { return null; } }();',
          'final first = config.firstDate ?? DateTime(1900);',
          'final last = config.lastDate ?? DateTime(2100);',
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
          'final current = controller.text.isEmpty ? null : () { try { return DateFormat(config.pattern).parse(controller.text); } catch (_) { return null; } }();',
          'final first = config.firstDate ?? DateTime(1900);',
          'final last = config.lastDate ?? DateTime(2100);',
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
          'try { return DateFormat(config.pattern).parse(text).millisecondsSinceEpoch; } catch (_) { return null; }',
        ],
      );

  // ── Per-field date row method ─────────────────────────────────────────────────

  String dateRowMethod(GLField f) {
    final name = f.name.token;
    final nullable = f.type.nullable;
    final isInt = _types.dartScalarType(f) == 'int';

    final regularExpr = isInt ? _fields.intRegularExpr(f, 'enabled') : _fields.stringRegularExpr(f, 'enabled');

    final dateValidators = <String>[
      'final _ctx = _buildContext();',
      'if ((_form.visibility?.$name?.call(_ctx) ?? FieldVisibility.enabled) != FieldVisibility.enabled) return null;',
      if (!nullable) "if (v == null || v.isEmpty) return _form.strings.required;",
      "try { DateFormat(_form.dateConfig!.$name!.pattern).parse(v${nullable ? " ?? ''" : '!'}); } catch (_) { return _form.strings.invalidDate; }",
      'return _form.validations?.$name?.call(v, _ctx);',
    ];

    final dialogField = _u.callExpression('TextFormField', [
      'controller: _${name}Controller',
      'enabled: enabled',
      'readOnly: !(_form.dateConfig!.$name!.allowKeyboardInput)',
      'keyboardType: _form.dateConfig!.$name!.allowKeyboardInput ? TextInputType.datetime : TextInputType.none',
      'inputFormatters: _form.dateConfig!.$name!.allowKeyboardInput ? [DateInputFormatter(_form.dateConfig!.$name!.pattern)] : const []',
      'onTap: _form.dateConfig!.$name!.allowKeyboardInput ? null : () => _pickDate(_${name}Controller, _form.dateConfig!.$name!)',
      'decoration: _textDecoration(label, null, ${_u.callExpression('IconButton', [
        "tooltip: _form.dateConfig!.$name!.type == DateType.dateTime ? _form.strings.pickDateAndTime : _form.strings.pickDate",
        'icon: const Icon(Icons.calendar_today_outlined)',
        'onPressed: enabled ? () => _pickDate(_${name}Controller, _form.dateConfig!.$name!) : null',
      ])})',
      'validator: ${_u.functionLiteral(['v'], dateValidators)}',
    ]);

    final errorText = _u.inlineIfStatement(
      condition: 'field.errorText != null',
      statement: _u.callExpression('Semantics', [
        'liveRegion: true',
        'child: ${_u.callExpression('Padding', [
          'padding: const EdgeInsets.only(top: 4, left: 4)',
          'child: Text(field.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))',
        ])}',
      ]),
    );

    final initialDateExpr =
        '_clampDate(_${name}Controller.text.isEmpty ? (_form.dateConfig!.$name!.initialDate ?? DateTime.now()) : (() { try { return DateFormat(_form.dateConfig!.$name!.pattern).parse(_${name}Controller.text); } catch (_) { return DateTime.now(); } }()), _form.dateConfig!.$name!.firstDate ?? DateTime(1900), _form.dateConfig!.$name!.lastDate ?? DateTime(2100))';

    final onCupertinoDateTimeChanged =
        '(dt) => setState(() { '
        '_${name}Controller.text = DateFormat(_form.dateConfig!.$name!.pattern).format(dt); '
        'field.didChange(_${name}Controller.text); '
        '})';

    final cupertinoCalendar = _u.callExpression('SizedBox', [
      'height: 220',
      'child: ${_u.callExpression('CupertinoDatePicker', [
        'mode: _form.dateConfig!.$name!.type == DateType.dateTime ? CupertinoDatePickerMode.dateAndTime : CupertinoDatePickerMode.date',
        'initialDateTime: $initialDateExpr',
        'minimumDate: _form.dateConfig!.$name!.firstDate ?? DateTime(1900)',
        'maximumDate: _form.dateConfig!.$name!.lastDate ?? DateTime(2100)',
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
      'initialDate: $initialDateExpr',
      'firstDate: _form.dateConfig!.$name!.firstDate ?? DateTime(1900)',
      'lastDate: _form.dateConfig!.$name!.lastDate ?? DateTime(2100)',
      'onDateChanged: $onMaterialDateChanged',
    ]);

    final inlineField = _u.callExpression('FormField<String>', [
      'initialValue: _${name}Controller.text',
      'autovalidateMode: AutovalidateMode.onUserInteraction',
      'validator: ${_u.functionLiteral(['v'], dateValidators)}',
      'builder: (field) => ${_u.callExpression('Column', [
        'crossAxisAlignment: CrossAxisAlignment.start',
        _u.listArg('children', [
          _u.callExpression('InkWell', [
            'onTap: enabled ? () => setState(() => _${name}CalendarOpen = !_${name}CalendarOpen) : null',
            'child: ${_u.callExpression('InputDecorator', [
              'decoration: _decoration(label).copyWith(errorText: field.errorText, suffixIcon: Icon(_${name}CalendarOpen ? Icons.keyboard_arrow_up_outlined : Icons.calendar_today_outlined))',
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
      ])}',
    ]);

    return _u.createMethod(
      returnType: 'Widget',
      methodName: '_${name}DateRow',
      namedArguments: false,
      arguments: ['Widget label', 'bool enabled'],
      statements: [
        'final config = _form.dateConfig?.$name;',
        _u.ifStatement(
          condition: 'config == null',
          ifBlockStatements: ['return _field(label, $regularExpr);'],
        ),
        _u.ifStatement(
          condition: 'config!.mode == DateInputMode.inline',
          ifBlockStatements: ['return $inlineField;'],
        ),
        'return _field(label, $dialogField);',
      ],
    );
  }
}
