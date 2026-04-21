import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';

class TypeScriptCodeGenUtils implements CodeGenUtilsBase {
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
  String ifStatement({
    required String condition,
    required List<String> ifBlockStatements,
    List<String>? elseBlockStatements,
  }) {
    var buffer = StringBuffer();
    buffer.write("if ($condition) ");
    buffer.write(block(ifBlockStatements));
    if (elseBlockStatements != null) {
      buffer.write(" else ");
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
    var buffer = StringBuffer();
    buffer.write("$methodName");
    buffer.write(parentheses(arguments));
    buffer.write(": $returnType ");
    buffer.write(block(statements));
    return buffer.toString();
  }

  @override
  String parentheses(List<String>? elements) {
    if (elements == null || elements.isEmpty) return "()";
    return "(${elements.join(", ")})";
  }

  @override
  String switchStatement({
    required String expression,
    required List<CaseStatement> cases,
    String? defaultStatement,
  }) {
    var buffer = StringBuffer();
    buffer.write("switch ($expression) ");
    var myCases = [...cases.map((e) => e.toCaseStatement())];
    if (defaultStatement != null) {
      myCases.add("default:");
      myCases.add(defaultStatement.ident());
    }
    buffer.write(block(myCases));
    return buffer.toString();
  }

  @override
  String ternaryOp({
    required String condition,
    required String positiveStatement,
    required String negativeStatement,
  }) {
    return "$condition ? $positiveStatement : $negativeStatement";
  }

  /// Generates a plain function or class method.
  /// [async] wraps the return type in `Promise<T>`.
  /// [isGenerator] produces `async function*` with `AsyncGenerator<T>` return type.
  @override
  String createMethod({
    String? returnType,
    required String methodName,
    List<String>? arguments,
    List<String>? statements,
    bool namedArguments = false,
    bool async = false,
    bool isGenerator = false,
  }) {
    var buffer = StringBuffer();
    if (async || isGenerator) buffer.write("async ");
    if (isGenerator) buffer.write("*");
    buffer.write(methodName);
    buffer.write(parentheses(arguments));
    if (returnType != null) {
      if (isGenerator) {
        buffer.write(": AsyncGenerator<$returnType>");
      } else if (async) {
        buffer.write(": Promise<$returnType>");
      } else {
        buffer.write(": $returnType");
      }
    }
    if (statements != null) {
      buffer.write(" ");
      buffer.write(block(statements));
    } else {
      buffer.write(";");
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
      // TypeScript catch has no type annotation
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
    buffer.write("for (const $variable of $iterable) ");
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

  // ── TypeScript-specific constructs ─────────────────────────────────────────

  /// Generates a TypeScript `interface`.
  ///
  /// ```typescript
  /// export interface Vehicle {
  ///   readonly id: string;
  ///   brand: string;
  /// }
  /// ```
  String createInterface({
    required String interfaceName,
    required List<String> fields,
    List<String>? extendsNames,
    bool exported = true,
  }) {
    var buffer = StringBuffer();
    if (exported) buffer.write("export ");
    buffer.write("interface $interfaceName");
    if (extendsNames != null && extendsNames.isNotEmpty) {
      buffer.write(" extends ${extendsNames.join(", ")}");
    }
    buffer.write(" ");
    buffer.write(block(fields));
    return buffer.toString();
  }

  /// Generates a TypeScript `type` alias.
  ///
  /// ```typescript
  /// export type Animal = Dog | Cat;
  /// ```
  String createTypeAlias({
    required String name,
    required String value,
    bool exported = true,
  }) {
    final prefix = exported ? "export " : "";
    return "${prefix}type $name = $value;";
  }

  /// Generates a TypeScript string `enum`.
  ///
  /// ```typescript
  /// export enum FuelType {
  ///   GASOLINE = 'GASOLINE',
  ///   DIESEL = 'DIESEL',
  /// }
  /// ```
  String createEnum({
    required String enumName,
    required List<String> enumValues,
    bool exported = true,
  }) {
    final prefix = exported ? "export " : "";
    final entries = enumValues.map((v) => "$v = '$v',").toList();
    var buffer = StringBuffer();
    buffer.write("${prefix}enum $enumName ");
    buffer.write(block(entries));
    return buffer.toString();
  }

  /// Generates a TypeScript `class`.
  String createClass({
    required String className,
    required List<String> statements,
    List<String>? implementsNames,
    String? extendsName,
    bool exported = true,
  }) {
    var buffer = StringBuffer();
    if (exported) buffer.write("export ");
    buffer.write("class $className");
    if (extendsName != null) buffer.write(" extends $extendsName");
    if (implementsNames != null && implementsNames.isNotEmpty) {
      buffer.write(" implements ${implementsNames.join(", ")}");
    }
    buffer.write(" ");
    buffer.write(block(statements));
    return buffer.toString();
  }

  /// Generates a standalone TypeScript `function` (top-level, not a class method).
  ///
  /// ```typescript
  /// export async function main(): Promise<void> { ... }
  /// ```
  String createFunction({
    required String functionName,
    List<String>? arguments,
    String? returnType,
    List<String>? statements,
    bool async = false,
    bool exported = false,
  }) {
    final buf = StringBuffer();
    if (exported) buf.write('export ');
    if (async) buf.write('async ');
    buf.write('function $functionName');
    buf.write(parentheses(arguments));
    if (returnType != null) {
      buf.write(async ? ': Promise<$returnType>' : ': $returnType');
    }
    if (statements != null) {
      buf.write(' ');
      buf.write(block(statements));
    } else {
      buf.write(';');
    }
    return buf.toString();
  }

  /// Generates an `export const name = value;` statement.
  String exportConst(String name, String value) => "export const $name = $value;";

  /// Returns a local variable name that is unlikely to clash with user-defined
  /// method arguments.
  ///
  /// Example: safeLocalVar('operationName') → '__gl_operationName__'
  String safeLocalVar(String name) => '__gl_${name}__';
}

class TypeScriptCaseStatement extends CaseStatement {
  TypeScriptCaseStatement({required super.caseValue, required super.statement});

  @override
  String toCaseStatement() {
    var buffer = StringBuffer();
    buffer.writeln("case $caseValue:");
    buffer.writeln(statement.ident());
    if (!statement.trim().startsWith("return ")) {
      buffer.writeln("break;".ident());
    }
    return buffer.toString();
  }
}
