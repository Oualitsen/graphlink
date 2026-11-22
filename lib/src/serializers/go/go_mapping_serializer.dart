import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class GoMappingSerializer extends GLMappingSerializer {
  final GoSerializer _owner;
  const GoMappingSerializer(this._owner);

  String _lowerFirst(String s) => s.firstLow;

  @override
  String toMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) {
    final targetType = target.mappingCodeName;
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
      receiver: 'v ${def.mappingCodeName}',
      methodName: 'To${targetType.firstUp}',
      arguments: params,
      returnType: targetType,
      statements: [...prelude, 'return $targetType{\n${assignments.join('\n').identGo()}\n}'],
    );
  }

  String _mapToExpr(String expr, GLType sourceType, GLType targetType, int index) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) return expr;
      final variable = 'e$index';
      final inner = _mapToExpr(variable, sourceType.inlineType, targetType.inlineType, index + 1);
      return 'glMapSlice($expr, func($variable ${_owner.serializeType(sourceType.inlineType)}) ${_owner.serializeType(targetType.inlineType)} { return $inner })';
    }
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      final target = _owner.resolveCodeName(targetType.token).firstUp;
      return sourceType.nullable
          ? 'glMapPtr($expr, func(x ${source.mappingCodeName}) ${_owner.serializeType(targetType)} { return x.To$target() })'
          : '$expr.To$target()';
    }
    return expr;
  }

  // ── Files & imports ────────────────────────────────────────────────────────
}
