import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';

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
    // Field/property-position identifiers (class fields, enum values, JSON keys,
    // and generated method names). TypeScript leaves this empty because reserved
    // words are legal as object-property names and method names.
    if (reservedWords.isNotEmpty) {
      for (final t in types.values) {
        t.assignCodeNames(reservedWords);
      }
      for (final i in inputs.values) {
        i.assignCodeNames(reservedWords);
      }
      for (final iface in interfaces.values) {
        iface.assignCodeNames(reservedWords);
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
      // Server resolver method names: controller fields are separate copies of
      // the root-type fields (services share the type instances and are already
      // covered), so a keyword-named operation needs its controller method
      // sanitized here. The wire name is pinned in the mapping annotation.
      for (final c in controllers.values) {
        c.assignCodeNames(reservedWords);
      }
      // Operation method names: a query/mutation/subscription may be named after
      // a reserved keyword (`return`); the generated client method must be safe
      // while the wire/operation name keeps the original token.
      _assignQueryCodeNames(queries.values);
    }

    // Parameter/binding-position identifiers (resolver + operation arguments).
    // For most languages this set equals [reservedWords]; TypeScript supplies a
    // non-empty set here even though its field set is empty, because reserved
    // words are illegal as parameter names / destructuring targets.
    if (parameterReservedWords.isNotEmpty) {
      for (final t in types.values) {
        _assignFieldArgumentCodeNames(t.fields);
      }
      for (final iface in interfaces.values) {
        _assignFieldArgumentCodeNames(iface.fields);
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
  }

  /// Resolves a collision-free, keyword-safe [GLQueryDefinition.codeName] for
  /// each operation whose name is reserved or starts with a leading underscore.
  /// Uniqueness is enforced against the other generated method names so two
  /// operations never produce the same method identifier.
  void _assignQueryCodeNames(Iterable<GLQueryDefinition> defs) {
    final taken = defs.map((d) => d.token).toSet();
    for (final def in defs) {
      final bare = def.token;

      var codeName = bare.startsWith('_') ? '${bare.substring(1)}_' : bare;
      if (codeName == bare && !reservedWords.contains(bare)) continue;

      if (reservedWords.contains(codeName)) {
        codeName = '${codeName}_';
      }
      var candidate = codeName;
      var counter = 2;
      while (taken.contains(candidate)) {
        candidate = '$codeName$counter';
        counter++;
      }
      def.codeName = candidate;
      taken.add(candidate);
    }
  }

  void _assignFieldArgumentCodeNames(Iterable<GLField> fields) {
    for (final f in fields) {
      _assignArgumentCodeNames(f.arguments);
    }
  }

  /// Resolves a collision-free, keyword-safe [GLArgumentDefinition.codeName] for
  /// each argument whose bare name is reserved or starts with a leading
  /// underscore. Uniqueness is enforced against the sibling argument names so
  /// generated parameter names never clash.
  void _assignArgumentCodeNames(List<GLArgumentDefinition> args) {
    final taken = args.map((a) => a.bareName).toSet();
    for (final arg in args) {
      final bare = arg.bareName;

      // Compute the desired code name:
      //   1. Strip leading underscore (_links → links_).
      //   2. If reserved, append underscore.
      var codeName = bare.startsWith('_') ? '${bare.substring(1)}_' : bare;

      // If unchanged and not reserved, skip.
      if (codeName == bare && !parameterReservedWords.contains(bare)) continue;

      // Name was changed or is reserved — check for collisions.
      if (parameterReservedWords.contains(codeName)) {
        codeName = '${codeName}_';
      }
      var candidate = codeName;
      var counter = 2;
      while (taken.contains(candidate)) {
        candidate = '$codeName$counter';
        counter++;
      }
      arg.codeName = candidate;
      taken.add(candidate);
    }
  }
}
