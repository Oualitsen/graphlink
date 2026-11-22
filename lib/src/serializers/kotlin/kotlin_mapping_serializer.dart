import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class KotlinMappingSerializer extends GLMappingSerializer {
  final KotlinSerializer _owner;
  const KotlinMappingSerializer(this._owner);

  @override
  String toMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) {
    final targetType = target.mappingCodeName;
    final params = [
      ...plan.requiredParams.map(
        (f) => '${f.targetField.codeName}: ${_owner.serializeType(f.targetField.type)}',
      ),
      ...plan.defaultParams.map(
        (f) => 'default${f.targetField.codeName.firstUp}: ${_owner.serializeType(f.targetField.type)}',
      ),
    ];

    final targetFields = target.getSerializableFields(_owner.grammar.mode);
    final autoByTarget = {for (final f in plan.autoMapped) f.targetField.name.token: f};
    final defaultByTarget = {for (final f in plan.defaultParams) f.targetField.name.token: f};
    final requiredByTarget = {for (final f in plan.requiredParams) f.targetField.name.token: f};

    final args = <String>[];
    for (final tf in targetFields) {
      final key = tf.name.token;
      final name = tf.codeName;
      if (autoByTarget.containsKey(key)) {
        final f = autoByTarget[key]!;
        final getter = f.sourceField!.codeName;
        args.add('$name = ${_toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0, def)}');
      } else if (defaultByTarget.containsKey(key)) {
        final f = defaultByTarget[key]!;
        final getter = f.sourceField!.codeName;
        args.add('$name = ${_owner.codeGenUtils.ternaryOp(
          condition: '$getter != null',
          positiveStatement: getter,
          negativeStatement: 'default${f.targetField.codeName.firstUp}',
        )}');
      } else if (requiredByTarget.containsKey(key)) {
        args.add('$name = $name');
      }
    }

    final paramsStr = params.isEmpty ? '' : params.join(', ');
    return 'fun to${targetType.firstUp}($paramsStr): $targetType = ${_owner.codeGenUtils.constructorCall(targetType, args)}';
  }

  @override
  String mapperFileName(GLTokenWithFields def) => '${mapperName(def)}.kt';

  @override
  String mapperImport(GLTokenWithFields def) => 'import ${_owner.importPrefix}.mappers.${mapperName(def)}';

  @override
  String mapperFile(GLTokenWithFields def, List<String> methods, List<String> imports) {
    final body = _owner.codeGenUtils.objectDecl(
      mapperName(def),
      [methods.join('\n\n')],
    );
    return [...imports, '', body].join('\n');
  }

  @override
  String mapperMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) {
    final targetType = _owner.mappingTypeName(target);
    final params = [
      'source: ${_owner.mappingTypeName(def)}',
      ...plan.requiredParams.map((f) => '${f.targetField.codeName}: ${_owner.serializeType(f.targetField.type)}'),
      ...plan.defaultParams.map(
        (f) => 'default${f.targetField.codeName.firstUp}: ${_owner.serializeType(f.targetField.type)}',
      ),
    ];

    final assignments = <String, String>{
      for (final f in plan.autoMapped)
        f.targetField.codeName: _mapperExpr('source.${f.sourceField!.codeName}', f.sourceField!.type, f.targetField.type, 0),
      for (final f in plan.defaultParams)
        f.targetField.codeName: 'source.${f.sourceField!.codeName} ?: default${f.targetField.codeName.firstUp}',
      for (final f in plan.requiredParams) f.targetField.codeName: f.targetField.codeName,
    };

    final String construction;
    if (target.isExternalType) {
      construction = '$targetType().apply ${_owner.codeGenUtils.block([for (final e in assignments.entries) '${e.key} = ${e.value}'])}';
    } else {
      final order = target.getSerializableFields(_owner.grammar.mode).map((f) => f.codeName);
      construction = _owner.codeGenUtils.constructorCall(
        targetType,
        [for (final n in order) if (assignments.containsKey(n)) '$n = ${assignments[n]}'],
      );
    }
    return 'fun to${target.mappingCodeName.firstUp}(${params.join(', ')}): $targetType = $construction';
  }

  String _mapperExpr(String variable, GLType sourceType, GLType targetType, int index) {
    if (sourceType is GLListType) {
      if (sourceType.firstType.token == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _mapperExpr(varName, sourceType.inlineType, targetType.inlineType, index + 1);
      return KotlinCodeGenUtils.mapCall(receiver: variable, param: varName, body: inner, nullable: sourceType.nullable);
    }
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      final call = '${mapperName(source)}.to${_owner.resolveCodeName(targetType.token).firstUp}';
      return sourceType.nullable
          ? KotlinCodeGenUtils.letCall(receiver: variable, body: '$call(it)', nullable: true)
          : '$call($variable)';
    }
    return variable;
  }

  String _toMappingExpr(String variable, GLType sourceType, GLType targetType, int index, GLToken context) {
    if (sourceType is GLListType) {
      if (sourceType.firstType.token == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _toMappingExpr(varName, sourceType.inlineType, targetType.inlineType, index + 1, context);
      return KotlinCodeGenUtils.mapCall(receiver: variable, param: varName, body: inner, nullable: sourceType.nullable);
    }
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      if (sourceType.nullable) return '$variable?.to${_owner.resolveCodeName(targetType.token).firstUp}()';
      return '$variable.to${_owner.resolveCodeName(targetType.token).firstUp}()';
    }
    return variable;
  }

  // ── File naming & imports ────────────────────────────────────────────────────
}
