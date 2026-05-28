import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';

class DartCodeGenUtils implements CodeGenUtilsBase {
  @override
  String block(List<String>? statements) {
    var buffer = StringBuffer();
    buffer.writeln("{");
    if (statements != null) {
      statements.map((e) => e.ident()).forEach(buffer.writeln);
    }
    buffer.write("}");
    return buffer.toString();
  }

  @override
  String ifStatement(
      {required String condition, required List<String> ifBlockStatements, List<String>? elseBlockStatements}) {
    var buffer = StringBuffer();
    buffer.write("if ");
    buffer.write(parentheses([condition]));
    buffer.write(" ");
    buffer.write(block(ifBlockStatements));
    if (elseBlockStatements != null) {
      buffer.write(" else ");
      buffer.write(block(elseBlockStatements));
    }
    return buffer.toString();
  }

  @override
  String method(
      {required String returnType, required methodName, List<String>? arguments, required List<String> statements}) {
    var buffer = StringBuffer();
    buffer.write(returnType);
    buffer.write(" ");
    buffer.write(methodName);
    buffer.write(parentheses(arguments));
    buffer.write(" ");

    buffer.write(block(statements));
    return buffer.toString();
  }

  @override
  String parentheses(List<String>? elements) {
    if (elements == null || elements.isEmpty) {
      return "()";
    }
    var buffer = StringBuffer();
    buffer.write("(");
    for (var e in elements) {
      buffer.write(e);
      if (e != elements.last) {
        buffer.write(", ");
      }
    }
    buffer.write(")");
    return buffer.toString();
  }

  String inlineIfStatement({required String condition, required String statement}) =>
      'if ${parentheses([condition])} $statement';

  String callExpression(String name, List<String> args) {
    if (args.isEmpty) return '$name()';
    final indented = args.map((a) => a.ident()).join(',\n');
    return '$name(\n$indented,\n)';}

  String functionLiteral(List<String> params, List<String> statements) =>
      '${parentheses(params)} ${block(statements)}';

  String listArg(String name, List<String> items) {
    if (items.isEmpty) return '$name: []';
    final indented = items.map((i) => i.ident()).join(',\n');
    return '$name: [\n$indented,\n]';
  }

  @override
  String switchStatement({
    required String expression,
    required List<CaseStatement> cases,
    List<String>? defaultStatements,
    bool generateBreaks = true,
  }) {
    var buffer = StringBuffer();
    buffer.write("switch");
    buffer.write(parentheses([expression]));
    buffer.write(" ");
    var myCases = [...cases.map((e) {
      if (!generateBreaks && e is DartCaseStatement) {
        return DartCaseStatement(caseValue: e.caseValue, statement: e.statement, generateBreak: false).toCaseStatement();
      }
      return e.toCaseStatement();
    })];
    if (defaultStatements != null) {
      myCases.add("default:");
      myCases.add(defaultStatements.map((e) => e.ident()).join("\n"));
    }
    buffer.write(block(myCases));
    return buffer.toString();
  }

  @override
  String ternaryOp({required String condition, required String positiveStatement, required String negativeStatement}) {
    var buffer = StringBuffer(condition);
    buffer.write(" ? ");
    buffer.write(positiveStatement);
    buffer.write(" : ");
    buffer.write(negativeStatement);
    return buffer.toString();
  }

  @override
  String createMethod(
      {String? returnType,
      required String methodName,
      List<String>? positionalArguments,
      List<String>? arguments,
      bool namedArguments = true,
      List<String>? initializers,
      List<String>? statements,
      bool async = false,
      bool isConst = false,
      bool override = false}) {
    var buffer = StringBuffer();
    if (override) buffer.write('@override\n');
    if (isConst) buffer.write('const ');
    if (returnType != null) {
      buffer.write(returnType);
      buffer.write(" ");
    }
    buffer.write(methodName);

    if (arguments != null || positionalArguments != null) {
      final positional = positionalArguments ?? [];
      final List<String> allArgs;
      if (arguments != null && arguments.isNotEmpty && namedArguments) {
        allArgs = [...positional, block([arguments.join(",\n")])];
      } else if (arguments != null) {
        allArgs = [...positional, ...arguments];
      } else {
        allArgs = positional;
      }
      buffer.write(parentheses(allArgs.isEmpty ? null : allArgs));
    }
    if (async) {
      buffer.write(" async");
    }
    if (initializers != null && initializers.isNotEmpty) {
      buffer.write(' : ${initializers.join(', ')}');
    }
    if (statements != null) {
      buffer.write(" ");
      buffer.write(block(statements));
    } else {
      buffer.write(";");
    }
    return buffer.toString();
  }

  String createConstructor({
    required String className,
    List<String>? arguments,
    List<String>? superArguments,
    List<String>? statements,
  }) {
    var buffer = StringBuffer();
    buffer.write(className);
    buffer.write(parentheses(arguments));
    if (superArguments != null) {
      buffer.write(" : super");
      buffer.write(parentheses(superArguments));
    }
    if (statements != null) {
      buffer.write(" ");
      buffer.write(block(statements));
    } else {
      buffer.write(";");
    }
    return buffer.toString();
  }

  String createClass({
    required String className,
    required List<String> statements,
    List<String>? baseClassNames,
    String? extendsClassName,
  }) {
    var buffer = StringBuffer();
    buffer.write("class ${className} ");
    if (extendsClassName != null) {
      buffer.write("extends $extendsClassName ");
    }
    if (baseClassNames != null && baseClassNames.isNotEmpty) {
      buffer.write("implements ");
      buffer.write(baseClassNames.join(", "));
      buffer.write(" ");
    }
    buffer.write(block(statements));
    return buffer.toString();
  }

  String switchExpression({
    required String expression,
    required List<DartSwitchExpressionCase> cases,
  }) {
    final caseLines = cases.map((c) => '${c.pattern} => ${c.result},').toList();
    return 'switch ${parentheses([expression])} ${block(caseLines)}';
  }

  String createInterface(
      {required String className, required List<String> statements, List<String>? baseInterfaceNames}) {
    var buffer = StringBuffer();
    buffer.write("abstract class ${className}");
    if (baseInterfaceNames != null && baseInterfaceNames.isNotEmpty) {
      buffer.write(" ");
      buffer.write(baseInterfaceNames.join(", "));
    }
    buffer.write(block(statements));
    return buffer.toString();
  }

  String createEnum({required String enumName, required List<String> enumValues, List<String>? methods}) {
    var buffer = StringBuffer();
    buffer.write("enum ${enumName}");
    buffer.write(enumValues.join(", "));
    buffer.writeln(";");
    if (methods != null && methods.isNotEmpty) {
      methods.forEach(buffer.writeln);
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
    var buffer = StringBuffer();
    buffer.write("try ");
    buffer.write(block(tryStatements));
    if (catchStatements != null) {
      final variable = catchVariable ?? "e";
      buffer.write(" catch ($variable) ");
      buffer.write(block(catchStatements));
    }
    if (finallyStatements != null) {
      buffer.write(" finally ");
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
    var buffer = StringBuffer();
    buffer.write("for (var $variable in $iterable) ");
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
    var buffer = StringBuffer();
    buffer.write("for ($init; $condition; $increment) ");
    buffer.write(block(statements));
    return buffer.toString();
  }

  String then({required String varName, required List<String> statements}) {
    return ".then(($varName) ${block(statements)})";
  }

  /// Returns a local variable name that is unlikely to clash with user-defined
  /// method arguments by wrapping it with a fixed prefix and suffix.
  ///
  /// Example: safeLocalVar('operationName') → '__gl_operationName__'
  String safeLocalVar(String name) => '__gl_${name}__';
}


class DartSwitchExpressionCase {
  final String pattern;
  final String result;
  const DartSwitchExpressionCase({required this.pattern, required this.result});
}

class DartCaseStatement extends CaseStatement {
  final bool generateBreak;

  DartCaseStatement({required super.caseValue, required super.statement, this.generateBreak = true});

  @override
  String toCaseStatement() {
    var buffer = StringBuffer();
    buffer.writeln(caseValue == 'default' ? 'default:' : 'case ${caseValue}:');
    buffer.writeln(statement.ident());
    if (generateBreak && !statement.trim().startsWith("return ")) {
      buffer.writeln("break;");
    }
    return buffer.toString();
  }
}