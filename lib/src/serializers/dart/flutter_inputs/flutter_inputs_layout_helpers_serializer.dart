import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsLayoutHelpersSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterInputsTypeHelpers _types;

  FlutterInputsLayoutHelpersSerializer(this._u, this._config, this._types);

  String requiredLabelHelper(String inputName) => _u.createMethod(
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

  String labelWithInfoHelper(String inputName) => _u.createMethod(
        returnType: 'Widget',
        methodName: '_labelWithInfo',
        namedArguments: false,
        arguments: ['Widget label', 'String? info'],
        statements: [
          _u.inlineIfStatement(condition: 'info == null', statement: 'return label;'),
          _u.inlineIfStatement(
            condition: '_form.labelPosition == ${inputName}LabelPosition.floatingLabel',
            statement: 'return label;',
          ),
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

  String withFloatingInfoHelper(String inputName) => _u.createMethod(
        returnType: 'Widget',
        methodName: '_withFloatingInfo',
        namedArguments: false,
        arguments: ['Widget field', 'String? info'],
        statements: [
          _u.inlineIfStatement(
            condition: 'info == null || _form.labelPosition != ${inputName}LabelPosition.floatingLabel',
            statement: 'return field;',
          ),
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

  String fieldHelper(String inputName) => _u.createMethod(
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

  String switchBoolFieldHelper(String inputName) => _u.createMethod(
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

  String checkboxBoolFieldHelper(String inputName) => _u.createMethod(
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

  String decorationHelper(String inputName) => _u.createMethod(
        returnType: 'InputDecoration',
        methodName: '_decoration',
        namedArguments: false,
        arguments: ['Widget label'],
        statements: [
          'return ${_u.ternaryOp(condition: '_form.labelPosition == ${inputName}LabelPosition.floatingLabel', positiveStatement: 'InputDecoration(label: label)', negativeStatement: 'const InputDecoration()')};',
        ],
      );

  String textDecorationHelper(String inputName) => _u.createMethod(
        returnType: 'InputDecoration',
        methodName: '_textDecoration',
        namedArguments: false,
        arguments: ['Widget label', 'TextFieldOptions? opts', 'Widget? suffixIcon', '[Widget? prefixIcon, TextEditingController? clearController]'],
        statements: [
          'var d = _decoration(label);',
          _u.constDecl('pi', 'prefixIcon ?? opts?.prefixIcon'),
          _u.inlineIfStatement(condition: 'pi != null', statement: 'd = d.copyWith(prefixIcon: pi);'),
          _u.constDecl('si', 'suffixIcon ?? opts?.suffixIcon'),
          _u.constDecl('clear', 'clearController != null && (opts?.clearButton ?? ${_config.defaultClearButton}) ? _clearButton(clearController) : null'),
          _u.constDecl('suffix', 'clear == null ? si : si == null ? clear : ${_u.callExpression('Row', [
            'mainAxisSize: MainAxisSize.min',
            _u.listArg('children', ['clear', 'si']),
          ])}'),
          _u.inlineIfStatement(condition: 'suffix != null', statement: 'd = d.copyWith(suffixIcon: suffix);'),
          'return opts?.decoration?.call(d) ?? d;',
        ],
      );

  String clearButtonHelper() => _u.createMethod(
        returnType: 'Widget',
        methodName: '_clearButton',
        namedArguments: false,
        arguments: ['TextEditingController controller'],
        statements: [
          'return ${_u.callExpression('ValueListenableBuilder<TextEditingValue>', [
            'valueListenable: controller',
            'builder: (_, value, __) => value.text.isEmpty ? const SizedBox.shrink() : ${_u.callExpression('IconButton', [
              'tooltip: _form.strings.clear',
              'icon: const Icon(Icons.clear)',
              'onPressed: () { controller.clear(); _onFieldChanged(); }',
            ])}',
          ])};',
        ],
      );

  String intersperseHelper() => _u.createMethod(
        returnType: 'List<Widget>',
        methodName: '_intersperse',
        namedArguments: false,
        arguments: ['List<Widget> widgets', 'double gap'],
        statements: [
          _u.inlineIfStatement(condition: 'widgets.isEmpty', statement: 'return [];'),
          _u.constDecl('result', '<Widget>[]'),
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

  // _field is used by: text fields, enum fields, tristate bool, date fields, and input list fields (catch-all).
  bool needsFieldHelper(List<GLField> textFields, List<GLField> enumFields,
      List<GLField> boolFields, List<GLField> inputListFields) =>
      textFields.isNotEmpty ||
      enumFields.isNotEmpty ||
      boolFields.any(_types.isTristateField) ||
      inputListFields.isNotEmpty;

  // _decoration is used by: text fields (via _textDecoration), enum dropdowns, tristate bool, date fields.
  bool needsDecorationHelper(
      List<GLField> textFields, List<GLField> enumFields, List<GLField> boolFields) =>
      textFields.isNotEmpty ||
      enumFields.isNotEmpty ||
      boolFields.any(_types.isTristateField);
}
