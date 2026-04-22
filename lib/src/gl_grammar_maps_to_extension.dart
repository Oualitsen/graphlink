import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

extension GLGrammarMapsToExtension on GLParser {
  /// Validates all @glMapsTo and @glMapField usages across the schema.
  void validateMapsToDirectives() {
    for (final input in inputs.values) {
      final targetName = input.mapsToType;
      if (targetName == null) continue;

      final target = _resolveTarget(targetName);
      if (target == null) {
        throw ParseException(
          "$glMapsTo target '$targetName' does not exist or is not a type",
          info: input.tokenInfo,
        );
      }

      final targetFieldNames = target.fields.map((f) => f.name.token).toSet();

      for (final field in input.fields) {
        final aliasTarget = field.mapFieldTo;
        if (aliasTarget == null) continue;
        if (!targetFieldNames.contains(aliasTarget)) {
          throw ParseException(
            "$glMapField(to: '$aliasTarget') on field '${field.name.token}' "
            "does not match any field on target type '$targetName'",
            info: field.name,
          );
        }
      }
    }
  }

  /// Resolves the [MappingPlan] for [input] if it declares @glMapsTo.
  /// Returns null if the input has no @glMapsTo directive.
  /// Assumes validation has already run — target is guaranteed to exist.
  MappingPlan? resolveInputMappingPlan(GLInputDefinition input,
      CodeGenerationMode mode) {
    final targetName = input.mapsToType;
    if (targetName == null) return null;
    return input.buildMappingPlan(_resolveTarget(targetName)!, inputs, types, mode, typeMap: typeMap);
  }

  GLTypeDefinition? _resolveTarget(String name) => types[name];
}
