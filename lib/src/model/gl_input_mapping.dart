import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

// ---------------------------------------------------------------------------
// Shared field pairing
// ---------------------------------------------------------------------------

/// A pairing between a target type field and the matching source input field.
class MappedField {
  final GLField targetField;

  /// Null when the target field has no counterpart in the source input.
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

  /// Target fields absent from the source input; serializer emits a required param.
  final List<MappedField> requiredParams;

  const ToMappingPlan._({
    required this.autoMapped,
    required this.defaultParams,
    required this.requiredParams,
  });

  /// True when at least one field is actually derived from the source input.
  /// When false the input instance would be unused — toXxx() should not be generated.
  bool get derivesAnythingFromSource =>
      autoMapped.isNotEmpty || defaultParams.isNotEmpty;

  factory ToMappingPlan.resolve(
      GLInputDefinition source,
      GLTypeDefinition target,
      Map<String, GLInputDefinition> allInputs,
      Map<String, GLTypeDefinition> allTypes,
      CodeGenerationMode mode, {
      Map<String, String> typeMap = const {},
  }) {
    final autoMapped = <MappedField>[];
    final defaultParams = <MappedField>[];
    final requiredParams = <MappedField>[];

    final sourceFields = source.getSerializableFields(mode);
    final targetFields = target.getSerializableFields(mode);

    for (final targetField in targetFields) {
      GLField? sourceField = sourceFields.firstWhereOrNull(
        (f) => f.mapFieldTo == targetField.name.token,
      );
      sourceField ??= sourceFields.firstWhereOrNull(
        (f) => f.mapFieldTo == null && f.name.token == targetField.name.token,
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
          if (sourceMapped != targetMapped) {
            final sourceInput = allInputs[sourceToken];
            if (sourceInput?.mapsToType != targetToken) {
              requiredParams.add(MappedField(targetField: targetField, sourceField: null));
              continue;
            }
            final nestedTarget = allTypes[targetToken];
            if (nestedTarget != null) {
              final nested = ToMappingPlan.resolve(sourceInput!, nestedTarget, allInputs, allTypes, mode, typeMap: typeMap);
              if (nested.requiredParams.isNotEmpty || nested.defaultParams.isNotEmpty) {
                requiredParams.add(MappedField(targetField: targetField, sourceField: null));
                continue;
              }
            }
          }
        }
      }

      if (sourceField.type.isList && targetField.type.isList) {
        final sourceElemToken = sourceField.type.firstType.token;
        final targetElemToken = targetField.type.firstType.token;
        if (sourceElemToken != targetElemToken) {
          final sourceInput = allInputs[sourceElemToken];
          if (sourceInput?.mapsToType != targetElemToken) {
            requiredParams.add(MappedField(targetField: targetField, sourceField: null));
            continue;
          }
          final nestedTarget = allTypes[targetElemToken];
          if (nestedTarget != null) {
            final nested = ToMappingPlan.resolve(sourceInput!, nestedTarget, allInputs, allTypes, mode, typeMap: typeMap);
            if (nested.requiredParams.isNotEmpty || nested.defaultParams.isNotEmpty) {
              requiredParams.add(MappedField(targetField: targetField, sourceField: null));
              continue;
            }
          }
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

// ---------------------------------------------------------------------------
// fromXxx() plan
// ---------------------------------------------------------------------------

/// Encodes everything the serializer needs to generate a `fromTargetType()` method.
class FromMappingPlan {
  /// Fields auto-derived from the target instance (direct assign or zero-arg nested fromXxx()).
  final List<MappedField> autoMapped;

  /// Fields where the target list is nullable but the input list is non-null.
  /// Serializer emits an optional `default` param and a `?? default` fallback.
  final List<MappedField> nullableListDefaults;

  /// Fields that cannot be auto-derived: nested fromXxx() needs args, list element
  /// nullability mismatch, or scalar target-nullable/input-non-null.
  /// Serializer emits a required param of the input field's type.
  final List<MappedField> promoted;

  /// Input fields with no counterpart on the target; always provided by the caller.
  final List<GLField> inputOnly;

  const FromMappingPlan._({
    required this.autoMapped,
    required this.nullableListDefaults,
    required this.promoted,
    required this.inputOnly,
  });

  /// True when this plan's fromXxx() requires arguments beyond the target instance.
  /// Used during recursive resolution to decide whether a nested fromXxx() can
  /// be inlined or must be promoted to a caller-supplied parameter.
  bool get hasRequiredParams =>
      promoted.isNotEmpty || inputOnly.any((f) => !f.type.nullable);

  /// True when at least one field is actually derived from the target instance.
  /// When false the target param would be unused — fromXxx() should not be generated.
  bool get derivesAnythingFromTarget =>
      autoMapped.isNotEmpty || nullableListDefaults.isNotEmpty;

  factory FromMappingPlan.resolve(
      GLInputDefinition source,
      GLTypeDefinition target,
      Map<String, GLInputDefinition> allInputs,
      Map<String, GLTypeDefinition> allTypes,
      CodeGenerationMode mode, {
      Map<String, String> typeMap = const {},
  }) {
    final toPlan = ToMappingPlan.resolve(source, target, allInputs, allTypes, mode, typeMap: typeMap);
    final allMapped = [...toPlan.autoMapped, ...toPlan.defaultParams];

    final autoMapped = <MappedField>[];
    final nullableListDefaults = <MappedField>[];
    final promoted = <MappedField>[];

    for (final f in allMapped) {
      final src = f.sourceField!;
      final tgt = f.targetField;

      if (src.type.isList && tgt.type.isList) {
        if (_hasElementNullabilityMismatch(src.type, tgt.type)) {
          promoted.add(f);
        } else if (src.type.firstType.token != tgt.type.firstType.token) {
          final srcInput = allInputs[src.type.firstType.token];
          if (srcInput?.mapsToType == tgt.type.firstType.token) {
            final nestedTarget = allTypes[tgt.type.firstType.token];
            if (nestedTarget != null) {
              final nested = FromMappingPlan.resolve(srcInput!, nestedTarget, allInputs, allTypes, mode, typeMap: typeMap);
              if (nested.hasRequiredParams) {
                promoted.add(f);
              } else if (tgt.type.nullable && !src.type.nullable) {
                nullableListDefaults.add(f);
              } else {
                autoMapped.add(f);
              }
            } else {
              promoted.add(f);
            }
          } else {
            promoted.add(f);
          }
        } else {
          if (tgt.type.nullable && !src.type.nullable) {
            nullableListDefaults.add(f);
          } else {
            autoMapped.add(f);
          }
        }
      } else {
        final srcToken = src.type.token;
        final tgtToken = tgt.type.token;
        final srcMapped = typeMap[srcToken] ?? srcToken;
        final tgtMapped = typeMap[tgtToken] ?? tgtToken;

        if (srcMapped == tgtMapped) {
          if (tgt.type.nullable && !src.type.nullable) {
            promoted.add(f);
          } else {
            autoMapped.add(f);
          }
        } else {
          final srcInput = allInputs[srcToken];
          if (srcInput?.mapsToType == tgtToken) {
            final nestedTarget = allTypes[tgtToken];
            if (nestedTarget != null) {
              final nested = FromMappingPlan.resolve(srcInput!, nestedTarget, allInputs, allTypes, mode, typeMap: typeMap);
              if (nested.hasRequiredParams) {
                promoted.add(f);
              } else {
                autoMapped.add(f);
              }
            } else {
              promoted.add(f);
            }
          } else {
            promoted.add(f);
          }
        }
      }
    }

    final matchedSourceFields = allMapped.map((f) => f.sourceField!).toSet();
    final inputOnly = source.getSerializableFields(mode)
        .where((f) => !matchedSourceFields.contains(f))
        .toList();

    return FromMappingPlan._(
      autoMapped: autoMapped,
      nullableListDefaults: nullableListDefaults,
      promoted: promoted,
      inputOnly: inputOnly,
    );
  }

  static bool _hasElementNullabilityMismatch(GLType sourceType, GLType targetType) {
    if (!sourceType.isList || !targetType.isList) return false;
    final sourceElem = sourceType.inlineType;
    final targetElem = targetType.inlineType;
    if (targetElem.nullable && !sourceElem.nullable) return true;
    return _hasElementNullabilityMismatch(sourceElem, targetElem);
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
