import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';

class SwiftCodeGenUtils implements CodeGenUtilsBase {
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
    buffer.write('if $condition ');
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
    buffer.write('func $methodName');
    buffer.write(parentheses(arguments));
    if (returnType != 'Void') buffer.write(' -> $returnType');
    buffer.write(' ');
    buffer.write(block(statements));
    return buffer.toString();
  }

  @override
  String parentheses(List<String>? elements) {
    if (elements == null || elements.isEmpty) return '()';
    return '(${elements.join(', ')})';
  }

  /// Maps to a Swift `switch` statement. Swift `case` branches never fall
  /// through by default, so [generateBreaks] is a no-op — there's no `break`
  /// keyword to emit (a bare `break` would actually be unusual/needless
  /// here, unlike C/Java/dart).
  @override
  String switchStatement({
    required String expression,
    required List<CaseStatement> cases,
    List<String>? defaultStatements,
    bool generateBreaks = true,
  }) {
    final buffer = StringBuffer();
    buffer.write('switch $expression ');
    final branches = [
      ...cases.map((e) => e.toCaseStatement()),
      if (defaultStatements != null)
        'default:\n${defaultStatements.join('\n').ident()}',
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
      '$condition ? $positiveStatement : $negativeStatement';

  @override
  String createMethod({
    String? returnType,
    required String methodName,
    List<String>? arguments,
    List<String>? statements,
  }) {
    final buffer = StringBuffer();
    buffer.write('func $methodName');
    buffer.write(parentheses(arguments));
    if (returnType != null && returnType != 'Void') buffer.write(' -> $returnType');
    if (statements != null) {
      buffer.write(' ');
      buffer.write(block(statements));
    }
    return buffer.toString();
  }

  /// Swift has no checked exceptions or a `finally` clause. `do`/`catch`
  /// covers `try`/`catch`; `finally` semantics are approximated with a
  /// `defer` registered as the first statement inside the `do` block —
  /// `defer` runs when that scope exits, whether normally or via a thrown
  /// error propagating out to `catch`, which is the same guarantee
  /// `finally` gives in Kotlin/Java. Individual throwing calls inside
  /// [tryStatements] must carry their own `try` keyword — this method only
  /// emits the surrounding `do`/`catch` structure, matching how
  /// [KotlinCodeGenUtils] leaves exception-specific syntax to the caller.
  @override
  String tryCatchFinally({
    required List<String> tryStatements,
    String? catchVariable,
    List<String>? catchStatements,
    List<String>? finallyStatements,
  }) {
    final buffer = StringBuffer();
    buffer.write('do ');
    buffer.write(block([
      if (finallyStatements != null) 'defer ${block(finallyStatements)}',
      ...tryStatements,
    ]));
    if (catchStatements != null) {
      buffer.write(catchVariable != null ? ' catch let $catchVariable ' : ' catch ');
      buffer.write(block(catchStatements));
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
    buffer.write('for $variable in $iterable ');
    buffer.write(block(statements));
    return buffer.toString();
  }

  /// Swift removed C-style `for (init; condition; increment)` loops
  /// entirely — this translates the same three clauses into an equivalent
  /// `while` loop. Swift-specific call sites should prefer [forEachLoop]
  /// with `.enumerated()` for indexed iteration instead; this exists to
  /// satisfy [CodeGenUtilsBase], mirroring [KotlinCodeGenUtils.forLoop]
  /// (which is likewise unused by Kotlin's own generator, since Kotlin has
  /// no C-style `for` either).
  @override
  String forLoop({
    required String init,
    required String condition,
    required String increment,
    required List<String> statements,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(init);
    buffer.write('while $condition ');
    buffer.write(block([...statements, increment]));
    return buffer.toString();
  }

  // ── Swift-specific helpers ───────────────────────────────────────────────

  /// Emits a `struct Name: Conformances { ... }` with one stored property
  /// per entry in [fields] (each already formatted as `let name: Type` /
  /// `var name: Type`). Swift does not auto-synthesize a `public` memberwise
  /// initializer, so [initBody] — the explicit `public init(...) { ... }` —
  /// is passed in separately and placed first in the body, ahead of
  /// [extraBody] (`toJson`/`fromJson`, etc.).
  String structDecl({
    required String name,
    required List<String> fields,
    required String initDecl,
    List<String>? extraBody,
    List<String>? conformances,
  }) {
    final buffer = StringBuffer();
    buffer.write('public struct $name');
    if (conformances != null && conformances.isNotEmpty) {
      buffer.write(': ${conformances.join(', ')}');
    }
    buffer.write(' ');
    buffer.write(block([
      ...fields,
      '',
      initDecl,
      if (extraBody != null) ...['', ...extraBody],
    ]));
    return buffer.toString();
  }

  /// Emits the explicit memberwise `public init(...)` every generated
  /// `struct` needs (Swift only auto-synthesizes a memberwise init when it
  /// can stay internal — never `public`). [params] are full parameter
  /// clauses (`name: Type = nil`); [assignments] are the `self.x = x` body
  /// lines, defaulting to one per param name if omitted.
  String initDecl({
    required List<String> params,
    List<String>? assignments,
  }) {
    final buffer = StringBuffer();
    buffer.write('public init(\n');
    for (var i = 0; i < params.length; i++) {
      final comma = i == params.length - 1 ? '' : ',';
      buffer.write('    ${params[i]}$comma\n');
    }
    buffer.write(') ');
    buffer.write(block(assignments ?? const []));
    return buffer.toString();
  }

  /// `protocol Name: Conformances { requirements }` — used for GraphQL
  /// interfaces/unions (see [enumNamespace] for the paired static
  /// `__typename`-dispatch factory).
  String protocolDecl({
    required String name,
    required List<String> requirements,
    List<String>? conformances,
  }) {
    final buffer = StringBuffer();
    buffer.write('public protocol $name');
    if (conformances != null && conformances.isNotEmpty) {
      buffer.write(': ${conformances.join(', ')}');
    }
    buffer.write(' ');
    buffer.write(block(requirements));
    return buffer.toString();
  }

  /// `public enum Name: String, Conformances { case ... }` for a
  /// GraphQL enum, `String`-backed so `rawValue` gives `toJson` for free.
  String enumDecl({
    required String name,
    required List<String> cases,
    List<String>? extraBody,
    List<String> conformances = const ['String', 'Sendable'],
  }) {
    final buffer = StringBuffer();
    buffer.write('public enum $name: ${conformances.join(', ')} ');
    buffer.write(block([
      ...cases,
      if (extraBody != null) ...['', ...extraBody],
    ]));
    return buffer.toString();
  }

  /// A case-less `enum` used purely as a static namespace — Swift's
  /// idiomatic uninstantiable-namespace pattern (`enum` with no cases can't
  /// be constructed). Used for `<Interface>Json.fromJson(_:)` dispatch
  /// factories, since a protocol can't host a "which concrete type is this
  /// JSON" static requirement about its own conformers.
  String enumNamespace({required String name, required List<String> body}) {
    final buffer = StringBuffer();
    buffer.write('public enum $name ');
    buffer.write(block(body));
    return buffer.toString();
  }

  /// `extension Name: Conformances? { body }` — used for `@glMapsTo`
  /// mapping methods and for retroactive protocol conformance.
  String extensionDecl({
    required String name,
    required List<String> body,
    List<String>? conformances,
  }) {
    final buffer = StringBuffer();
    buffer.write('extension $name');
    if (conformances != null && conformances.isNotEmpty) {
      buffer.write(': ${conformances.join(', ')}');
    }
    buffer.write(' ');
    buffer.write(block(body));
    return buffer.toString();
  }

  /// Emits `variable?.method` or `variable.method` based on [nullable] —
  /// same `?.` syntax Swift and Kotlin share.
  static String safeCall(String variable, String method, bool nullable) =>
      nullable ? '$variable?.$method' : '$variable.$method';

  /// Emits a closure body: `{ body }`, or `{ param in body }` if [param] is
  /// given. With no [param], callers are expected to use Swift's implicit
  /// `$0` shorthand inside [body] rather than naming a parameter.
  static String closure(String body, {String? param}) =>
      param == null ? '{ $body }' : '{ $param in $body }';

  /// Emits `receiver.map { param in body }`, or `receiver?.map { ... }` if
  /// [chainThroughOptional]. Which one is correct depends on *what* is
  /// being mapped, not just whether [receiver] is optional — Swift's
  /// `Optional` has its own `.map` (transform-the-whole-value, propagating
  /// `nil`) distinct from `Sequence.map` (iterate-elements):
  ///
  /// - Transforming an optional **scalar/object** as a single value — e.g.
  ///   `(map["role"] as? String).map { Role.fromJson($0) }` — wants plain
  ///   `.map` (no `?`): that calls `Optional<String>.map` directly, so
  ///   `$0`/[param] is bound to the whole unwrapped `String`. Writing
  ///   `?.map` here would be optional-chaining instead, which unwraps first
  ///   and then resolves `.map` against `String`'s *own* members — and
  ///   since `String` is itself a `Sequence<Character>`, that would
  ///   silently iterate characters instead.
  /// - Iterating the **elements of a nullable list** — e.g. `[Role]?` —
  ///   wants [chainThroughOptional]: `optRoles?.map { $0.toJson() }`
  ///   unwraps the `Optional<[Role]>` via chaining first, then calls
  ///   `Array.map` on the resulting `[Role]` to transform each element
  ///   while still propagating an overall `nil`. Plain `.map` here would
  ///   call `Optional.map` instead, binding the closure param to the
  ///   *entire array* rather than one element at a time.
  ///
  /// Callers building the list-recursion case (`GLListType`) pass
  /// `chainThroughOptional: type.nullable` (the outer list's own
  /// nullability); callers transforming a single optional scalar/object
  /// value leave it `false`.
  static String mapCall({
    required String receiver,
    required String body,
    String? param,
    bool chainThroughOptional = false,
  }) =>
      safeCall(receiver, 'map ${closure(body, param: param)}', chainThroughOptional);

  /// Returns a local variable name that won't clash with user-defined
  /// parameters — same convention as [KotlinCodeGenUtils.safeLocalVar] /
  /// `JavaCodeGenUtils.safeLocalVar`.
  String safeLocalVar(String name) => '__gl_${name}__';

  String letField(String name, String type) => 'public let $name: $type';

  String varField(String name, String type) => 'public var $name: $type';
}

class SwiftCaseBranch extends CaseStatement {
  SwiftCaseBranch({required super.caseValue, required super.statement});

  @override
  String toCaseStatement() => 'case $caseValue:\n${statement.ident()}';
}
