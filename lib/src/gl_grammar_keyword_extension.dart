import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/code_name_mixin.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';

/// Assigns target-language safe identifiers ([GLField.codeName],
/// [GLEnumValue.codeName], [GLArgumentDefinition.codeName]) to every GraphQL
/// name that collides with a reserved keyword. The original name is left
/// untouched as the canonical wire token (JSON keys, query/SDL text).
///
/// Runs as the last step of [validateSemantics] so that projected types and
/// projected interfaces — created during validation — are covered too.
extension GLGrammarKeywordExtension on GLParser {
  /// Runs the leading-underscore / reserved-word sanitization for operation
  /// names only. Called before [createProjectedTypes] so that
  /// [GLQueryDefinition.getGeneratedTypeDefinition] sees the final codeName
  /// when it builds and caches the `<stem>Response` type name.
  void assignQueryCodeNamesEarly() {
    _assignQueryCodeNames(queries.values);
  }

  /// One pass over every container of identifiers. No-op when [reservedWords]
  /// is empty (e.g. TypeScript, which accepts reserved words as properties).
  void assignCodeNames() {
    // Type/input/interface/union/enum *declaration* names — `class`, `in`,
    // `fun`, etc. are illegal here in every target language, including
    // TypeScript (`interface class { … }` is a syntax error even though
    // `{ class: string }` as a property is fine). This is a binding-identifier
    // position, so it uses [parameterReservedWords], not [reservedWords].
    _assignTypeCodeNames();

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
      // Schema/batch-mapping methods: `mapping.field` is a copy made during
      // `generateSchemaMappings()` (well before this pass runs), so — unlike
      // top-level resolver fields — it is never shared with a container this
      // loop already covers and needs its own sanitization here.
      for (final c in controllers.values) {
        _assignMappingCodeNames(c.mappings);
      }
      // Mapping-derived service interface methods (e.g. `carRelated`): the
      // synthetic field built in `_mappingServiceField` is likewise never
      // shared with any other container.
      for (final s in services.values) {
        s.assignCodeNames(reservedWords);
      }
    }

    // Parameter/binding-position identifiers (resolver + operation arguments).
    // For most languages this set equals [reservedWords]; TypeScript supplies a
    // non-empty set here even though its field set is empty, because reserved
    // words are illegal as parameter names / destructuring targets.
    // Operation method names always run: a leading-underscore operation
    // (e.g. `_entities`) must become `entities_` regardless of whether any
    // reserved words are configured, because `_entities` is a private
    // identifier in every target language.
    _assignQueryCodeNames(queries.values);

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
        _assignFieldArgumentCodeNames(c.mappings.map((m) => m.field));
      }
      for (final s in services.values) {
        _assignFieldArgumentCodeNames(s.fields);
      }
      for (final q in queries.values) {
        _assignArgumentCodeNames(q.arguments);
      }
    }
  }

  /// Resolves a collision-free, keyword-safe [GLField.codeName] for every
  /// schema/batch-mapping method on [mappings]. Mirrors [_assignQueryCodeNames]
  /// — collisions are resolved against the other mapping method names on the
  /// same controller (`mapping.field` is never a top-level [GLQueryDefinition]
  /// so it isn't covered by that pass).
  void _assignMappingCodeNames(Iterable<GLSchemaMapping> mappings) {
    final taken = mappings.map((m) => m.field.name.token).toSet();
    for (final mapping in mappings) {
      final field = mapping.field;
      final bare = field.codeName;

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
      field.codeName = candidate;
      taken.add(candidate);
    }
  }

  /// Resolves a collision-free, keyword-safe [CodeNameMixin.codeName] for every
  /// type/input/interface/union/enum — declared or projected — whose (possibly
  /// already naming-convention-normalized) code name collides with a reserved
  /// keyword, e.g. `input class` → `class_`. Mirrors the container scope and
  /// collision handling of [GLGrammarNormalizationExtension.sanitizeTypeNames]
  /// (interfaces created from a union are excluded and re-synced to the
  /// union's final name afterwards, since they must always agree).
  ///
  /// Projected types/interfaces are included because `@glTypeName(name: ...)`
  /// lets a query/field selection pin an arbitrary literal name — see
  /// `_generateName` in gl_grammar_projection_extension.dart, which documents
  /// that pinned name as "honoured as-is and left untouched" — so a schema
  /// that pins the name to a reserved word (e.g. `class`) would otherwise
  /// generate an uncompilable declaration.
  void _assignTypeCodeNames() {
    if (parameterReservedWords.isEmpty) return;

    final allContainers = <CodeNameMixin>[
      ...types.values,
      ...inputs.values,
      ...interfaces.values.where((i) => !i.fromUnion),
      ...unions.values,
      ...enums.values,
      ...projectedTypes.values,
      ...projectedInterfaces.values.where((i) => !i.fromUnion),
    ];

    final taken = <String>{
      ...types.keys,
      ...inputs.keys,
      ...interfaces.keys,
      ...unions.keys,
      ...enums.keys,
      ...projectedTypes.keys,
      ...projectedInterfaces.keys,
      ...allContainers.map((c) => c.codeName),
    };

    for (final container in allContainers) {
      final current = container.codeName;
      if (!parameterReservedWords.contains(current)) continue;

      var candidate = '${current}_';
      var counter = 2;
      while (taken.contains(candidate)) {
        candidate = '${current}_$counter';
        counter++;
      }

      taken.remove(current);
      container.codeName = candidate;
      taken.add(candidate);
    }

    // Sync fromUnion interfaces to their union's final codeName so that the
    // abstract class declaration and the `implements` clauses agree.
    for (final iface in [
      ...interfaces.values.where((i) => i.fromUnion),
      ...projectedInterfaces.values.where((i) => i.fromUnion),
    ]) {
      final union = unions[iface.token];
      if (union != null) iface.codeName = union.codeName;
    }
  }

  /// Resolves a collision-free, keyword-safe [GLQueryDefinition.codeName] for
  /// each operation whose name is reserved or starts with a leading underscore.
  /// Uniqueness is enforced against the other generated method names so two
  /// operations never produce the same method identifier.
  void _assignQueryCodeNames(Iterable<GLQueryDefinition> defs) {
    final taken = defs.map((d) => d.token).toSet();
    for (final def in defs) {
      final bare = def.codeName;

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
      // Start from codeName so normalization applied earlier is respected.
      final bare = arg.codeName;

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
