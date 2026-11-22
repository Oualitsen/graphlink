import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class PythonMappingSerializer extends GLMappingSerializer {
  final PythonSerializer _owner;
  const PythonMappingSerializer(this._owner);

  String _snake(String codeName) => codeName.toSnakeCaseWords();

  @override
  String toMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) {
    final targetType = target.mappingCodeName;
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

  String _mapperModule(GLTokenWithFields def) {
    final name = _snake(mapperName(def));
    return name;
  }

  @override
  String mapperFileName(GLTokenWithFields def) => '${_mapperModule(def)}.py';

  @override
  String mapperImport(GLTokenWithFields def) => 'from .${_mapperModule(def)} import ${mapperName(def)}';

  @override
  String mapperFile(GLTokenWithFields def, List<String> methods, List<String> imports) {
    final body = _owner.codeGenUtils.createClass(
      className: mapperName(def),
      statements: [methods.join('\n\n')],
    );
    return [...imports, '', '', body].join('\n');
  }

  @override
  String mapperMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) {
    final targetType = _owner.mappingTypeName(target);
    final params = [
      ...plan.requiredParams.map((f) => '${f.targetField.codeName}: ${_owner.serializeType(f.targetField.type)}'),
      ...plan.defaultParams.map((f) => 'default_${f.targetField.codeName}: ${_owner.serializeType(f.targetField.type)}'),
    ];
    final assignments = [
      ...plan.autoMapped.map((f) =>
          '${f.targetField.codeName}=${_mapperExpr('source.${f.sourceField!.codeName}', f.sourceField!.type, f.targetField.type, 0)}'),
      ...plan.defaultParams.map((f) {
        final value = 'source.${f.sourceField!.codeName}';
        return '${f.targetField.codeName}=${_owner.codeGenUtils.ternaryOp(condition: '$value is not None', positiveStatement: value, negativeStatement: 'default_${f.targetField.codeName}')}';
      }),
      ...plan.requiredParams.map((f) => '${f.targetField.codeName}=${f.targetField.codeName}'),
    ];
    return _owner.codeGenUtils.createMethod(
      decorators: const ['@staticmethod'],
      methodName: 'to_${_snake(target.mappingCodeName)}',
      arguments: ['source: ${_owner.mappingTypeName(def)}', if (params.isNotEmpty) '*', ...params],
      returnType: targetType,
      statements: ['return ${_owner.codeGenUtils.callExpression(targetType, assignments)}'],
    );
  }

  String _mapperExpr(String expr, GLType sourceType, GLType targetType, int index) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) {
        return _owner.codeGenUtils.nullSafe(expr, 'list($expr)', sourceType.nullable);
      }
      final variable = 'e$index';
      final inner = _mapperExpr(variable, sourceType.inlineType, targetType.inlineType, index + 1);
      return _owner.codeGenUtils.nullSafe(
          expr, _owner.codeGenUtils.listComprehension(expression: inner, variable: variable, iterable: expr), sourceType.nullable);
    }
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      final call = '${mapperName(source)}.to_${_snake(_owner.resolveCodeName(targetType.token))}($expr)';
      return _owner.codeGenUtils.nullSafe(expr, call, sourceType.nullable);
    }
    return expr;
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
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      return _owner.codeGenUtils.nullSafe(expr, '$expr.to_${_snake(_owner.resolveCodeName(targetType.token))}()', sourceType.nullable);
    }
    return expr;
  }

  // ── Files & imports ────────────────────────────────────────────────────────
}
