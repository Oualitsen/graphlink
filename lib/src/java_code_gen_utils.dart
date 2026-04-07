import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';


class JavaCodeGenUtils implements CodeGenUtilsBase {
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
      myCases.add(defaultStatement);
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
      {String? returnType, required String methodName, List<String>? arguments, List<String>? statements}) {
    var buffer = StringBuffer();
    if (returnType != null) {
      buffer.write("${returnType} ");
    }
    buffer.write(methodName);
    buffer.write(parentheses(arguments));
    if (statements != null) {
      buffer.write(" ");
      buffer.write(block(statements));
    }
    return buffer.toString();
  }

  String createRecord(
      {required String recordName,
      required List<String> components,
      List<String>? statements,
      List<String>? interfaces}) {
    var buffer = StringBuffer();
    buffer.write("public record ${recordName}");
    buffer.write("(");
    buffer.write(components.join(", "));
    buffer.write(") ");
    if (interfaces != null && interfaces.isNotEmpty) {
      buffer.write("implements ");
      buffer.write(interfaces.join(", "));
      buffer.write(" ");
    }
    buffer.write(block(statements));
    return buffer.toString();
  }

  String createClass({
    required String className,
    required List<String> statements,
    List<String>? interfaceNames,
    bool staticClass = false,
  }) {
    var buffer = StringBuffer();
    buffer.write("public ");
    if (staticClass) {
      buffer.write("static ");
    }
    buffer.write("class ${className} ");
    if (interfaceNames != null && interfaceNames.isNotEmpty) {
      buffer.write("implements ");
      buffer.write(interfaceNames.join(", "));
    }
    buffer.write(block(statements));
    return buffer.toString();
  }

  String createInterface(
      {required String interfaceName, required List<String> statements, List<String>? interfaceNames}) {
    var buffer = StringBuffer();
    buffer.write("public interface ${interfaceName}");
    if (interfaceNames != null && interfaceNames.isNotEmpty) {
      buffer.write(" extends ");
      buffer.write(interfaceNames.join(", "));
    }
    buffer.write(" ");
    buffer.write(block(statements));
    return buffer.toString();
  }

  String createEnum({required String enumName, required List<String> enumValues, List<String>? methods}) {
    var buffer = StringBuffer();
    buffer.write("public enum ${enumName} ");

    buffer.write(block([
      "${enumValues.join(", ")};",
      "",
      if (methods != null) ...methods,
    ]));

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
      buffer.write(" catch (Exception $variable) ");
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
    buffer.write("for (var $variable : $iterable) ");
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

   static String safeCall(String variable, String method, bool nullable) {
    if (nullable) {
      return "$variable == null ? null : ${variable}.${method}";
    }
    return "${variable}.${method}";
  }
  
}


class JavaCaseStatement extends CaseStatement {
  JavaCaseStatement({required super.caseValue, required super.statement});

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