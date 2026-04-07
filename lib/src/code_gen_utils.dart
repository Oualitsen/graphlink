import 'package:graphlink/src/extensions.dart';

abstract class CodeGenUtilsBase {
  String block(List<String>? statements);

  String ifStatement(
      {required String condition, required List<String> ifBlockStatements, List<String>? elseBlockStatements});

  String method(
      {required String returnType, required methodName, List<String>? arguments, required List<String> statements});

  String parentheses(List<String>? elements);

  String switchStatement({
    required String expression,
    required List<CaseStatement> cases,
    String? defaultStatement,
  });
  String ternaryOp({required String condition, required String positiveStatement, required String negativeStatement});

  String createMethod({String? returnType, required String methodName, List<String>? arguments});

  String tryCatchFinally({
    required List<String> tryStatements,
    String? catchVariable,
    List<String>? catchStatements,
    List<String>? finallyStatements,
  });

  String forEachLoop({
    required String variable,
    required String iterable,
    required List<String> statements,
  });

  String forLoop({
    required String init,
    required String condition,
    required String increment,
    required List<String> statements,
  });
}

abstract class CaseStatement {
  final String caseValue;
  final String statement;

  CaseStatement({required this.caseValue, required this.statement});

  String toCaseStatement();
}

