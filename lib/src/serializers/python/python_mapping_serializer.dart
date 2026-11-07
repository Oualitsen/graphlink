import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class PythonMappingSerializer extends GLMappingSerializer {
  final PythonSerializer _owner;
  const PythonMappingSerializer(this._owner);

  String _snake(String codeName) => codeName.toSnakeCaseWords();

  @override
  String toMethod(GLInputDefinition def, String targetType, ToMappingPlan plan) {
    final params = [
      ...plan.requiredParams.map((f) => '${f.targetField.codeName}: ${_owner.serializeType(f.targetField.type)}'),
      ...plan.defaultParams.map((f) => 'default_${f.targetField.codeName}: ${_owner.serializeType(f.targetField.type)}'),
    ];
    final assignments = [
      ...plan.autoMapped.map((f) =>
          '${f.targetField.codeName}=${_mapToExpr('self.${f.sourceField!.codeName}', f.sourceField!.type, f.targetField.type, 0)}'),
      ...plan.defaultParams.map((f) {
        final source = 'self.${f.sourceField!.codeName}';
        return '${f.targetField.codeName}=${_owner.codeGenUtils.ternaryOp(condition: '$source is not None', positiveStatement: source, negativeStatement: 'default_${f.targetField.codeName}')}';
      }),
      ...plan.requiredParams.map((f) => '${f.targetField.codeName}=${f.targetField.codeName}'),
    ];
    return _owner.codeGenUtils.createMethod(
      methodName: 'to_${_snake(targetType)}',
      arguments: ['self', if (params.isNotEmpty) '*', ...params],
      returnType: '"$targetType"',
      statements: ['return ${_owner.codeGenUtils.callExpression(targetType, assignments)}'],
    );
  }

  @override
  String fromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = _snake(targetType);
    final autoMapped = plan.autoMapped.map((f) =>
        '${f.sourceField!.codeName}=${_mapFromExpr('$targetVar.${f.targetField.codeName}', f.sourceField!.type.firstType.token, f.targetField.type, 0)}');
    final nullableListParams = plan.nullableListDefaults
        .map((f) => 'default_${f.sourceField!.codeName}: Optional[${_owner.serializeType(f.sourceField!.type)}] = None');
    final nullableListAssignments = plan.nullableListDefaults.map((f) {
      final expr = _mapFromExpr('$targetVar.${f.targetField.codeName}', f.sourceField!.type.firstType.token, f.targetField.type, 0);
      final fallback = 'default_${f.sourceField!.codeName}';
      return '${f.sourceField!.codeName}=${_owner.codeGenUtils.ternaryOp(condition: '$expr is not None', positiveStatement: expr, negativeStatement: _owner.codeGenUtils.ternaryOp(condition: '$fallback is not None', positiveStatement: fallback, negativeStatement: '[]'))}';
    });
    final promotedParams = plan.promoted.map((f) => '${f.sourceField!.codeName}: ${_owner.serializeType(f.sourceField!.type)}');
    final promotedAssignments = plan.promoted.map((f) => '${f.sourceField!.codeName}=${f.sourceField!.codeName}');
    final inputOnlyAssignments = plan.inputOnly.map((f) => '${f.codeName}=${f.codeName}');

    final requiredParams = [
      '$targetVar: "$targetType"',
      ...promotedParams,
      ...plan.inputOnly.where((f) => !f.type.nullable).map((f) => '${f.codeName}: ${_owner.serializeType(f.type)}'),
    ];
    final optionalParams = [
      ...nullableListParams,
      ...plan.inputOnly.where((f) => f.type.nullable).map((f) => '${f.codeName}: ${_owner.serializeType(f.type)} = None'),
    ];
    return _owner.codeGenUtils.createMethod(
      decorators: ['@classmethod'],
      methodName: 'from_${_snake(targetType)}',
      arguments: ['cls', '*', ...requiredParams, ...optionalParams],
      returnType: '"${def.codeName}"',
      statements: [
        'return ${_owner.codeGenUtils.callExpression('cls', [
          ...autoMapped,
          ...nullableListAssignments,
          ...promotedAssignments,
          ...inputOnlyAssignments,
        ])}',
      ],
    );
  }

  String _mapToExpr(String expr, GLType sourceType, GLType targetType, int index) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) {
        return _owner.codeGenUtils.nullSafe(expr, 'list($expr)', sourceType.nullable);
      }
      final variable = 'e$index';
      final inner = _mapToExpr(variable, sourceType.inlineType, targetType.inlineType, index + 1);
      return _owner.codeGenUtils.nullSafe(
          expr, _owner.codeGenUtils.listComprehension(expression: inner, variable: variable, iterable: expr), sourceType.nullable);
    }
    final sourceInput = _owner.grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      return _owner.codeGenUtils.nullSafe(expr, '$expr.to_${_snake(_owner.resolveCodeName(targetType.token))}()', sourceType.nullable);
    }
    return expr;
  }

  String _mapFromExpr(String variable, String sourceElemToken, GLType targetType, int index) {
    if (targetType.isList) {
      if (sourceElemToken == targetType.firstType.token) {
        return _owner.codeGenUtils.nullSafe(variable, 'list($variable)', targetType.nullable);
      }
      final element = 'e$index';
      final inner = _mapFromExpr(element, sourceElemToken, targetType.inlineType, index + 1);
      return _owner.codeGenUtils.nullSafe(
          variable, _owner.codeGenUtils.listComprehension(expression: inner, variable: element, iterable: variable), targetType.nullable);
    }
    final sourceInput = _owner.grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = _owner.resolveCodeName(sourceElemToken);
      final targetCodeName = _owner.resolveCodeName(targetType.token);
      final call = '$sourceCodeName.from_${_snake(targetCodeName)}(${_snake(targetCodeName)}=$variable)';
      return _owner.codeGenUtils.nullSafe(variable, call, targetType.nullable);
    }
    return variable;
  }

  // ── Files & imports ────────────────────────────────────────────────────────
}
