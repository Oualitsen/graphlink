import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/utils.dart';


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
      if (!generateBreaks && e is JavaCaseStatement) {
        return JavaCaseStatement(caseValue: e.caseValue, statement: e.statement, generateBreak: false).toCaseStatement();
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

  /// Emits `receiver.stream().map(param -> body).collect(Collectors.toList())`,
  /// or `receiver.stream().collect(Collectors.toList())` if [param]/[body] are
  /// omitted (element type unchanged). Wrapped in a null-check via [safeCall]
  /// if [nullable].
  static String streamMapCollect({
    required String receiver,
    String? param,
    String? body,
    bool nullable = false,
  }) {
    final method = param == null
        ? 'stream().$javaCollectorsToList'
        : 'stream().map($param -> $body).$javaCollectorsToList';
    return safeCall(receiver, method, nullable);
  }

  /// Returns `condition == null ? null : expr` if [nullable], else [expr] unchanged.
  static String nullSafeExpr(String condition, String expr, bool nullable) =>
      nullable ? '$condition == null ? null : $expr' : expr;

  /// Returns a local variable name that is unlikely to clash with user-defined
  /// method arguments by wrapping it with a fixed prefix and suffix.
  ///
  /// Example: safeLocalVar('operationName') → '__gl_operationName__'
  String safeLocalVar(String name) => '__gl_${name}__';

  /// Boxes [token] (if it names a Java primitive) and wraps it as
  /// `? extends $boxed` if [token] names a GraphQL interface, or if [token]
  /// is itself a generic type whose argument is already wildcarded (e.g.
  /// `List<? extends CarProjection>`) — Java generics are invariant, so a
  /// wildcarded type argument forces every enclosing generic to also be
  /// wildcarded for a covariant override to type-check (e.g.
  /// `Flux<? extends List<? extends CarProjection>>`). Used to build the
  /// element type of `Mono<>`, `Flux<>` and `List<>` so a covariant
  /// implementor (e.g. `User` for `UserProjection`) remains a valid override.
  static String wildcardExtends(GLParser grammar, String token) {
    final boxed = convertPrimitiveToBoxed(token);
    // The `? extends` wildcard exists solely so a server implementor (e.g.
    // `User implements UserProjection`) can covariantly override a method
    // returning `List<? extends CarProjection>` — Java generics are invariant,
    // so the wildcard is required there. Client code never overrides these
    // signatures; emitting bare `List<Interface>` keeps return types ergonomic
    // for callers (no wildcard leaking into their variable declarations).
    if (grammar.mode != CodeGenerationMode.server) {
      return boxed;
    }
    if (grammar.isInterface(token) ||
        boxed.contains('? extends') ||
        boxed.startsWith('Map<') ||
        boxed.startsWith('List<')) {
      return "? extends $boxed";
    }
    return boxed;
  }

  /// Returns `List<...>`, wrapping/boxing the element type via [wildcardExtends].
  static String listOf(GLParser grammar, String token) =>
      "List<${wildcardExtends(grammar, token)}>";

  /// Wraps [token] in [flavor]'s deferred-single type (`Mono`/`Single`/`Uni`),
  /// or returns the bare boxed/wildcarded type when [flavor] is blocking.
  /// Used for query/mutation return types — async-ness is the outer wrapper,
  /// list-ness stays part of the inner type.
  static String singleOf(
      GLParser grammar, String token, JavaReactiveFlavor flavor,
      {bool wildcard = true}) {
    final inner = wildcard ? wildcardExtends(grammar, token) : convertPrimitiveToBoxed(token);
    return flavor.single == null ? inner : "${flavor.single}<$inner>";
  }

  /// Wraps [token] in [flavor]'s deferred-many type (`Flux`/`Observable`/
  /// `Multi`). Used only for subscriptions (genuine streams).
  static String manyOf(
      GLParser grammar, String token, JavaReactiveFlavor flavor) {
    final inner = wildcardExtends(grammar, token);
    return flavor.many == null ? inner : "${flavor.many}<$inner>";
  }

  /// Returns `Mono<...>`, wrapping/boxing the element type via [wildcardExtends].
  static String monoOf(GLParser grammar, String token, {bool wildcard = true}) =>
      singleOf(grammar, token, JavaReactiveFlavor.reactor, wildcard: wildcard);

  /// Returns `Flux<...>`, wrapping/boxing the element type via [wildcardExtends].
  static String fluxOf(GLParser grammar, String token) =>
      manyOf(grammar, token, JavaReactiveFlavor.reactor);

  /// Returns `Map<K, V>`, boxing the key type and wrapping/boxing the value
  /// type via [wildcardExtends]. The key is left invariant (no wildcard) —
  /// `Map<K, V>` is a valid covariant override of `Map<K, ? extends
  /// VProjection>` when `V <: VProjection`, same reasoning as [listOf].
  static String mapOf(GLParser grammar, String keyToken, String valueToken) =>
      "Map<${convertPrimitiveToBoxed(keyToken)}, ${wildcardExtends(grammar, valueToken)}>";

}


class JavaCaseStatement extends CaseStatement {
  final bool generateBreak;

  JavaCaseStatement({required super.caseValue, required super.statement, this.generateBreak = true});

  @override
  String toCaseStatement() {
    var buffer = StringBuffer();
    buffer.writeln("case ${caseValue}:");
    buffer.writeln(statement.ident());
    if (generateBreak && !statement.trim().startsWith("return ")) {
      buffer.writeln("break;");
    }
    return buffer.toString();
  }
}