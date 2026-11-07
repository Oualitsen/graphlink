import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/reserved_words.dart';
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

  /// `public static func from<Target>(_ target: Target, ...) -> Self` — a
  /// static factory (called as `CreateUserInput.fromUser(user)`), mirroring
  /// how `fromJson` is static too. The first parameter is unlabeled (`_`),
  /// matching every other generated `fromXxx`-shaped factory.
  @override
  String fromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan) {
    // Unlike every other identifier in this file, `targetVar` isn't a
    // `codeName` — it's synthesized here from the target type name
    // (`Person` -> `person`), so it never passes through the
    // swiftReservedWords-driven codeName rename and needs its own guard
    // against colliding with a Swift keyword (e.g. a type named `Self`).
    final lowered = targetType.firstLow;
    final targetVar = swiftReservedWords.contains(lowered) ? '${lowered}_' : lowered;

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
        args.add('$name: ${_fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0)}');
      } else if (nullableListBySource.containsKey(key)) {
        final f = nullableListBySource[key]!;
        final sourceExpr = '$targetVar.${f.targetField.codeName}';
        final expr = _fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0);
        args.add('$name: $expr ?? default${f.sourceField!.codeName.firstUp}');
      } else if (promotedNames.contains(key) || inputOnlyNames.contains(key)) {
        args.add('$name: $name');
      }
    }

    final allParams = [
      '_ $targetVar: $targetType',
      ...nullableListDefaultParams,
      ...promotedParams,
      ...inputOnlyParams,
    ];

    final argsStr = args.join(',\n').ident();
    return 'public static ${_owner.codeGenUtils.method(
      returnType: def.codeName,
      methodName: 'from${targetType.firstUp}',
      arguments: allParams,
      statements: ['return ${def.codeName}(\n$argsStr\n)'],
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
    final sourceInput = _owner.grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      final targetCodeName = _owner.resolveCodeName(targetType.token);
      return SwiftCodeGenUtils.safeCall(variable, 'to${targetCodeName.firstUp}()', sourceType.nullable);
    }
    return variable;
  }

  /// Target (type) → source (input) reverse-conversion expression during
  /// `fromXxx()`. The nested-mapped-input case calls a *static* factory
  /// (`PeriodInput.fromPeriod(value)`) rather than an instance method, so —
  /// same reasoning as the enum/projectable branches of [_fromJsonExpr] —
  /// it needs `Optional.map` (plain `.map`, never `?.map`) to transform the
  /// whole optional value via a closure, not optional-chaining into some
  /// member of the wrapped value itself.
  String _fromMappingExpr(String variable, String sourceElemToken, GLType targetType, int index) {
    if (targetType is GLListType) {
      if (sourceElemToken == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _fromMappingExpr(varName, sourceElemToken, targetType.inlineType, index + 1);
      return SwiftCodeGenUtils.mapCall(
          receiver: variable, param: varName, body: inner, chainThroughOptional: targetType.nullable);
    }
    final sourceInput = _owner.grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = _owner.resolveCodeName(sourceElemToken);
      final targetCodeName = _owner.resolveCodeName(targetType.token);
      if (targetType.nullable) {
        return SwiftCodeGenUtils.mapCall(
            receiver: variable, body: '$sourceCodeName.from${targetCodeName.firstUp}(\$0)');
      }
      return '$sourceCodeName.from${targetCodeName.firstUp}($variable)';
    }
    return variable;
  }
}
