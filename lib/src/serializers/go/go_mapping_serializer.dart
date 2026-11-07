import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class GoMappingSerializer extends GLMappingSerializer {
  final GoSerializer _owner;
  const GoMappingSerializer(this._owner);

  String _lowerFirst(String s) => s.firstLow;

  @override
  String toMethod(GLInputDefinition def, String targetType, ToMappingPlan plan) {
    final params = [
      ...plan.requiredParams
          .map((f) => '${_lowerFirst(f.targetField.codeName)} ${_owner.serializeType(f.targetField.type)}'),
      ...plan.defaultParams.map((f) => 'default${f.targetField.codeName.firstUp} ${_owner.serializeType(f.targetField.type)}'),
    ];
    final prelude = <String>[];
    final assignments = [
      ...plan.autoMapped.map((f) =>
          '${f.targetField.codeName}: ${_mapToExpr('v.${f.sourceField!.codeName}', f.sourceField!.type, f.targetField.type, 0)},'),
      ...plan.defaultParams.map((f) {
        final local = 'resolved${f.targetField.codeName.firstUp}';
        final source = 'v.${f.sourceField!.codeName}';
        prelude.add(_owner.codeGenUtils.constDecl(local, 'default${f.targetField.codeName.firstUp}'));
        prelude.add(_owner.codeGenUtils.ifStatement(
          condition: '$source != nil',
          ifBlockStatements: ['$local = ${_owner.usesPointer(f.sourceField!.type) ? '*$source' : source}'],
        ));
        return '${f.targetField.codeName}: $local,';
      }),
      ...plan.requiredParams
          .map((f) => '${f.targetField.codeName}: ${_lowerFirst(f.targetField.codeName)},'),
    ];
    return _owner.codeGenUtils.createMethod(
      receiver: 'v ${def.codeName}',
      methodName: 'To${targetType.firstUp}',
      arguments: params,
      returnType: targetType,
      statements: [...prelude, 'return $targetType{\n${assignments.join('\n').identGo()}\n}'],
    );
  }

  @override
  String fromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = targetType.firstLow;
    final preludes = <String>[];
    final assignments = <String>[
      ...plan.autoMapped.map((f) =>
          '${f.sourceField!.codeName}: ${_mapFromExpr('$targetVar.${f.targetField.codeName}', f.sourceField!.type.firstType.token, f.targetField.type, 0)},'),
      ...plan.nullableListDefaults.map((f) {
        final expr = _mapFromExpr(
            '$targetVar.${f.targetField.codeName}', f.sourceField!.type.firstType.token, f.targetField.type, 0);
        final local = 'resolved${f.sourceField!.codeName.firstUp}';
        preludes.add(_owner.codeGenUtils.constDecl(local, expr));
        preludes.add(_owner.codeGenUtils.ifStatement(
          condition: '$local == nil',
          ifBlockStatements: ['$local = default${f.sourceField!.codeName.firstUp}'],
        ));
        return '${f.sourceField!.codeName}: $local,';
      }),
      ...plan.promoted.map((f) => '${f.sourceField!.codeName}: ${_lowerFirst(f.sourceField!.codeName)},'),
      ...plan.inputOnly.map((f) => '${f.codeName}: ${_lowerFirst(f.codeName)},'),
    ];
    final params = [
      '$targetVar $targetType',
      ...plan.nullableListDefaults
          .map((f) => 'default${f.sourceField!.codeName.firstUp} ${_owner.serializeType(f.sourceField!.type)}'),
      ...plan.promoted.map((f) => '${_lowerFirst(f.sourceField!.codeName)} ${_owner.serializeType(f.sourceField!.type)}'),
      ...plan.inputOnly.map((f) => '${_lowerFirst(f.codeName)} ${_owner.serializeType(f.type)}'),
    ];
    return _owner.codeGenUtils.createMethod(
      methodName: '${def.codeName}From${targetType.firstUp}',
      arguments: params,
      returnType: def.codeName,
      statements: [...preludes, 'return ${def.codeName}{\n${assignments.join('\n').identGo()}\n}'],
    );
  }

  String _mapToExpr(String expr, GLType sourceType, GLType targetType, int index) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) return expr;
      final variable = 'e$index';
      final inner = _mapToExpr(variable, sourceType.inlineType, targetType.inlineType, index + 1);
      return 'glMapSlice($expr, func($variable ${_owner.serializeType(sourceType.inlineType)}) ${_owner.serializeType(targetType.inlineType)} { return $inner })';
    }
    final sourceInput = _owner.grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      final target = _owner.resolveCodeName(targetType.token).firstUp;
      return sourceType.nullable
          ? 'glMapPtr($expr, func(x ${sourceInput!.codeName}) ${_owner.serializeType(targetType)} { return x.To$target() })'
          : '$expr.To$target()';
    }
    return expr;
  }

  String _mapFromExpr(String variable, String sourceElemToken, GLType targetType, int index) {
    if (targetType.isList) {
      if (sourceElemToken == targetType.firstType.token) return variable;
      final element = 'e$index';
      final inner = _mapFromExpr(element, sourceElemToken, targetType.inlineType, index + 1);
      final sourceInput = _owner.grammar.inputs[sourceElemToken];
      return 'glMapSlice($variable, func($element ${_owner.serializeType(targetType.inlineType)}) ${sourceInput?.codeName ?? _owner.serializeType(targetType.inlineType)} { return $inner })';
    }
    final sourceInput = _owner.grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = _owner.resolveCodeName(sourceElemToken);
      final targetCodeName = _owner.resolveCodeName(targetType.token);
      final call = '${sourceCodeName}From${targetCodeName.firstUp}';
      if (targetType.nullable) {
        return 'glMapPtr($variable, func(x $targetCodeName) $sourceCodeName { return $call(x) })';
      }
      return '$call($variable)';
    }
    return variable;
  }

  // ── Files & imports ────────────────────────────────────────────────────────
}
