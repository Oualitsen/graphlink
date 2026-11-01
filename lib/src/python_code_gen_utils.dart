import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';

class PythonCodeGenUtils implements CodeGenUtilsBase {
  /// Python blocks have no braces: the indented statements follow a `:` header
  /// that the caller writes. An empty block renders as `pass`.
  @override
  String block(List<String>? statements) {
    final lines = statements ?? const <String>[];
    if (lines.every((s) => s.isEmpty)) return 'pass'.identPy();
    return lines.map((e) => e.identPy()).join('\n');
  }

  @override
  String ifStatement({
    required String condition,
    required List<String> ifBlockStatements,
    List<String>? elseBlockStatements,
  }) {
    final buffer = StringBuffer('if $condition:\n${block(ifBlockStatements)}');
    if (elseBlockStatements != null) {
      buffer.write('\nelse:\n${block(elseBlockStatements)}');
    }
    return buffer.toString();
  }

  String elifChain({
    required List<MapEntry<String, List<String>>> branches,
    List<String>? elseStatements,
  }) {
    final buffer = StringBuffer();
    for (var i = 0; i < branches.length; i++) {
      buffer.write('${i == 0 ? 'if' : '\nelif'} ${branches[i].key}:\n${block(branches[i].value)}');
    }
    if (elseStatements != null) buffer.write('\nelse:\n${block(elseStatements)}');
    return buffer.toString();
  }

  String inlineIfStatement({required String condition, required String statement}) => 'if $condition: $statement';

  @override
  String method({
    required String returnType,
    required methodName,
    List<String>? arguments,
    required List<String> statements,
  }) =>
      createMethod(
        returnType: returnType,
        methodName: methodName,
        arguments: arguments,
        statements: statements,
      );

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
    final branches = cases
        .map((c) => MapEntry('$expression == ${c.caseValue}', [c.statement]))
        .toList();
    if (branches.isEmpty) return block(defaultStatements);
    return elifChain(branches: branches, elseStatements: defaultStatements);
  }

  @override
  String ternaryOp({
    required String condition,
    required String positiveStatement,
    required String negativeStatement,
  }) =>
      '$positiveStatement if $condition else $negativeStatement';

  /// `def name(args) -> ret:` with the given body. Pass `async: true` for a
  /// coroutine and [decorators] (`@classmethod`, `@property`, …) to prefix it.
  /// Without [statements] it renders a bare signature followed by `...`.
  @override
  String createMethod({
    String? returnType,
    required String methodName,
    List<String>? arguments,
    List<String>? statements,
    List<String> decorators = const [],
    bool async = false,
  }) {
    final buffer = StringBuffer();
    for (final d in decorators) {
      buffer.writeln(d);
    }
    buffer.write(async ? 'async def ' : 'def ');
    buffer.write(methodName);
    buffer.write(parentheses(arguments));
    if (returnType != null) {
      buffer.write(' -> $returnType');
    }
    buffer.write(':\n');
    buffer.write(block(statements ?? const ['...']));
    return buffer.toString();
  }

  @override
  String constDecl(String name, String value, {String? type}) =>
      '$name${type == null ? '' : ': $type'} = $value';

  @override
  String callExpression(String name, List<String> args) {
    if (args.isEmpty) return '$name()';
    return '$name(\n${args.join(',\n').identPy()}\n)';
  }

  @override
  String tryCatchFinally({
    required List<String> tryStatements,
    String? catchVariable,
    List<String>? catchStatements,
    List<String>? finallyStatements,
  }) {
    final buffer = StringBuffer('try:\n${block(tryStatements)}');
    if (catchStatements != null) {
      buffer.write('\nexcept Exception${catchVariable != null ? ' as $catchVariable' : ''}:\n${block(catchStatements)}');
    }
    if (finallyStatements != null) {
      buffer.write('\nfinally:\n${block(finallyStatements)}');
    }
    return buffer.toString();
  }

  @override
  String forEachLoop({
    required String variable,
    required String iterable,
    required List<String> statements,
    bool async = false,
  }) =>
      '${async ? 'async ' : ''}for $variable in $iterable:\n${block(statements)}';

  @override
  String forLoop({
    required String init,
    required String condition,
    required String increment,
    required List<String> statements,
  }) =>
      '$init\nwhile $condition:\n${block([...statements, increment])}';

  // ── Python-specific helpers ───────────────────────────────────────────────

  String createClass({
    required String className,
    required List<String> statements,
    List<String> baseClassNames = const [],
    List<String> decorators = const [],
  }) {
    final buffer = StringBuffer();
    for (final d in decorators) {
      buffer.writeln(d);
    }
    buffer.write('class $className');
    if (baseClassNames.isNotEmpty) buffer.write('(${baseClassNames.join(', ')})');
    buffer.write(':\n');
    buffer.write(block(statements));
    return buffer.toString();
  }

  String lambda(List<String> params, String expression) =>
      params.isEmpty ? 'lambda: $expression' : 'lambda ${params.join(', ')}: $expression';

  String listComprehension({required String expression, required String variable, required String iterable, String? condition}) =>
      '[$expression for $variable in $iterable${condition == null ? '' : ' if $condition'}]';

  String nullSafe(String variable, String expression, bool nullable) =>
      nullable ? '(None if $variable is None else $expression)' : expression;
}

class PythonCaseBranch extends CaseStatement {
  PythonCaseBranch({required super.caseValue, required super.statement});

  @override
  String toCaseStatement() => 'if ${caseValue}:\n${statement.identPy()}';
}
