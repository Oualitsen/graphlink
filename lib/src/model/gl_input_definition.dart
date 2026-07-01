import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/code_name_mixin.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

class GLInputDefinition extends GLTokenWithFields with GLDirectivesMixin, CodeNameMixin {
  @override
  String get wireName => token;
  final String declaredName;
  GLInputDefinition(
      {required List<GLDirectiveValue> directives,
      required TokenInfo name,
      required this.declaredName,
      required List<GLField> fields,
      required bool extension,
      String? documentation})
      : super(name, extension, fields, documentation: documentation) {
    directives.forEach(addDirective);
  }

  /// Returns the target type name from @glMapsTo, or null if not declared.
  String? get mapsToType =>
      getDirectiveByName(glMapsTo)?.getArgValueAsString(glMapsToType);

  ToMappingPlan buildToMappingPlan(
          GLTypeDefinition target,
          Map<String, GLInputDefinition> allInputs,
          Map<String, GLTypeDefinition> allTypes,
          CodeGenerationMode mode, {
          Map<String, String> typeMap = const {},
          }) =>
      ToMappingPlan.resolve(this, target, allInputs, allTypes, mode, typeMap: typeMap);

  FromMappingPlan buildFromMappingPlan(
          GLTypeDefinition target,
          Map<String, GLInputDefinition> allInputs,
          Map<String, GLTypeDefinition> allTypes,
          CodeGenerationMode mode, {
          Map<String, String> typeMap = const {},
          }) =>
      FromMappingPlan.resolve(this, target, allInputs, allTypes, mode, typeMap: typeMap);

  void _collectDefaultValueDeps(
      Object? value, String typeName, GLParser g, Map<String, GLToken> result) {
    final inputDef = g.inputs[typeName];
    if (inputDef == null) return;
    if (value is Map<String, Object?>) {
      for (final entry in value.entries) {
        final subField = inputDef.getFieldByName(entry.key);
        if (subField == null) continue;
        final subTypeName = subField.type.firstType.token;
        final subToken = g.getTokenByKey(subTypeName);
        if (subToken != null && filterDependecy(subToken, g)) {
          result[subToken.token] = subToken;
        }
        _collectDefaultValueDeps(entry.value, subTypeName, g, result);
      }
    } else if (value is List<Object?>) {
      for (final element in value) {
        _collectDefaultValueDeps(element, typeName, g, result);
      }
    }
  }

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    final result = {...super.getImportDependecies(g)};

    final extraDeps = <String, GLToken>{};
    for (final f in getSerializableFields(g.mode)) {
      if (f.initialValue == null) continue;
      _collectDefaultValueDeps(f.initialValue, f.type.firstType.token, g, extraDeps);
    }
    result.addAll(extraDeps.values);

    final targetName = mapsToType;
    if (targetName == null) return result;

    if (g.mode == CodeGenerationMode.client && !g.projectedTypes.containsKey(targetName)) {
      return result;
    }


    final target = g.types[targetName]!;
    result.add(target);

    final toPlan = buildToMappingPlan(target, g.inputs, g.types, g.mode, typeMap: g.typeMap);
    final fromPlan = buildFromMappingPlan(target, g.inputs, g.types, g.mode, typeMap: g.typeMap);

    for (final f in toPlan.requiredParams) {
      final token = g.getTokenByKey(f.targetField.type.firstType.token);
      if (filterDependecy(token, g)) result.add(token!);
    }

    for (final f in fromPlan.inputOnly) {
      final token = g.getTokenByKey(f.type.firstType.token);
      if (filterDependecy(token, g)) result.add(token!);
    }

    return result;
  }

  @override
  String toString() {
    return 'InputType{fields: $fields, name: $tokenInfo}';
  }

  @override
  void merge<T extends GLExtensibleToken>(T other) {
    if (other is GLInputDefinition) {
      other.getDirectives().forEach(addDirective);
      other.fields.forEach(addOrMergeField);
    }
  }
}
