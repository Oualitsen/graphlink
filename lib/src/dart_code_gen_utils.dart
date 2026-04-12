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
    buffer.write("if");
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

  @override
  String switchStatement({
    required String expression,
    required List<CaseStatement> cases,
    String? defaultStatement,
  }) {
    var buffer = StringBuffer();
    buffer.write("switch");
    buffer.write(parentheses([expression]));
    buffer.write(" ");
    var myCases = [...cases.map((e) => e.toCaseStatement())];
    if (defaultStatement != null) {
      myCases.add("default:");
      myCases.add(defaultStatement.ident());
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
      List<String>? arguments,
      bool namedArguments = true,
      List<String>? statements,
      bool async = false}) {
    var buffer = StringBuffer();
    if (returnType != null) {
      buffer.write(returnType);
      buffer.write(" ");
    }
    buffer.write(methodName);

    if (arguments != null) {
      buffer.write(parentheses(namedArguments && arguments.isNotEmpty
          ? [
              block([arguments.join(",\n")]),
            ]
          : arguments));
    }
    if (async) {
      buffer.write(" async");
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

  String createClass({required String className, required List<String> statements, List<String>? baseClassNames}) {
    var buffer = StringBuffer();
    buffer.write("class ${className} ");
    if (baseClassNames != null && baseClassNames.isNotEmpty) {
      buffer.write("implements ");
      buffer.write(baseClassNames.join(", "));
      buffer.write(" ");
    }
    buffer.write(block(statements));
    return buffer.toString();
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


class DartCaseStatement extends CaseStatement {
  DartCaseStatement({required super.caseValue, required super.statement});

  @override
  String toCaseStatement() {
    var buffer = StringBuffer();
    buffer.writeln("case ${caseValue}:");
    buffer.writeln(statement.ident());
    if (!statement.trim().startsWith("return ")) {
      buffer.writeln("break;");
    }
    return buffer.toString();
  }
}