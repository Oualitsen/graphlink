import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';

/// Assigns target-language safe identifiers ([GLField.codeName],
/// [GLEnumValue.codeName], [GLArgumentDefinition.codeName]) to every GraphQL
/// name that collides with a reserved keyword. The original name is left
/// untouched as the canonical wire token (JSON keys, query/SDL text).
///
/// Runs as the last step of [validateSemantics] so that projected types and
/// projected interfaces — created during validation — are covered too.
extension GLGrammarKeywordExtension on GLParser {
  /// One pass over every container of identifiers. No-op when [reservedWords]
  /// is empty (e.g. TypeScript, which accepts reserved words as properties).
  void assignCodeNames() {
    if (reservedWords.isEmpty) return;
    for (final t in types.values) {
      t.assignCodeNames(reservedWords);
      _assignFieldArgumentCodeNames(t.fields);
    }
    for (final i in inputs.values) {
      i.assignCodeNames(reservedWords);
    }
    for (final iface in interfaces.values) {
      iface.assignCodeNames(reservedWords);
      _assignFieldArgumentCodeNames(iface.fields);
    }
    for (final t in projectedTypes.values) {
      t.assignCodeNames(reservedWords);
    }
    for (final iface in projectedInterfaces.values) {
      iface.assignCodeNames(reservedWords);
    }
    for (final e in enums.values) {
      e.assignCodeNames(reservedWords);
    }
    // Server resolver method params: top-level operations and the field
    // arguments of @SchemaMapping/@BatchMapping controller methods.
    for (final c in controllers.values) {
      _assignFieldArgumentCodeNames(c.fields);
    }
    for (final q in queries.values) {
      _assignArgumentCodeNames(q.arguments);
    }
  }

  void _assignFieldArgumentCodeNames(Iterable<GLField> fields) {
    for (final f in fields) {
      _assignArgumentCodeNames(f.arguments);
    }
  }

  /// Resolves a collision-free, keyword-safe [GLArgumentDefinition.codeName] for
  /// each argument whose bare name is reserved. Uniqueness is enforced against
  /// the sibling argument names so generated parameter names never clash.
  void _assignArgumentCodeNames(List<GLArgumentDefinition> args) {
    final taken = args.map((a) => a.bareName).toSet();
    for (final arg in args) {
      if (!reservedWords.contains(arg.bareName)) continue;
      var candidate = '${arg.bareName}_';
      var counter = 2;
      while (taken.contains(candidate)) {
        candidate = '${arg.bareName}_$counter';
        counter++;
      }
      arg.codeName = candidate;
      taken.add(candidate);
    }
  }
}
