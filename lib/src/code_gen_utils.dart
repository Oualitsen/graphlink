import 'package:retrofit_graphql/src/extensions.dart';


   String block(List<String>? statements) {
    var buffer = StringBuffer();
    buffer.writeln("{");
    if(statements != null){
      statements.map((e) => e.ident()).forEach(buffer.writeln);
    }
    buffer.write("}");
    return buffer.toString();
  }

   String ifStatement({
    required String condition,
    required List<String> ifBlockStatements,
    List<String>? elseBlockStatements
  }) {
    var buffer = StringBuffer();
    buffer.write("if");
    buffer.write(parentheses([condition]));
    buffer.write(" ");
    buffer.write(block(ifBlockStatements));
    if(elseBlockStatements != null) {
      buffer.write(" else ");
      buffer.write(block(elseBlockStatements));
    }
    return buffer.toString();
  }

  String method({required String returnType, required methodName, List<String>? arguments, required List<String> statements}) {
    var buffer = StringBuffer();
    buffer.write(returnType);
    buffer.write(" ");
    buffer.write(methodName);
    buffer.write(parentheses(arguments));
    buffer.write(" ");

    buffer.write(block(statements));
    return buffer.toString();
  }

  String parentheses(List<String>? elements) {
    if(elements == null || elements.isEmpty) {
      return "()";
    }
    var buffer = StringBuffer();
    buffer.write("(");
    for(var e in elements) {
      buffer.write(e);
      if(e != elements.last) {
        buffer.write(", ");
      }
    }
    buffer.write(")");
    return buffer.toString();
  }

  String switchStatement({required String expression, required List<CaseStatement> cases, String? defaultStatement, }) {
    var buffer = StringBuffer();
    buffer.write("switch");
    buffer.write(parentheses([expression]));
    buffer.write(" ");
    var myCases = [... cases.map((e) => e.toCaseStatement())];
    if(defaultStatement != null) {
      myCases.add("default:");
      myCases.add(defaultStatement);
    }
    buffer.write(block(myCases));
    return buffer.toString();
  }

  class CaseStatement {
    final String caseValue;
    final String statement;

   CaseStatement({required this.caseValue, required this.statement});

   String toCaseStatement() {
    var buffer = StringBuffer();
    buffer.writeln("case ${caseValue}:");
    buffer.writeln(statement.ident());
    if(!statement.trim().startsWith("return ")) {
      buffer.writeln("break;");
    }
    return buffer.toString();
   }
  }

  String ternaryOp({required String condition, required String positiveStatement,required String negativeStatement}) {
    var buffer = StringBuffer(condition);
    buffer.write(" ? ");
    buffer.write(positiveStatement);
    buffer.write(" : ");
    buffer.write(negativeStatement);
    return buffer.toString();
  }

  String declareMethod({String? returnType, required String methodName, List<String>? statements}) {
    var buffer = StringBuffer();
    if(returnType != null) {
      buffer.write(returnType);
      buffer.write(" ");
    }
    buffer.write(methodName);
    buffer.write(parentheses([block(statements)]));
    return buffer.toString();
  }