import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLInputDefinition extends GLTokenWithFields with GLDirectivesMixin {
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

  /// Resolves the full field mapping plan from this input to [target].
  MappingPlan buildMappingPlan(
          GLTypeDefinition target,
          Map<String, GLInputDefinition> allInputs,
          Map<String, GLTypeDefinition> allTypes) =>
      MappingPlan.resolve(this, target, allInputs, allTypes);

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    final result = {...super.getImportDependecies(g)};
    final targetName = mapsToType;
    if (targetName == null) return result;

    final target = g.types[targetName]!;
    result.add(target);

    final plan = buildMappingPlan(target, g.inputs, g.types);

    // requiredParams fields whose types are complex (non-scalar) need importing
    // since they appear explicitly in the toXxx() method signature.
    for (final f in plan.requiredParams) {
      final token = g.getTokenByKey(f.targetField.type.firstType.token);
      if (filterDependecy(token, g)) result.add(token!);
    }

    // inputOnlyFields whose types are complex need importing
    // since they appear explicitly in the fromXxx() method signature.
    for (final f in plan.inputOnlyFields) {
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
