import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class DartMappingSerializer extends GLMappingSerializer {
  final DartSerializer _owner;
  const DartMappingSerializer(this._owner);

  @override
  String toMethod(
      GLInputDefinition def, String targetType, ToMappingPlan plan) {
    final params = [
      ...plan.requiredParams.map(
        (f) =>
            'required ${_owner.serializeType(f.targetField.type)} ${f.targetField.codeName}',
      ),
      ...plan.defaultParams.map(
        (f) =>
            'required ${_owner.serializeType(f.targetField.type)} default${f.targetField.codeName.firstUp}',
      ),
    ];

    final assignments = [
      ...plan.autoMapped.map((f) {
        final suffix =
            _callToMapping(f.sourceField!.type, f.targetField.type, 0);
        return '${f.targetField.codeName}: ${f.sourceField!.codeName}$suffix';
      }),
      ...plan.defaultParams.map(
        (f) =>
            '${f.targetField.codeName}: ${f.sourceField!.codeName} ?? default${f.targetField.codeName.firstUp}',
      ),
      ...plan.requiredParams.map(
        (f) => '${f.targetField.codeName}: ${f.targetField.codeName}',
      ),
    ];

    return _owner.codeGenUtils.createMethod(
      returnType: targetType,
      methodName: 'to${targetType.firstUp}',
      namedArguments: true,
      arguments: params,
      statements: ['return $targetType(${assignments.join(', ')});'],
    );
  }

  @override
  String fromMethod(
      GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = targetType.firstLow;

    final autoMappedAssignments = plan.autoMapped.map((f) {
      final variable = '$targetVar.${f.targetField.codeName}';
      final expr = _callFromMapping(variable, f.sourceField!.type.firstType.token, f.targetField.type, 0);
      return '${f.sourceField!.codeName}: $expr';
    });

    final nullableListDefaultParams = plan.nullableListDefaults.map((f) =>
        '${_owner.serializeType(f.sourceField!.type)} default${f.sourceField!.codeName.firstUp} = const []');
    final nullableListAssignments = plan.nullableListDefaults.map((f) {
      final variable = '$targetVar.${f.targetField.codeName}';
      final expr = _callFromMapping(variable, f.sourceField!.type.firstType.token, f.targetField.type, 0);
      return '${f.sourceField!.codeName}: $expr ?? default${f.sourceField!.codeName.firstUp}';
    });

    final promotedParams = plan.promoted.map(
      (f) => 'required ${_owner.serializeType(f.sourceField!.type)} ${f.sourceField!.codeName}',
    );
    final promotedAssignments = plan.promoted.map(
      (f) => '${f.sourceField!.codeName}: ${f.sourceField!.codeName}',
    );

    final inputOnlyParams = plan.inputOnly.map(
      (f) => '${f.type.nullable ? '' : 'required '}${_owner.serializeType(f.type)} ${f.codeName}',
    );
    final inputOnlyAssignments = plan.inputOnly.map(
      (f) => '${f.codeName}: ${f.codeName}',
    );

    return _owner.codeGenUtils.createMethod(
      returnType: 'static ${def.codeName}',
      methodName: 'from${targetType.firstUp}',
      namedArguments: true,
      arguments: [
        'required $targetType $targetVar',
        ...nullableListDefaultParams,
        ...promotedParams,
        ...inputOnlyParams,
      ],
      statements: [
        'return ${def.codeName}(${[
          ...autoMappedAssignments,
          ...nullableListAssignments,
          ...promotedAssignments,
          ...inputOnlyAssignments,
        ].join(', ')});',
      ],
    );
  }

  /// Returns a suffix to append to a source field value for toXxx() assignments.
  /// e.g. '' for direct copy, '.map((e0) => e0.toTag()).toList()' for mapped lists.
  String _callToMapping(GLType sourceType, GLType targetType, int index) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) {
        return DartCodeGenUtils.toListCopy('', sourceType.nullable); // same element type — copy the list
      }
      final varName = 'e$index';
      final inner = _callToMapping(
          sourceType.inlineType, targetType.inlineType, index + 1);
      return DartCodeGenUtils.mapToList(
          receiver: '', param: varName, body: '$varName$inner', nullable: sourceType.nullable);
    }
    final sourceInput = _owner.grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      final dot = sourceType.nullable ? '?.' : '.';
      return '${dot}to${_owner.resolveCodeName(targetType.token).firstUp}()';
    }
    return ''; // same type — direct copy
  }

  /// Returns the full expression for a fromXxx() field assignment.
  /// e.g. 'order.tags.map((e0) => TagInput.fromTag(e0)).toList()'
  String _callFromMapping(
      String variable, String sourceElemToken, GLType targetType, int index) {
    if (targetType.isList) {
      if (sourceElemToken == targetType.firstType.token) {
        return DartCodeGenUtils.toListCopy(variable, targetType.nullable); // same element type — copy the list
      }
      final varName = 'e$index';
      final inner = _callFromMapping(
          varName, sourceElemToken, targetType.inlineType, index + 1);
      return DartCodeGenUtils.mapToList(
          receiver: variable, param: varName, body: inner, nullable: targetType.nullable);
    }
    final sourceInput = _owner.grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = _owner.resolveCodeName(sourceElemToken);
      final targetCodeName = _owner.resolveCodeName(targetType.token);
      if (targetType.nullable) {
        return '$variable != null ? $sourceCodeName.from${targetCodeName.firstUp}(${targetCodeName.firstLow}: $variable!) : null';
      }
      return '$sourceCodeName.from${targetCodeName.firstUp}(${targetCodeName.firstLow}: $variable)';
    }
    return variable; // same type — direct copy
  }
}
