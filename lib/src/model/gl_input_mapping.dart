import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

// ---------------------------------------------------------------------------
// Mapping plan model (Step 5)
// ---------------------------------------------------------------------------

/// Describes how a single target field is satisfied by the source input.
class MappedField {
  /// The field on the target type being mapped to.
  final GLField targetField;

  /// The matching field on the source input, or null if it is missing there.
  final GLField? sourceField;

  const MappedField({
    required this.targetField,
    required this.sourceField,
  });

  /// True when the source field is nullable but the target field is non-null,
  /// so a `defaultXxx` parameter must be generated.
  bool get isNullabilityMismatch =>
      sourceField != null &&
      sourceField!.type.nullable &&
      !targetField.type.nullable;
}

/// The full resolved mapping between a source input and its target type.
class MappingPlan {
  /// Fields that map directly (name or alias match, compatible nullability).
  final List<MappedField> autoMapped;

  /// Fields with a match but a nullable→non-null mismatch; need a `defaultXxx` param.
  final List<MappedField> defaultParams;

  /// Target fields absent from the source input; need a required parameter.
  final List<MappedField> requiredParams;

  final List<GLField> _sourceFields;

  MappingPlan._({
    required this.autoMapped,
    required this.defaultParams,
    required this.requiredParams,
    required List<GLField> sourceFields,
  }) : _sourceFields = sourceFields;

  /// Source fields that have no counterpart on the target type.
  /// These must be passed as parameters in fromXxx() to satisfy the input constructor.
  List<GLField> get inputOnlyFields {
    final matched = {
      ...autoMapped.map((f) => f.sourceField!),
      ...defaultParams.map((f) => f.sourceField!),
    };
    return _sourceFields.where((f) => !matched.contains(f)).toList();
  }

  /// Resolves the mapping plan for [source] mapped to [target].
  /// [allInputs] is required to detect list fields whose element type is a
  /// mapped input (e.g. [TagInput!]! → [Tag!]!) vs an unmapped mismatch
  /// (e.g. [PhoneInput!]! → [Phone!]!) which becomes a required parameter.
  /// [allTypes] is required to recursively check whether a nested mapped input's
  /// toXxx() can be called with zero arguments.
  factory MappingPlan.resolve(
      GLInputDefinition source,
      GLTypeDefinition target,
      Map<String, GLInputDefinition> allInputs,
      Map<String, GLTypeDefinition> allTypes,
      CodeGenerationMode mode) {
    final autoMapped = <MappedField>[];
    final defaultParams = <MappedField>[];
    final requiredParams = <MappedField>[];

    final sourceFields = source.getSerializableFields(mode);
    final targetFields = target.getSerializableFields(mode);

    for (final targetField in targetFields) {
      // 1. Alias match: source field whose @glMapField(to:) equals the target field name.
      GLField? sourceField = sourceFields.firstWhereOrNull(
        (f) => f.mapFieldTo == targetField.name.token,
      );

      // 2. Name match: source field whose own name equals the target field name.
      sourceField ??= sourceFields.firstWhereOrNull(
        (f) => f.mapFieldTo == null && f.name.token == targetField.name.token,
      );

      if (sourceField == null) {
        requiredParams.add(MappedField(targetField: targetField, sourceField: null));
        continue;
      }

      // 3. For list fields, check element-type compatibility.
      if (sourceField.type.isList && targetField.type.isList) {
        final sourceElemToken = sourceField.type.firstType.token;
        final targetElemToken = targetField.type.firstType.token;
        if (sourceElemToken != targetElemToken) {
          final sourceInput = allInputs[sourceElemToken];
          if (sourceInput?.mapsToType != targetElemToken) {
            // Unmapped type mismatch — becomes a required parameter.
            requiredParams.add(MappedField(targetField: targetField, sourceField: null));
            continue;
          }
          // Mapped input list — only auto-map if the nested toXxx() needs zero args.
          final nestedTarget = allTypes[targetElemToken];
          if (nestedTarget != null) {
            final nestedPlan = MappingPlan.resolve(sourceInput!, nestedTarget, allInputs, allTypes, mode);
            if (nestedPlan.requiredParams.isNotEmpty || nestedPlan.defaultParams.isNotEmpty) {
              // Nested toXxx() has required params — caller must pre-convert.
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

    return MappingPlan._(
      autoMapped: autoMapped,
      defaultParams: defaultParams,
      requiredParams: requiredParams,
      sourceFields: sourceFields,
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
