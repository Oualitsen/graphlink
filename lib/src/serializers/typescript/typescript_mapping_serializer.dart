import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';

class TypeScriptMappingSerializer extends GLMappingSerializer {
  final TypeScriptSerializer _owner;
  const TypeScriptMappingSerializer(this._owner);

  @override
  String toMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) =>
      _method(def, target, plan, inMapper: false);

  @override
  String mapperMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) =>
      _method(def, target, plan, inMapper: true);

  @override
  String mapperFileName(GLTokenWithFields def) => '${mapperName(def).toKebabCase()}.ts';

  @override
  String mapperImport(GLTokenWithFields def) =>
      "import { ${mapperName(def)} } from './${mapperName(def).toKebabCase()}.js';";

  @override
  String mapperFile(GLTokenWithFields def, List<String> methods, List<String> imports) {
    final body = 'export namespace ${mapperName(def)} ${_owner.codeGenUtils.block([methods.join('\n\n')])}';
    return [...imports, '', body].join('\n');
  }

  String _method(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan, {required bool inMapper}) {
    final targetType = inMapper ? _owner.mappingTypeName(target) : target.mappingCodeName;
    const source = 'obj';

    final params = [
      '$source: ${inMapper ? _owner.mappingTypeName(def) : def.mappingCodeName}',
      ...plan.requiredParams.map((f) => '${f.targetField.codeName}: ${_owner.serializeType(f.targetField.type)}'),
      ...plan.defaultParams
          .map((f) => 'default${f.targetField.codeName.firstUp}: ${_owner.serializeType(f.targetField.type)}'),
    ];

    final autoByTarget = {for (final f in plan.autoMapped) f.targetField.name.token: f};
    final defaultByTarget = {for (final f in plan.defaultParams) f.targetField.name.token: f};
    final requiredByTarget = {for (final f in plan.requiredParams) f.targetField.name.token: f};

    final wireTypeName = target is GLTypeDefinition ? _owner.wireTypeNameOf(target) : null;
    final entries = <String>[
      if (wireTypeName != null) "__typename: '$wireTypeName'",
    ];
    for (final tf in target.getSerializableFields(_owner.grammar.mode)) {
      final key = tf.name.token;
      final name = tf.codeName;
      final auto = autoByTarget[key];
      final withDefault = defaultByTarget[key];
      if (auto != null) {
        final expr = _mapExpr('$source.${auto.sourceField!.codeName}', auto.sourceField!.type, auto.targetField.type, 0, inMapper);
        final needsNull = _isOptional(def, auto.sourceField!.type.nullable) && !_isOptional(target, auto.targetField.type.nullable);
        entries.add('$name: ${needsNull ? (expr.contains(' ? ') ? '($expr) ?? null' : '$expr ?? null') : expr}');
      } else if (withDefault != null) {
        entries.add('$name: $source.${withDefault.sourceField!.codeName} ?? default${name.firstUp}');
      } else if (requiredByTarget.containsKey(key)) {
        entries.add(name);
      }
    }

    return _owner.codeGenUtils.createFunction(
      functionName: 'to${target.mappingCodeName.firstUp}',
      exported: true,
      arguments: params,
      returnType: targetType,
      statements: ['return ${_owner.codeGenUtils.block(entries.map((e) => '$e,').toList())};'],
    );
  }

  bool _isOptional(GLTokenWithFields owner, bool nullable) =>
      nullable && owner is GLInputDefinition && _owner.optionalNullableInputFields;

  String _mapExpr(String expr, GLType sourceType, GLType targetType, int index, bool inMapper) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) return expr;
      final element = 'e$index';
      final inner = _mapExpr(element, sourceType.inlineType, targetType.inlineType, index + 1, inMapper);
      final access = sourceType.nullable ? '?.' : '.';
      return '$expr${access}map(($element) => $inner)';
    }
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      final owner = inMapper ? mapperName(source) : _owner.resolveCodeName(sourceType.token);
      final call = '$owner.to${_owner.resolveCodeName(targetType.token).firstUp}($expr)';
      return sourceType.nullable ? '$expr == null ? $expr : $call' : call;
    }
    return expr;
  }
}
