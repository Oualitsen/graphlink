import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class KotlinMappingSerializer extends GLMappingSerializer {
  final KotlinSerializer _owner;
  const KotlinMappingSerializer(this._owner);

  @override
  String toMethod(GLInputDefinition def, String targetType, ToMappingPlan plan) {
    final params = [
      ...plan.requiredParams.map(
        (f) => '${f.targetField.codeName}: ${_owner.serializeType(f.targetField.type)}',
      ),
      ...plan.defaultParams.map(
        (f) => 'default${f.targetField.codeName.firstUp}: ${_owner.serializeType(f.targetField.type)}',
      ),
    ];

    final targetDef = _owner.grammar.types[targetType];
    final targetFields = targetDef?.getSerializableFields(_owner.grammar.mode) ?? [];
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
  String fromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = targetType.firstLow;

    final promotedParams = plan.promoted.map(
      (f) => '${f.sourceField!.codeName}: ${_owner.serializeType(f.sourceField!.type)}',
    );
    final inputOnlyParams = plan.inputOnly.map(
      (f) => '${f.codeName}: ${_owner.serializeType(f.type)}',
    );
    final nullableListDefaultParams = plan.nullableListDefaults.map(
      (f) => 'default${f.sourceField!.codeName.firstUp}: ${_owner.serializeType(f.sourceField!.type)}',
    );

    final autoBySource = {for (final f in plan.autoMapped) f.sourceField!.name.token: f};
    final nullableListBySource = {for (final f in plan.nullableListDefaults) f.sourceField!.name.token: f};
    final promotedNames = {for (final f in plan.promoted) f.sourceField!.name.token};
    final inputOnlyNames = {for (final f in plan.inputOnly) f.name.token};

    final fields = def.getSerializableFields(_owner.grammar.mode);
    final args = <String>[];
    for (final field in fields) {
      final key = field.name.token;
      final name = field.codeName;
      if (autoBySource.containsKey(key)) {
        final f = autoBySource[key]!;
        final sourceExpr = '$targetVar.${f.targetField.codeName}';
        args.add('$name = ${_fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def)}');
      } else if (nullableListBySource.containsKey(key)) {
        final f = nullableListBySource[key]!;
        final sourceExpr = '$targetVar.${f.targetField.codeName}';
        final expr = _fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def);
        args.add('$name = $expr ?: default${f.sourceField!.codeName.firstUp}');
      } else if (promotedNames.contains(key) || inputOnlyNames.contains(key)) {
        args.add('$name = $name');
      }
    }

    final allParams = [
      '$targetVar: $targetType',
      ...nullableListDefaultParams,
      ...promotedParams,
      ...inputOnlyParams,
    ].join(', ');

    return 'fun from${targetType.firstUp}($allParams): ${def.codeName} = ${_owner.codeGenUtils.constructorCall(def.codeName, args)}';
  }

  String _toMappingExpr(String variable, GLType sourceType, GLType targetType, int index, GLToken context) {
    if (sourceType is GLListType) {
      if (sourceType.firstType.token == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _toMappingExpr(varName, sourceType.inlineType, targetType.inlineType, index + 1, context);
      return KotlinCodeGenUtils.mapCall(receiver: variable, param: varName, body: inner, nullable: sourceType.nullable);
    }
    final sourceInput = _owner.grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      if (sourceType.nullable) return '$variable?.to${_owner.resolveCodeName(targetType.token).firstUp}()';
      return '$variable.to${_owner.resolveCodeName(targetType.token).firstUp}()';
    }
    return variable;
  }

  String _fromMappingExpr(String variable, String sourceElemToken, GLType targetType, int index, GLToken context) {
    if (targetType is GLListType) {
      if (sourceElemToken == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _fromMappingExpr(varName, sourceElemToken, targetType.inlineType, index + 1, context);
      return KotlinCodeGenUtils.mapCall(receiver: variable, param: varName, body: inner, nullable: targetType.nullable);
    }
    final sourceInput = _owner.grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = _owner.resolveCodeName(sourceElemToken);
      final targetCodeName = _owner.resolveCodeName(targetType.token);
      if (targetType.nullable) {
        return KotlinCodeGenUtils.letCall(receiver: variable, body: '$sourceCodeName.from${targetCodeName.firstUp}(it)');
      }
      return '$sourceCodeName.from${targetCodeName.firstUp}($variable)';
    }
    return variable;
  }

  // ── File naming & imports ────────────────────────────────────────────────────
}
