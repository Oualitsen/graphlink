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
