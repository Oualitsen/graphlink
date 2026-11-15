import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_field.dart';

class FlutterInputsNumberSerializer {
  final DartCodeGenUtils _u;

  FlutterInputsNumberSerializer(this._u);

  static const hintDuration = 'const Duration(seconds: 2)';

  List<String> stateVarDecls(List<GLField> numberFields) => [
        for (final f in numberFields) ...[
          'String? _${f.codeName}Hint;',
          'Timer? _${f.codeName}HintTimer;',
        ],
      ];

  List<String> disposeStatements(List<GLField> numberFields) =>
      numberFields.map((f) => '_${f.codeName}HintTimer?.cancel();').toList();

  List<String> stateMembers(List<GLField> numberFields) => [
        for (final f in numberFields) ...[
          configGetter(f),
          flashHintMethod(f),
        ],
      ];

  String configGetter(GLField f) =>
      'NumberInputConfig get _${f.codeName}Number => _form.numberConfig?.${f.codeName} ?? const NumberInputConfig();';

  String hintGuard(String name) => _u.ifStatement(
        condition: '_${name}Hint != null',
        ifBlockStatements: ['return _${name}Hint;'],
      );

  String formatterExpr(String name, {required bool integer}) => _u.callExpression('NumberInputFormatter', [
        'config: _${name}Number',
        'integer: $integer',
        'onRejected: ${_u.functionLiteral(['rejection'], ['_flash${name.firstUp}Hint(rejection.message(_form.strings));'])}',
      ]);

  String flashHintMethod(GLField f) {
    final name = f.codeName;
    return _u.createMethod(
      returnType: 'void',
      methodName: '_flash${name.firstUp}Hint',
      namedArguments: false,
      arguments: ['String message'],
      statements: [
        '_${name}HintTimer?.cancel();',
        '_${name}Hint = message;',
        '_${name}FieldKey.currentState?.validate();',
        '_${name}HintTimer = Timer($hintDuration, ${_u.functionLiteral([], [
          _u.ifStatement(condition: '!mounted', ifBlockStatements: ['return;']),
          '_${name}Hint = null;',
          '_${name}FieldKey.currentState?.validate();',
        ])});',
      ],
    );
  }
}
