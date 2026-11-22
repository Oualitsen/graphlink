import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/swift_code_gen_utils.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class SwiftMappingSerializer extends GLMappingSerializer {
  final SwiftSerializer _owner;
  const SwiftMappingSerializer(this._owner);

  /// `public func to<Target>(...) -> Target` — an instance method on the
  /// input struct. Unlike [generateFromMethod], this stays an *instance*
  /// method (called as `input.toUser()`), matching the plan's own example.
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
        args.add('$name: ${_toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0)}');
      } else if (defaultByTarget.containsKey(key)) {
        final f = defaultByTarget[key]!;
        final getter = f.sourceField!.codeName;
        // Nil-coalescing directly expresses "use the value if present,
        // otherwise the caller-supplied default" — no if/else needed the
        // way Kotlin's `if (x != null) x else default` spells it out.
        args.add('$name: $getter ?? default${f.targetField.codeName.firstUp}');
      } else if (requiredByTarget.containsKey(key)) {
        args.add('$name: $name');
      }
    }

    final argsStr = args.join(',\n').ident();
    return 'public ${_owner.codeGenUtils.method(
      returnType: targetType,
      methodName: 'to${targetType.firstUp}',
      arguments: params,
      statements: ['return $targetType(\n$argsStr\n)'],
    )}';
  }

  /// Source (input) → target (type) conversion expression for one field
  /// during `toXxx()`. List nullability uses [SwiftCodeGenUtils.mapCall]'s
  /// `chainThroughOptional` (see its doc — iterating a nullable list's
  /// elements needs `?.map`, not `Optional.map`). The nested-mapped-input
  /// case (`variable.toPeriod()` / `variable?.toPeriod()`) is a plain method
  /// call, not `.map` at all, so it has no such ambiguity — `.toPeriod()` is
  /// not a `Sequence` member, so optional chaining is unambiguous here.
  String _toMappingExpr(String variable, GLType sourceType, GLType targetType, int index) {
    if (sourceType is GLListType) {
      if (sourceType.firstType.token == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _toMappingExpr(varName, sourceType.inlineType, targetType.inlineType, index + 1);
      return SwiftCodeGenUtils.mapCall(
          receiver: variable, param: varName, body: inner, chainThroughOptional: sourceType.nullable);
    }
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      final targetCodeName = _owner.resolveCodeName(targetType.token);
      return SwiftCodeGenUtils.safeCall(variable, 'to${targetCodeName.firstUp}()', sourceType.nullable);
    }
    return variable;
  }

}
