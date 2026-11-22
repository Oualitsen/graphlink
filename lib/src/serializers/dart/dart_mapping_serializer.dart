import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class DartMappingSerializer extends GLMappingSerializer {
  final DartSerializer _owner;
  const DartMappingSerializer(this._owner);

  @override
  String toMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) {
    final targetType = target.mappingCodeName;
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
  String mapperFileName(GLTokenWithFields def) => '${mapperName(def).toSnakeCase()}.dart';

  @override
  String mapperImport(GLTokenWithFields def) =>
      "import '${_owner.importPrefix}/mappers/${mapperName(def).toSnakeCase()}.dart';";

  @override
  String mapperFile(GLTokenWithFields def, List<String> methods, List<String> imports) {
    final body = _owner.codeGenUtils.createClass(
      className: mapperName(def),
      statements: ['${mapperName(def)}._();', ...methods.expand((m) => ['', m])],
    );
    return [...imports, '', body].join('\n');
  }

  @override
  String mapperMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) {
    final targetType = _owner.mappingTypeName(target);
    final named = [
      ...plan.requiredParams.map((f) => 'required ${_owner.serializeType(f.targetField.type)} ${f.targetField.codeName}'),
      ...plan.defaultParams.map(
        (f) => 'required ${_owner.serializeType(f.targetField.type)} default${f.targetField.codeName.firstUp}',
      ),
    ];
    final assignments = [
      ...plan.autoMapped.map(
        (f) => '${f.targetField.codeName}: ${_mapperExpr('source.${f.sourceField!.codeName}', f.sourceField!.type, f.targetField.type, 0)}',
      ),
      ...plan.defaultParams.map(
        (f) => '${f.targetField.codeName}: source.${f.sourceField!.codeName} ?? default${f.targetField.codeName.firstUp}',
      ),
      ...plan.requiredParams.map((f) => '${f.targetField.codeName}: ${f.targetField.codeName}'),
    ];
    return _owner.codeGenUtils.createMethod(
      returnType: 'static $targetType',
      methodName: 'to${target.mappingCodeName.firstUp}',
      positionalArguments: ['${_owner.mappingTypeName(def)} source'],
      arguments: named,
      statements: ['return $targetType(${assignments.join(', ')});'],
    );
  }

  String _mapperExpr(String variable, GLType sourceType, GLType targetType, int index) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) {
        return DartCodeGenUtils.toListCopy(variable, sourceType.nullable);
      }
      final varName = 'e$index';
      final inner = _mapperExpr(varName, sourceType.inlineType, targetType.inlineType, index + 1);
      return DartCodeGenUtils.mapToList(receiver: variable, param: varName, body: inner, nullable: sourceType.nullable);
    }
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      final argument = sourceType.nullable ? '$variable!' : variable;
      final call = '${mapperName(source)}.to${_owner.resolveCodeName(targetType.token).firstUp}($argument)';
      return DartCodeGenUtils.nullSafeExpr(variable, call, sourceType.nullable);
    }
    return variable;
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
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      final dot = sourceType.nullable ? '?.' : '.';
      return '${dot}to${_owner.resolveCodeName(targetType.token).firstUp}()';
    }
    return ''; // same type — direct copy
  }
}
