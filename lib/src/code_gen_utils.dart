import 'package:retrofit_graphql/src/extensions.dart';

abstract class CodeGenUtilsBase {
  String block(List<String>? statements);

  String ifStatement(
      {required String condition,
      required List<String> ifBlockStatements,
      List<String>? elseBlockStatements});

  String method(
      {required String returnType,
      required methodName,
      List<String>? arguments,
      required List<String> statements});

  String parentheses(List<String>? elements);

  String switchStatement({
    required String expression,
    required List<CaseStatement> cases,
    String? defaultStatement,
  });
  String ternaryOp(
      {required String condition,
      required String positiveStatement,
      required String negativeStatement});

  String createMethod(
      {String? returnType,
      required String methodName,
      List<String>? arguments});
    
  
}

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
      {required String condition,
      required List<String> ifBlockStatements,
      List<String>? elseBlockStatements}) {
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
      {required String returnType,
      required methodName,
      List<String>? arguments,
      required List<String> statements}) {
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
  String ternaryOp(
      {required String condition,
      required String positiveStatement,
      required String negativeStatement}) {
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
      List<String>? statements}) {
    var buffer = StringBuffer();
    if (returnType != null) {
      buffer.write(returnType);
      buffer.write(" ");
    }
    buffer.write(methodName);
    if (arguments != null) {
      buffer.write(parentheses(namedArguments ?  [block(arguments)]: arguments));
    } else {
      buffer.write(parentheses([]));
    }
    if (statements != null) {
      buffer.write(" ");
      buffer.write(block(statements));
    }
    return buffer.toString();
  }

  String createClass({required String className, required List<String> statements, List<String>? baseClassNames}) {
    var buffer = StringBuffer();
    buffer.write("class ${className}");
    if(baseClassNames != null && baseClassNames.isNotEmpty) {
      buffer.write(" ");
      buffer.write(baseClassNames.join(", "));
    }
    buffer.write(block(statements));
    return buffer.toString();
  }

  String createInterface({required String className, required List<String> statements, List<String>? baseInterfaceNames}) {
    var buffer = StringBuffer();
    buffer.write("abstract class ${className}");
     if(baseInterfaceNames != null && baseInterfaceNames.isNotEmpty) {
      buffer.write(" ");
      buffer.write(baseInterfaceNames.join(", "));
    }
    buffer.write(block(statements));
    return buffer.toString();
  }

  String createEnum({required String className, required List<String> enumValues, List<String>? methods}) {
    var buffer = StringBuffer();
    buffer.write("enum ${className}");
    buffer.write(enumValues.join(", "));
    buffer.writeln(";");
    if(methods != null && methods.isNotEmpty) {
      methods.forEach(buffer.writeln);
    }
    return buffer.toString();
  }
}

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
      {required String condition,
      required List<String> ifBlockStatements,
      List<String>? elseBlockStatements}) {
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
      {required String returnType,
      required methodName,
      List<String>? arguments,
      required List<String> statements}) {
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
  String ternaryOp(
      {required String condition,
      required String positiveStatement,
      required String negativeStatement}) {
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
      List<String>? statements}) {
    var buffer = StringBuffer();
    if (returnType != null) {
      buffer.write(returnType);
      buffer.write(" ");
    }
    buffer.write(methodName);
    buffer.write(parentheses(arguments));
    if (statements != null) {
      buffer.write(block(statements));
    }
    return buffer.toString();
  }

  String createClass({required String className, required List<String> statements, List<String>? baseClassNames}) {
    var buffer = StringBuffer();
    buffer.write("public class ${className}");
    if(baseClassNames != null && baseClassNames.isNotEmpty) {
      buffer.write(" ");
      buffer.write(baseClassNames.join(", "));
    }
    buffer.write(block(statements));
    return buffer.toString();
  }

  String createInterface({required String className, required List<String> statements, List<String>? baseInterfaceNames}) {
    var buffer = StringBuffer();
    buffer.write("public interface ${className}");
    if(baseInterfaceNames != null && baseInterfaceNames.isNotEmpty) {
      buffer.write(" ");
      buffer.write(baseInterfaceNames.join(", "));
    }
    buffer.write(block(statements));
    return buffer.toString();
  }

  String createEnum({required String className, required List<String> enumValues, List<String>? methods}) {
    var buffer = StringBuffer();
    buffer.write("enum ${className}");
    buffer.write(enumValues.join(", "));
    buffer.writeln(";");
    if(methods != null && methods.isNotEmpty) {
      methods.forEach(buffer.writeln);
    }
    return buffer.toString();
  }
}

abstract class CaseStatement {
  final String caseValue;
  final String statement;

  CaseStatement({required this.caseValue, required this.statement});

  String toCaseStatement();
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
