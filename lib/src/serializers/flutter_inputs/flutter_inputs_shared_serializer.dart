import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/serializers/flutter_api.dart';

class _Field {
  final String type;
  final String name;
  final String? defaultValue;

  const _Field(this.type, this.name, [this.defaultValue]);

  String get declaration => 'final $type $name;';

  String get parameter => defaultValue == null ? 'this.$name' : 'this.$name = $defaultValue';
}

class FlutterInputsSharedSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterApi _api;

  FlutterInputsSharedSerializer(this._u, this._config, this._api);

  String _file(List<String> imports, List<String> declarations) {
    final header = imports.isEmpty ? '' : '${imports.join('\n')}\n\n';
    return '$header${declarations.join('\n\n')}\n';
  }

  String _constClass(String name, List<_Field> fields) => _u.createClass(
        className: name,
        statements: [
          ...fields.map((f) => f.declaration),
          _u.createMethod(isConst: true, methodName: name, arguments: fields.map((f) => f.parameter).toList()),
        ],
      );

  String _simpleEnum(String name, List<String> values) => _u.createEnum(enumName: name, enumValues: values);

  String _emptyBodyMethod(String returnType, String methodName, List<String> arguments, {bool named = false}) =>
      _u.createMethod(
        returnType: returnType,
        methodName: methodName,
        arguments: arguments,
        namedArguments: named,
        statements: [],
      );

  String serializeSharedInputFormWidget() => _file([
        "import 'package:flutter/material.dart';",
      ], [
        _u.createInterface(
          className: 'InputFormWidget<T>',
          baseInterfaceNames: ['StatefulWidget'],
          statements: [
            _u.createMethod(isConst: true, methodName: 'InputFormWidget', arguments: ['super.key']),
          ],
        ),
        _u.createInterface(
          className: 'InputFormState<T>',
          baseInterfaceNames: ['State<InputFormWidget<T>>'],
          statements: [
            _u.createMethod(returnType: 'T', methodName: 'read', arguments: [], namedArguments: false),
            'bool validate() => true;',
            _emptyBodyMethod('void', 'reset', ['List<String>? fields'], named: true),
            'bool get isDirty => false;',
            'bool get isSubmitting => false;',
            _emptyBodyMethod('void', 'setSubmitting', ['bool value']),
            if (_config.persistDrafts) _emptyBodyMethod('void', 'restore', ['T value']),
          ],
        ),
      ]);

  String serializeSharedFormDraftStore() => _file([], [
        _u.createInterface(
          className: 'FormDraftStore',
          statements: [
            _u.createMethod(returnType: 'Future<String?>', methodName: 'read', arguments: ['String key'], namedArguments: false),
            _u.createMethod(
                returnType: 'Future<void>', methodName: 'write', arguments: ['String key', 'String value'], namedArguments: false),
            _u.createMethod(returnType: 'Future<void>', methodName: 'delete', arguments: ['String key'], namedArguments: false),
          ],
        ),
      ]);

  String serializeSharedInputReadException() => _file([], [
        _u.createClass(
          className: 'InputReadException',
          baseClassNames: ['Exception'],
          statements: [
            'final String message;',
            _u.createMethod(isConst: true, methodName: 'InputReadException', arguments: ['this.message'], namedArguments: false),
            _u.createMethod(
              override: true,
              returnType: 'String',
              methodName: 'toString',
              namedArguments: false,
              arguments: [],
              statements: ["return 'InputReadException: \$message';"],
            ),
          ],
        ),
      ]);

  String serializeSharedFieldWidgets() => _file([], [
        _simpleEnum('SelectWidget', ['dropdown', 'chips', 'radio']),
        _simpleEnum('BoolFieldWidget', ['chips', 'radio']),
      ]);

  String serializeSharedRequiredIndicator() => _file([], [
        _simpleEnum('RequiredIndicator', ['none', 'asterisk', 'requiredText', 'optionalText']),
      ]);

  String serializeSharedTextFieldOptions() => _file([
        "import '${_api.materialImport}';",
      ], [
        _constClass('TextFieldOptions', const [
          _Field('TextInputType', 'keyboardType', 'TextInputType.text'),
          _Field('TextInputAction', 'textInputAction', 'TextInputAction.next'),
          _Field('TextCapitalization', 'textCapitalization', 'TextCapitalization.none'),
          _Field('bool', 'autocorrect', 'true'),
          _Field('bool', 'enableSuggestions', 'true'),
          _Field('bool', 'obscureText', 'false'),
          _Field('bool?', 'clearButton'),
          _Field('int?', 'maxLength'),
          _Field('int?', 'maxLines', '1'),
          _Field('Widget?', 'prefixIcon'),
          _Field('Widget?', 'suffixIcon'),
          _Field('InputDecoration Function(InputDecoration)?', 'decoration'),
        ]),
      ]);

  String serializeSharedFormStrings() => _file([], [
        _constClass('FormStrings', const [
          _Field('String', 'required', "'Required'"),
          _Field('String', 'mustBeWholeNumber', "'Must be a whole number'"),
          _Field('String', 'mustBeNumber', "'Must be a number'"),
          _Field('String', 'invalidDate', "'Invalid date'"),
          _Field('String', 'chooseAnOption', "'Choose an option'"),
          _Field('String', 'yes', "'Yes'"),
          _Field('String', 'no', "'No'"),
          _Field('String', 'showPassword', "'Show password'"),
          _Field('String', 'hidePassword', "'Hide password'"),
          _Field('String', 'pickDate', "'Pick date'"),
          _Field('String', 'pickDateAndTime', "'Pick date & time'"),
          _Field('String', 'cancel', "'Cancel'"),
          _Field('String', 'done', "'Done'"),
          _Field('String', 'clear', "'Clear'"),
          _Field('String', 'requiredText', "'required'"),
          _Field('String', 'optionalText', "'optional'"),
        ]),
      ]);

  String serializeSharedStepperStrings() => _file([], [
        _constClass('StepperStrings', const [
          _Field('String', 'next', "'Next'"),
          _Field('String', 'back', "'Back'"),
          _Field('String', 'submit', "'Submit'"),
        ]),
      ]);

  String serializeSharedDateInputConfig() => _file([], [
        _simpleEnum('DateType', ['date', 'dateTime']),
        _simpleEnum('DateInputMode', ['dialog', 'inline']),
        _constClass('DateInputConfig', [
          const _Field('DateType', 'type', 'DateType.date'),
          _Field('DateInputMode', 'mode', 'DateInputMode.${_config.defaultDateMode.name}'),
          _Field('String', 'pattern', "'${_config.defaultDatePattern}'"),
          const _Field('bool', 'allowKeyboardInput', 'true'),
          const _Field('bool?', 'useCupertino'),
          const _Field('DateTime?', 'firstDate'),
          const _Field('DateTime?', 'lastDate'),
          const _Field('DateTime?', 'initialDate'),
        ]),
      ]);

  String serializeSharedDateInputFormatter() => _file([
        "import 'package:flutter/services.dart';",
      ], [
        _u.createClass(
          className: 'DateInputFormatter',
          extendsClassName: 'TextInputFormatter',
          statements: [
            'final String pattern;',
            _u.createMethod(isConst: true, methodName: 'DateInputFormatter', arguments: ['this.pattern'], namedArguments: false),
            "static const _digitChars = {'y', 'M', 'd', 'H', 'h', 'm', 's'};",
            _u.createMethod(
              override: true,
              returnType: 'TextEditingValue',
              methodName: 'formatEditUpdate',
              namedArguments: false,
              arguments: ['TextEditingValue oldValue', 'TextEditingValue newValue'],
              statements: [
                _u.constDecl("digits", "newValue.text.replaceAll(RegExp(r'[^0-9]'), '')"),
                'var digitIdx = 0;',
                _u.constDecl('buffer', 'StringBuffer()'),
                _u.forEachLoop(
                  variable: 'char',
                  iterable: "pattern.split('')",
                  statements: [
                    _u.inlineIfStatement(condition: 'digitIdx >= digits.length', statement: 'break;'),
                    _u.ifStatement(
                      condition: '_digitChars.contains(char)',
                      ifBlockStatements: ['buffer.write(digits[digitIdx++]);'],
                      elseBlockStatements: [
                        _u.inlineIfStatement(condition: 'digitIdx < digits.length', statement: 'buffer.write(char);'),
                      ],
                    ),
                  ],
                ),
                _u.constDecl('text', 'buffer.toString()'),
                'return ${_u.callExpression('newValue.copyWith', [
                  'text: text',
                  'selection: TextSelection.collapsed(offset: text.length)',
                ])};',
              ],
            ),
          ],
        ),
      ]);

  String serializeSharedFieldVisibility() => _file([], [
        _simpleEnum('FieldVisibility', ['enabled', 'disabled', 'hidden']),
      ]);

  String serializeSharedSimpleFieldForm() => _file([
        "import 'input_form_widget.dart';",
        "import 'package:flutter/widgets.dart';",
      ], [
        _u.createClass(
          className: 'SimpleFieldForm<T>',
          extendsClassName: 'InputFormWidget<T>',
          statements: [
            'final T Function() reader;',
            'final Widget Function(BuildContext) builder;',
            _u.createMethod(
              isConst: true,
              methodName: 'SimpleFieldForm',
              arguments: ['required this.reader', 'required this.builder', 'super.key'],
            ),
            _u.createMethod(
              override: true,
              returnType: 'State<InputFormWidget<T>>',
              methodName: 'createState',
              namedArguments: false,
              arguments: [],
              statements: ['return _SimpleFieldFormState<T>();'],
            ),
          ],
        ),
        _u.createClass(
          className: '_SimpleFieldFormState<T>',
          extendsClassName: 'InputFormState<T>',
          statements: [
            _u.createMethod(
              override: true,
              returnType: 'T',
              methodName: 'read',
              namedArguments: false,
              arguments: [],
              statements: ['return (widget as SimpleFieldForm<T>).reader();'],
            ),
            _u.createMethod(
              override: true,
              returnType: 'Widget',
              methodName: 'build',
              namedArguments: false,
              arguments: ['BuildContext context'],
              statements: ['return (widget as SimpleFieldForm<T>).builder(context);'],
            ),
          ],
        ),
      ]);

  String serializeSharedInputStepOptions() => _file([
        "import 'package:flutter/widgets.dart';",
      ], [
        _constClass('InputStepOptions', const [
          _Field('Widget?', 'title'),
          _Field('Widget?', 'subtitle'),
        ]),
      ]);

  String serializeSharedInputStepGroup() => _file([
        "import 'package:flutter/widgets.dart';",
      ], [
        _u.createClass(
          className: 'InputStepGroup',
          statements: [
            'final List<String> fields;',
            'final Widget? title;',
            'final Widget? subtitle;',
            _u.createMethod(
              isConst: true,
              methodName: 'InputStepGroup',
              arguments: ['required this.fields', 'this.title', 'this.subtitle'],
            ),
          ],
        ),
      ]);

  String serializeSharedSelectFieldConfig() => _file([
        "import 'package:flutter/widgets.dart';",
        "import 'field_widgets.dart';",
      ], [
        _u.createClass(
          className: 'SelectFieldConfig<T>',
          statements: [
            'final List<T> options;',
            'final SelectWidget widget;',
            'final Widget Function(T)? labelBuilder;',
            _u.createMethod(
              isConst: true,
              methodName: 'SelectFieldConfig',
              arguments: ['required this.options', 'this.widget = SelectWidget.dropdown', 'this.labelBuilder'],
            ),
          ],
        ),
      ]);

  String serializeSharedBooleanLabels() => _file([
        "import 'package:flutter/widgets.dart';",
      ], [
        _constClass('BooleanLabels', const [
          _Field('Widget', 'unselected', "const Text('Choose an option')"),
          _Field('Widget', 'trueLabel', "const Text('Yes')"),
          _Field('Widget', 'falseLabel', "const Text('No')"),
        ]),
      ]);
}
