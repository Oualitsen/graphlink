import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';

class KotlinCodeGenUtils implements CodeGenUtilsBase {
  @override
  String block(List<String>? statements) {
    final buffer = StringBuffer();
    buffer.writeln('{');
    if (statements != null) {
      statements.map((e) => e.ident()).forEach(buffer.writeln);
    }
    buffer.write('}');
    return buffer.toString();
  }

  @override
  String ifStatement({
    required String condition,
    required List<String> ifBlockStatements,
    List<String>? elseBlockStatements,
  }) {
    final buffer = StringBuffer();
    buffer.write('if ($condition) ');
    buffer.write(block(ifBlockStatements));
    if (elseBlockStatements != null) {
      buffer.write(' else ');
      buffer.write(block(elseBlockStatements));
    }
    return buffer.toString();
  }

  @override
  String method({
    required String returnType,
    required methodName,
    List<String>? arguments,
    required List<String> statements,
  }) {
    final buffer = StringBuffer();
    buffer.write('fun $methodName');
    buffer.write(parentheses(arguments));
    buffer.write(': $returnType ');
    buffer.write(block(statements));
    return buffer.toString();
  }

  @override
  String parentheses(List<String>? elements) {
    if (elements == null || elements.isEmpty) return '()';
    return '(${elements.join(', ')})';
  }

  /// Maps to a Kotlin `when` expression.
  @override
  String switchStatement({
    required String expression,
    required List<CaseStatement> cases,
    List<String>? defaultStatements,
    bool generateBreaks = true,
  }) {
    final buffer = StringBuffer();
    buffer.write('when ($expression) ');
    final branches = [
      ...cases.map((e) => e.toCaseStatement()),
      if (defaultStatements != null)
        'else -> ${block(defaultStatements)}',
    ];
    buffer.write(block(branches));
    return buffer.toString();
  }

  @override
  String ternaryOp({
    required String condition,
    required String positiveStatement,
    required String negativeStatement,
  }) =>
      'if ($condition) $positiveStatement else $negativeStatement';

  @override
  String createMethod({
    String? returnType,
    required String methodName,
    List<String>? arguments,
    List<String>? statements,
  }) {
    final buffer = StringBuffer();
    buffer.write('fun $methodName');
    buffer.write(parentheses(arguments));
    if (returnType != null) buffer.write(': $returnType');
    if (statements != null) {
      buffer.write(' ');
      buffer.write(block(statements));
    }
    return buffer.toString();
  }

  @override
  String tryCatchFinally({
    required List<String> tryStatements,
    String? catchVariable,
    List<String>? catchStatements,
    List<String>? finallyStatements,
  }) {
    final buffer = StringBuffer();
    buffer.write('try ');
    buffer.write(block(tryStatements));
    if (catchStatements != null) {
      final variable = catchVariable ?? 'e';
      buffer.write(' catch ($variable: Exception) ');
      buffer.write(block(catchStatements));
    }
    if (finallyStatements != null) {
      buffer.write(' finally ');
      buffer.write(block(finallyStatements));
    }
    return buffer.toString();
  }

  @override
  String forEachLoop({
    required String variable,
    required String iterable,
    required List<String> statements,
  }) {
    final buffer = StringBuffer();
    buffer.write('for ($variable in $iterable) ');
    buffer.write(block(statements));
    return buffer.toString();
  }

  @override
  String forLoop({
    required String init,
    required String condition,
    required String increment,
    required List<String> statements,
  }) {
    final buffer = StringBuffer();
    buffer.write('for ($init; $condition; $increment) ');
    buffer.write(block(statements));
    return buffer.toString();
  }

  // ── Kotlin-specific helpers ─────────────────────────────────────────────────

  String suspendFun({
    required String name,
    List<String>? arguments,
    required String returnType,
    required List<String> statements,
  }) {
    final buffer = StringBuffer();
    buffer.write('suspend fun $name');
    buffer.write(parentheses(arguments));
    buffer.write(': $returnType ');
    buffer.write(block(statements));
    return buffer.toString();
  }

  String dataClass({
    required String name,
    required List<String> params,
    List<String>? body,
    List<String>? interfaces,
  }) {
    final buffer = StringBuffer();
    buffer.write('data class $name(\n');
    for (final p in params) {
      buffer.write('    $p,\n');
    }
    buffer.write(')');
    if (interfaces != null && interfaces.isNotEmpty) {
      buffer.write(' : ${interfaces.join(', ')}');
    }
    if (body != null && body.isNotEmpty) {
      buffer.write(' ');
      buffer.write(block(body));
    }
    return buffer.toString();
  }

  String openClass({
    required String name,
    required List<String> params,
    List<String>? body,
    List<String>? interfaces,
  }) {
    final buffer = StringBuffer();
    buffer.write('open class $name(\n');
    for (final p in params) {
      buffer.write('    $p,\n');
    }
    buffer.write(')');
    if (interfaces != null && interfaces.isNotEmpty) {
      buffer.write(' : ${interfaces.join(', ')}');
    }
    if (body != null && body.isNotEmpty) {
      buffer.write(' ');
      buffer.write(block(body));
    }
    return buffer.toString();
  }

  String companionObject(List<String> body) {
    final buffer = StringBuffer();
    buffer.write('companion object ');
    buffer.write(block(body));
    return buffer.toString();
  }

  String kotlinInterface({
    required String name,
    List<String>? body,
    List<String>? superInterfaces,
  }) {
    final buffer = StringBuffer();
    buffer.write('interface $name');
    if (superInterfaces != null && superInterfaces.isNotEmpty) {
      buffer.write(' : ${superInterfaces.join(', ')}');
    }
    buffer.write(' ');
    buffer.write(block(body));
    return buffer.toString();
  }

  String enumClass({
    required String name,
    required List<String> values,
    List<String>? body,
  }) {
    final buffer = StringBuffer();
    buffer.write('enum class $name ');
    final entries = [
      '${values.join(', ')};',
      '',
      if (body != null) ...body,
    ];
    buffer.write(block(entries));
    return buffer.toString();
  }

  /// Emits `variable?.method` or `variable.method` based on [nullable].
  static String safeCall(String variable, String method, bool nullable) =>
      nullable ? '$variable?.$method' : '$variable.$method';

  /// Returns a local variable name that won't clash with user-defined
  /// parameters — same convention as `JavaCodeGenUtils.safeLocalVar`.
  String safeLocalVar(String name) => '__gl_${name}__';

  String valField(String name, String type) => 'val $name: $type';

  String varField(String name, String type) => 'var $name: $type';

  /// Emits a constructor/function call with one argument per line:
  /// ```
  /// ClassName(
  ///     arg1,
  ///     arg2,
  /// )
  /// ```
  String constructorCall(String name, List<String> args) {
    final buffer = StringBuffer();
    buffer.writeln('$name(');
    for (final arg in args) {
      buffer.writeln('    $arg,');
    }
    buffer.write(')');
    return buffer.toString();
  }

  /// Emits a `run { ... }` block, useful for scoping temporary variables.
  String runBlock(List<String> statements) {
    final buffer = StringBuffer();
    buffer.write('run ');
    buffer.write(block(statements));
    return buffer.toString();
  }
}

class KotlinWhenBranch extends CaseStatement {
  KotlinWhenBranch({required super.caseValue, required super.statement});

  @override
  String toCaseStatement() => '$caseValue -> $statement';
}
