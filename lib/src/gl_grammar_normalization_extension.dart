import 'package:graphlink/src/model/code_name_mixin.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/naming_convention.dart';

/// Applies a [NamingConvention] to every field identifier in the schema.
///
/// Runs as a pass inside [GLParser.validateSemantics], immediately before
/// [GLGrammarKeywordExtension.assignCodeNames]. This ordering ensures that
/// keyword-safe sanitization operates on the already-normalized code name,
/// so `Return` → lowerCamelCase → `return` → reserved → `return_`.
///
/// No-op when [GLParser.naming] is null.
extension GLGrammarNormalizationExtension on GLParser {
  void normalizeIdentifiers() {
    final convention = naming;
    if (convention == null) return;

    // ── Type / input / union / enum definition names ───────────────────────
    for (final t in types.values) {
      _applyTypeNaming(t, convention);
    }
    for (final i in inputs.values) {
      _applyTypeNaming(i, convention);
    }
    for (final iface in interfaces.values) {
      _applyTypeNaming(iface, convention);
    }
    for (final u in unions.values) {
      _applyTypeNaming(u, convention);
    }
    for (final e in enums.values) {
      _applyTypeNaming(e, convention);
    }

    // ── Field identifiers ──────────────────────────────────────────────────
    for (final t in types.values) {
      t.applyFieldNaming(convention);
    }
    for (final i in inputs.values) {
      i.applyFieldNaming(convention);
    }
    for (final iface in interfaces.values) {
      iface.applyFieldNaming(convention);
    }
    for (final t in projectedTypes.values) {
      t.applyFieldNaming(convention);
    }
    for (final iface in projectedInterfaces.values) {
      iface.applyFieldNaming(convention);
    }
    for (final e in enums.values) {
      e.applyEnumValueNaming(convention);
    }

    // Field arguments on types and interfaces.
    for (final t in types.values) {
      _applyArgumentNamingToFields(t.fields, convention);
    }
    for (final iface in interfaces.values) {
      _applyArgumentNamingToFields(iface.fields, convention);
    }

    // Operation arguments (queries / mutations / subscriptions).
    for (final q in queries.values) {
      _applyArgumentNaming(q.arguments, convention);
    }

    // Controller field arguments (server mode).
    for (final c in controllers.values) {
      _applyArgumentNamingToFields(c.fields, convention);
    }
  }

  void _applyArgumentNamingToFields(
      Iterable<GLField> fields, NamingConvention convention) {
    for (final f in fields) {
      _applyArgumentNaming(f.arguments, convention);
    }
  }

  /// Strips any leading `_` from every container's [codeName] and appends it
  /// to the end (`_Entity` → `Entity_`), then resolves collisions with an
  /// index suffix (`Entity_2`, `Entity_3`, …).
  ///
  /// Runs unconditionally after [normalizeIdentifiers] so the rule fires even
  /// when no [NamingConvention] is configured.  Cross-map collision detection
  /// covers types, inputs, interfaces, unions, and enums simultaneously.
  void sanitizeTypeNames() {
    // Exclude interfaces auto-generated from unions (fromUnion == true) — they
    // carry the same wire name as the union and must not compete for the same
    // sanitized code name.
    final allContainers = <CodeNameMixin>[
      ...types.values,
      ...inputs.values,
      ...interfaces.values.where((i) => !i.fromUnion),
      ...unions.values,
      ...enums.values,
    ];

    // Seed with every wire name (always reserved) plus any code names already
    // assigned by the normalization pass.
    final taken = <String>{
      ...types.keys,
      ...inputs.keys,
      ...interfaces.keys,
      ...unions.keys,
      ...enums.keys,
      ...allContainers.map((c) => c.codeName),
    };

    for (final container in allContainers) {
      // Check the wire name, not codeName: a naming convention (e.g. toPascalCase)
      // may have already removed the leading _ from codeName, but the rule is
      // "any type whose wire name starts with _ gets a trailing _ in codeName".
      if (!container.wireName.startsWith('_')) continue;

      final current = container.codeName;
      final base = current.replaceFirst(RegExp(r'^_+'), '');
      var candidate = '${base}_';
      var counter = 2;
      while (taken.contains(candidate)) {
        candidate = '${base}_$counter';
        counter++;
      }

      taken.remove(current);
      container.codeName = candidate;
      taken.add(candidate);
    }

    // Sync fromUnion interfaces to their union's final codeName so that the
    // abstract class declaration and the `implements` clauses agree.
    for (final iface in interfaces.values.where((i) => i.fromUnion)) {
      final union = unions[iface.token];
      if (union != null) iface.codeName = union.codeName;
    }
  }

  /// Normalizes a container's definition name (type / input / union / enum)
  /// using [convention].typeName.  No collision handling is needed here:
  /// [sanitizeTypeNames] resolves any leading-underscore conflicts afterwards.
  void _applyTypeNaming(CodeNameMixin container, NamingConvention convention) {
    final normalized = convention.typeName(container.wireName);
    if (normalized != container.wireName) container.codeName = normalized;
  }

  /// Normalizes argument code names using [convention].field (arguments follow
  /// the same casing convention as fields in all current target languages).
  /// Collision among sibling arguments is resolved with an index suffix.
  void _applyArgumentNaming(
      List<GLArgumentDefinition> args, NamingConvention convention) {
    final taken = args.map((a) => a.bareName).toSet();
    for (final arg in args) {
      final raw = arg.bareName;
      final normalized = convention.field(raw);
      if (normalized == raw) continue;

      var code = normalized;
      if (taken.contains(code)) {
        var counter = 2;
        while (taken.contains('$code$counter')) counter++;
        code = '$code$counter';
      }
      arg.codeName = code;
      taken.add(code);
    }
  }
}
