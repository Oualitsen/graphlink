import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';

class GoCodeGenUtils implements CodeGenUtilsBase {
  @override
  String block(List<String>? statements) {
    final lines = (statements ?? const <String>[]).where((s) => s.isNotEmpty);
    return lines.map((e) => e.identGo()).join('\n');
  }

  String braces(String header, List<String>? statements) {
    final body = block(statements);
    return body.isEmpty ? '$header {\n}' : '$header {\n$body\n}';
  }

  @override
  String ifStatement({
    required String condition,
    required List<String> ifBlockStatements,
    List<String>? elseBlockStatements,
  }) {
    final head = braces('if $condition', ifBlockStatements);
    if (elseBlockStatements == null) return head;
    return '$head else {\n${block(elseBlockStatements)}\n}';
  }

  String inlineIfStatement({required String condition, required String statement}) =>
      braces('if $condition', [statement]);

  String elseIfChain({
    required List<MapEntry<String, List<String>>> branches,
    List<String>? elseStatements,
  }) {
    final buffer = StringBuffer();
    for (var i = 0; i < branches.length; i++) {
      buffer.write(i == 0 ? '' : ' else ');
      buffer.write(braces('if ${branches[i].key}', branches[i].value));
    }
    if (elseStatements != null) buffer.write(' else {\n${block(elseStatements)}\n}');
    return buffer.toString();
  }

  @override
  String method({
    required String returnType,
    required methodName,
    List<String>? arguments,
    required List<String> statements,
  }) =>
      createMethod(returnType: returnType, methodName: methodName, arguments: arguments, statements: statements);

  @override
  String parentheses(List<String>? elements) {
    if (elements == null || elements.isEmpty) return '()';
    return '(${elements.join(', ')})';
  }

  @override
  String switchStatement({
    required String expression,
    required List<CaseStatement> cases,
    List<String>? defaultStatements,
    bool generateBreaks = true,
  }) {
    final buffer = StringBuffer('switch $expression {\n');
    for (final c in cases) {
      buffer.writeln('case ${c.caseValue}:');
      buffer.writeln(c.statement.identGo());
    }
    if (defaultStatements != null) {
      buffer.writeln('default:');
      buffer.writeln(block(defaultStatements));
    }
    buffer.write('}');
    return buffer.toString();
  }

  @override
  String ternaryOp({required String condition, required String positiveStatement, required String negativeStatement}) =>
      throw UnsupportedError('Go has no ternary operator; use ifStatement');

  /// `func (receiver) name(args) ret { ... }`. [receiver] is e.g. `v *Foo`.
  @override
  String createMethod({
    String? returnType,
    required String methodName,
    List<String>? arguments,
    List<String>? statements,
    String? receiver,
  }) {
    final head = StringBuffer('func ');
    if (receiver != null) head.write('($receiver) ');
    head.write(methodName);
    head.write('(${(arguments ?? const []).join(', ')})');
    if (returnType != null && returnType.isNotEmpty) head.write(' $returnType');
    return braces(head.toString(), statements);
  }

  /// `name := value` (inferred) or `var name type = value`.
  @override
  String constDecl(String name, String value, {String? type}) =>
      type == null ? '$name := $value' : 'var $name $type = $value';

  @override
  String callExpression(String name, List<String> args) {
    if (args.isEmpty) return '$name()';
    return '$name(\n${args.join(',\n').identGo()},\n)';
  }

  /// Go has no exceptions. A panic raised inside [tryStatements] is recovered
  /// into [catchVariable] and the finally block always runs.
  @override
  String tryCatchFinally({
    required List<String> tryStatements,
    String? catchVariable,
    List<String>? catchStatements,
    List<String>? finallyStatements,
  }) {
    final body = <String>[
      if (finallyStatements != null) braces('defer func()', finallyStatements).replaceFirst(RegExp(r'\}$'), '}()'),
      if (catchStatements != null)
        braces('defer func()', [
          'if ${catchVariable ?? '_'} := recover(); ${catchVariable ?? '_'} != nil {\n${block(catchStatements)}\n}',
        ]).replaceFirst(RegExp(r'\}$'), '}()'),
      ...tryStatements,
    ];
    return '${braces('func()', body)}()';
  }

  /// [variable] may name both loop vars (`i, v`); a single name binds the value.
  @override
  String forEachLoop({
    required String variable,
    required String iterable,
    required List<String> statements,
  }) {
    final binding = variable.contains(',') ? variable : '_, $variable';
    return braces('for $binding := range $iterable', statements);
  }

  @override
  String forLoop({
    required String init,
    required String condition,
    required String increment,
    required List<String> statements,
  }) =>
      braces('for $init; $condition; $increment', statements);

  String structDecl(String name, List<String> fields) => braces('type $name struct', fields);

  String interfaceDecl(String name, List<String> members) => braces('type $name interface', members);

  String functionLiteral(List<String> params, List<String> statements, {String? returns}) =>
      braces('func(${params.join(', ')})${returns == null ? '' : ' $returns'}', statements);

  String nilCheckReturn(String errVar, {List<String> prefix = const []}) =>
      ifStatement(condition: '$errVar != nil', ifBlockStatements: [...prefix, 'return $errVar']);

  String ptr(String goType, String value) => 'Ptr[$goType]($value)';
}

class GoCaseBranch extends CaseStatement {
  GoCaseBranch({required super.caseValue, required super.statement});

  @override
  String toCaseStatement() => 'case $caseValue:\n${statement.identGo()}';
}
