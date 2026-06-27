import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

/// Groups each operation's *propagated* (hoisted) field-argument variables — the
/// ones `_addGeneratedArgument` flagged `isDeclared == false` — into a single
/// synthesized `<Op>FieldArgs` input object, so a query never explodes into a
/// flat parameter list (worst on Java, which has no named params).
///
/// For each affected operation the pass swaps the arg list in place: it removes
/// every non-declared arg and inserts ONE synthetic arg whose type is the
/// generated input. Because the operation's argument list is the single source
/// of truth the serializers read, method signatures fall out for free; only the
/// wire-level emitters (query-string serializer + variables map) must expand the
/// synthetic arg back into the flat `$variables`, keyed off
/// [GLArgumentDefinition.hoistArgsInput].
///
/// Must run after `propagateFieldArgumentVariables()` (so the propagated args
/// exist) and before `createProjectedTypes()` (so the new input is picked up by
/// projection and import resolution).
extension GLHoistArgs on GLParser {
  void groupHoistedArgsIntoInputs() {
    for (final def in queries.values) {
      final extracted =
          def.arguments.where((a) => !a.isDeclared).toList(growable: false);
      if (extracted.isEmpty) continue;

      for (final a in extracted) {
        def.removeArgument(a.token);
      }

      final inputName = _uniqueHoistInputName(def.token);
      final input = GLInputDefinition(
        directives: [],
        name: def.tokenInfo.ofNewName(inputName),
        declaredName: inputName,
        extension: false,
        fields: [
          for (final a in extracted)
            GLField(
              name: a.bareName.toToken(),
              type: a.type,
              arguments: const [],
              directives: const [],
              initialValue: a.defaultValue?.value,
            ),
        ],
      );
      inputs[inputName] = input;

      // The object can be omitted only when every field is satisfiable without
      // the caller — i.e. no field is non-null without a default. If any is, the
      // caller MUST supply it, so the object parameter is required (non-null).
      final objectRequired =
          extracted.any((a) => !a.type.nullable && a.defaultValue == null);

      final paramName = _uniqueParamName(def);
      final synthetic = GLArgumentDefinition(
        '\$$paramName'.toToken(),
        GLType(inputName.toToken(), !objectRequired),
        const [],
      )..hoistArgsInput = input;
      def.setArgument(synthetic);
    }
  }

  String _uniqueHoistInputName(String opName) {
    final base = '${opName.firstUp}FieldArgs';
    if (!_hoistNameTaken(base)) return base;
    var i = 1;
    while (_hoistNameTaken('$base$i')) {
      i++;
    }
    return '$base$i';
  }

  bool _hoistNameTaken(String name) =>
      types.containsKey(name) ||
      inputs.containsKey(name) ||
      interfaces.containsKey(name) ||
      enums.containsKey(name) ||
      unions.containsKey(name) ||
      scalars.containsKey(name);

  /// Picks a parameter name (`fieldArgs`) that doesn't clash with the operation's
  /// remaining declared-arg identifiers; index-suffixes on collision.
  String _uniqueParamName(GLQueryDefinition def) {
    final taken = def.arguments.map((a) => a.codeName).toSet();
    const base = 'fieldArgs';
    if (!taken.contains(base)) return base;
    var i = 1;
    while (taken.contains('$base$i')) {
      i++;
    }
    return '$base$i';
  }
}
