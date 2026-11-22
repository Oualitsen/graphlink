import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/code_name_mixin.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

/// One `@glMapsTo(type: ...)` declared on a type or input.
class GLMapsTo {
  final String targetName;
  final TokenInfo tokenInfo;

  const GLMapsTo(this.targetName, this.tokenInfo);
}

extension GLMapsToSource on GLTokenWithFields {
  List<GLMapsTo> get mapsTo {
    final self = this;
    if (self is! GLDirectivesMixin) return const [];
    final directives = (self as GLDirectivesMixin).getDirectivesByName(glMapsTo);
    return [
      for (final d in directives)
        GLMapsTo(d.getArgValueAsString(glMapsToType)!, d.tokenInfo),
    ];
  }

  bool mapsToTarget(String targetName) => mapsTo.any((m) => m.targetName == targetName);

  String get mappingCodeName {
    final self = this;
    return self is CodeNameMixin ? (self as CodeNameMixin).codeName : token;
  }

  Set<GLToken> mappingDependencies(GLParser g) {
    final result = <GLToken>{};
    for (final mapping in g.resolveMappings(this, g.mode)) {
      result.add(mapping.target);
      for (final f in mapping.plan.requiredParams) {
        final token = g.getTokenByKey(f.targetField.type.firstType.token);
        if (filterDependecy(token, g)) result.add(token!);
      }
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// Shared field pairing
// ---------------------------------------------------------------------------

/// A pairing between a target field and the matching source field.
class MappedField {
  final GLField targetField;

  /// Null when the target field has no counterpart in the source.
  final GLField? sourceField;

  const MappedField({required this.targetField, required this.sourceField});

  /// True when the source is nullable but the target is non-null.
  bool get isNullabilityMismatch =>
      sourceField != null &&
      sourceField!.type.nullable &&
      !targetField.type.nullable;
}

// ---------------------------------------------------------------------------
// toXxx() plan
// ---------------------------------------------------------------------------

/// Encodes everything the serializer needs to generate a `toTargetType()` method.
class ToMappingPlan {
  /// Fields that copy directly (name / alias match, compatible nullability).
  final List<MappedField> autoMapped;

  /// Fields with a nullable→non-null mismatch; serializer emits a `defaultXxx` param.
  final List<MappedField> defaultParams;

  /// Target fields absent from the source; serializer emits a required param.
  final List<MappedField> requiredParams;

  const ToMappingPlan._({
    required this.autoMapped,
    required this.defaultParams,
    required this.requiredParams,
  });

  /// True when at least one field is actually derived from the source.
  /// When false the instance would be unused — toXxx() should not be generated.
  bool get derivesAnythingFromSource =>
      autoMapped.isNotEmpty || defaultParams.isNotEmpty;

  factory ToMappingPlan.resolve(
    GLTokenWithFields source,
    GLTokenWithFields target,
    GLParser parser,
    CodeGenerationMode mode, {
    Set<String> visiting = const {},
  }) {
    final autoMapped = <MappedField>[];
    final defaultParams = <MappedField>[];
    final requiredParams = <MappedField>[];
    final typeMap = parser.typeMap;

    final sourceFields = source.getSerializableFields(mode);
    final targetFields = target.getSerializableFields(mode);

    ToMappingPlan? nestedPlan(String sourceToken, String targetToken) {
      final key = '$sourceToken>$targetToken';
      if (visiting.contains(key)) return null;
      final nestedSource = parser.mappingToken(sourceToken);
      final nestedTarget = parser.mappingToken(targetToken);
      if (nestedSource == null || nestedTarget == null || !nestedSource.mapsToTarget(targetToken)) {
        return null;
      }
      return ToMappingPlan.resolve(nestedSource, nestedTarget, parser, mode, visiting: {...visiting, key});
    }

    bool needsParams(ToMappingPlan? nested) =>
        nested == null || nested.requiredParams.isNotEmpty || nested.defaultParams.isNotEmpty;

    for (final targetField in targetFields) {
      final sourceField = sourceFields.firstWhereOrNull(
        (f) => (f.mapFieldTo(target.token) ?? f.name.token) == targetField.name.token,
      );

      if (sourceField == null) {
        requiredParams.add(MappedField(targetField: targetField, sourceField: null));
        continue;
      }

      if (!sourceField.type.isList && !targetField.type.isList) {
        final sourceToken = sourceField.type.token;
        final targetToken = targetField.type.token;
        if (sourceToken != targetToken) {
          final sourceMapped = typeMap[sourceToken] ?? sourceToken;
          final targetMapped = typeMap[targetToken] ?? targetToken;
          if (sourceMapped != targetMapped && needsParams(nestedPlan(sourceToken, targetToken))) {
            requiredParams.add(MappedField(targetField: targetField, sourceField: null));
            continue;
          }
        }
      }

      if (sourceField.type.isList && targetField.type.isList) {
        final sourceElemToken = sourceField.type.firstType.token;
        final targetElemToken = targetField.type.firstType.token;
        if (sourceElemToken != targetElemToken && needsParams(nestedPlan(sourceElemToken, targetElemToken))) {
          requiredParams.add(MappedField(targetField: targetField, sourceField: null));
          continue;
        }
      }

      final entry = MappedField(targetField: targetField, sourceField: sourceField);
      if (entry.isNullabilityMismatch) {
        defaultParams.add(entry);
      } else {
        autoMapped.add(entry);
      }
    }

    return ToMappingPlan._(
      autoMapped: autoMapped,
      defaultParams: defaultParams,
      requiredParams: requiredParams,
    );
  }
}

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
