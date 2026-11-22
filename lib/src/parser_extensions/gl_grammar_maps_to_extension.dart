import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

class ResolvedMapping {
  final GLTokenWithFields target;
  final ToMappingPlan plan;

  const ResolvedMapping(this.target, this.plan);
}

extension GLGrammarMapsToExtension on GLParser {
  GLTokenWithFields? mappingToken(String name) => types[name] ?? inputs[name];

  Iterable<GLTokenWithFields> get _mappingSources => [...types.values, ...inputs.values];

  void validateMapsToDirectives() {
    for (final source in _mappingSources) {
      final declared = source.mapsTo;
      final seen = <String>{};

      for (final m in declared) {
        final target = mappingToken(m.targetName);
        if (target == null) {
          throw ParseException(
            "$glMapsTo target '${m.targetName}' does not exist or is not a type or input",
            info: m.tokenInfo,
          );
        }
        if (m.targetName == source.token) {
          throw ParseException("$glMapsTo on '${source.token}' cannot target itself", info: m.tokenInfo);
        }
        if (!seen.add(m.targetName)) {
          throw ParseException(
            "$glMapsTo(type: '${m.targetName}') is declared twice on '${source.token}'",
            info: m.tokenInfo,
          );
        }
      }

      _validateMapFields(source, declared);
    }
  }

  void _validateMapFields(GLTokenWithFields source, List<GLMapsTo> declared) {
    final targetNames = declared.map((m) => m.targetName).toSet();

    for (final field in source.fields) {
      final directives = field.getDirectivesByName(glMapField);
      if (directives.isEmpty) continue;

      if (declared.isEmpty) {
        throw ParseException(
          "$glMapField on field '${field.name.token}' requires $glMapsTo on '${source.token}'",
          info: field.name,
        );
      }
      if (field.arguments.isNotEmpty || field.hasDirective(glSkipOnServer)) {
        throw ParseException(
          "$glMapField cannot be used on field '${field.name.token}': fields with arguments "
          "or $glSkipOnServer never take part in a mapping",
          info: field.name,
        );
      }

      for (final d in directives) {
        final explicitTarget = d.getArgValueAsString(glMapFieldTarget);
        if (explicitTarget == null && declared.length > 1) {
          throw ParseException(
            "$glMapField on field '${field.name.token}' needs target: because '${source.token}' "
            "declares several $glMapsTo",
            info: field.name,
          );
        }
        if (explicitTarget != null && !targetNames.contains(explicitTarget)) {
          throw ParseException(
            "$glMapField(target: '$explicitTarget') on field '${field.name.token}' is not one of "
            "the $glMapsTo targets of '${source.token}'",
            info: field.name,
          );
        }

        final targetName = explicitTarget ?? declared.first.targetName;
        final alias = d.getArgValueAsString(glMapFieldTo);
        final target = mappingToken(targetName);
        if (target != null && alias != null && !target.fields.any((f) => f.name.token == alias)) {
          throw ParseException(
            "$glMapField(to: '$alias') on field '${field.name.token}' "
            "does not match any field on target '$targetName'",
            info: field.name,
          );
        }
      }
    }
  }

  /// The `to<Target>()` mappings [def] generates in the current mode. Empty on a client
  /// unless `generateMappers` is on and the target is generated for that client.
  bool mapsInMapperClass(GLTokenWithFields def) =>
      mapperAsClass ||
      def.isExternalType ||
      def.mapsTo.any((m) => mappingToken(m.targetName)?.isExternalType ?? false);

  List<ResolvedMapping> resolveMappings(GLTokenWithFields def, CodeGenerationMode mode) {
    final declared = def.mapsTo;
    if (declared.isEmpty) return const [];
    if (mode == CodeGenerationMode.client && !generateMappers) return const [];

    final result = <ResolvedMapping>[];
    final methodNames = <String, String>{};
    for (final m in declared) {
      final target = mappingToken(m.targetName)!;
      final isGenerated = mode == CodeGenerationMode.server ||
          target.isExternalType ||
          projectedTypes.containsKey(m.targetName) ||
          inputs.containsKey(m.targetName);
      if (!isGenerated) continue;

      final previous = methodNames[target.mappingCodeName];
      if (previous != null) {
        throw ParseException(
          "$glMapsTo targets '$previous' and '${m.targetName}' of '${def.token}' both generate to${target.mappingCodeName}()",
          info: m.tokenInfo,
        );
      }
      methodNames[target.mappingCodeName] = m.targetName;
      result.add(ResolvedMapping(target, ToMappingPlan.resolve(def, target, this, mode)));
    }
    return result;
  }
}

extension GLGrammarMapperClassExtension on GLParser {
  bool _isGeneratedHere(GLTokenWithFields def) =>
      mode == CodeGenerationMode.server ||
      def.isExternalType ||
      inputs.containsKey(def.token) ||
      projectedTypes.containsKey(def.token);

  /// Sources whose `to<Target>()` is emitted in a mapper class, in the order they are declared.
  List<GLTokenWithFields> get mapperClassSources => [
        for (final s in _mappingSources)
          if (mapsInMapperClass(s) && s.mapsTo.isNotEmpty && _isGeneratedHere(s)) s,
      ];

  /// Nested sources called through their own mapper class from the mappings of [def].
  Set<GLTokenWithFields> nestedMapperSources(GLTokenWithFields def) {
    final result = <GLTokenWithFields>{};
    for (final resolved in resolveMappings(def, mode)) {
      for (final f in resolved.plan.autoMapped) {
        final nested = mappingToken(f.sourceField!.type.firstType.token);
        if (nested != null &&
            nested.token != def.token &&
            nested.mapsToTarget(f.targetField.type.firstType.token)) {
          result.add(nested);
        }
      }
    }
    return result;
  }

  /// Every type a mapper file of [def] refers to: [def], its targets, parameter types and nested mappings.
  Set<GLToken> mapperDependencies(GLTokenWithFields def) {
    final result = <GLToken>{def};
    for (final resolved in resolveMappings(def, mode)) {
      result.add(resolved.target);
      for (final f in [...resolved.plan.requiredParams, ...resolved.plan.defaultParams]) {
        final token = getTokenByKey(f.targetField.type.firstType.token);
        if (token != null && !scalars.containsKey(token.token)) result.add(token);
      }
      for (final f in resolved.plan.autoMapped) {
        final nested = mappingToken(f.sourceField!.type.firstType.token);
        final nestedTarget = mappingToken(f.targetField.type.firstType.token);
        if (nested != null && nestedTarget != null && nested.mapsToTarget(nestedTarget.token)) {
          result..add(nested)..add(nestedTarget);
        }
      }
    }
    return result;
  }
}
