import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class JavaMappingSerializer extends GLMappingSerializer {
  final JavaSerializer _owner;
  const JavaMappingSerializer(this._owner);

  @override
  String toMethod(GLInputDefinition def, String targetType, ToMappingPlan plan) {
    // Whether the source input and target type are records (affects accessor style).
    final targetIsRecord = _owner.typesAsRecords;

    final params = [
      ...plan.requiredParams.map(
        (f) => '${_owner.serializeType(f.targetField.type)} ${f.targetField.codeName}',
      ),
      ...plan.defaultParams.map(
        (f) => '${_owner.serializeType(f.targetField.type)} default${f.targetField.codeName.firstUp}',
      ),
    ];

    if ([...plan.requiredParams, ...plan.defaultParams].any((f) => f.targetField.type.isList)) {
      def.addImport(JavaImports.list);
    }

    if (targetIsRecord) {
      // Build positional constructor args in the target type's field declaration order.
      final targetDef = _owner.grammar.types[targetType];
      final targetFields = targetDef?.getSerializableFields(_owner.grammar.mode) ?? [];

      // Index mappings by target field name for quick lookup.
      final autoByTarget = {for (final f in plan.autoMapped) f.targetField.name.token: f};
      final defaultByTarget = {for (final f in plan.defaultParams) f.targetField.name.token: f};
      final requiredByTarget = {for (final f in plan.requiredParams) f.targetField.name.token: f};

      final constructorArgs = <String>[];
      for (final tf in targetFields) {
        final name = tf.name.token;
        if (autoByTarget.containsKey(name)) {
          final f = autoByTarget[name]!;
          final getter = _getterFieldName(def, f.sourceField!, true);
          constructorArgs.add(_toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0, def));
        } else if (defaultByTarget.containsKey(name)) {
          final f = defaultByTarget[name]!;
          final getter = _getterFieldName(def, f.sourceField!, true);
          constructorArgs.add('$getter != null ? $getter : default${f.targetField.codeName.firstUp}');
        } else if (requiredByTarget.containsKey(name)) {
          constructorArgs.add(tf.codeName);
        }
      }

      final lastIdx = constructorArgs.length - 1;
      return _owner.codeGenUtils.createMethod(
        returnType: 'public $targetType',
        methodName: 'to${targetType.firstUp}',
        arguments: params,
        statements: [
          'return new $targetType(',
          ...constructorArgs.asMap().entries.map(
                (e) => e.key < lastIdx ? '${e.value},' : e.value,
              ),
          ');',
        ],
      );
    }

    // Class-style target: builder chain.
    final builderCalls = [
      ...plan.autoMapped.map((f) {
        final getter = _getterFieldName(def, f.sourceField!, true);
        final expr = _toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0, def);
        return '.${f.targetField.codeName}($expr)';
      }),
      ...plan.defaultParams.map((f) {
        final getter = _getterFieldName(def, f.sourceField!, true);
        return '.${f.targetField.codeName}($getter != null ? $getter : default${f.targetField.codeName.firstUp})';
      }),
      ...plan.requiredParams.map(
        (f) => '.${f.targetField.codeName}(${f.targetField.codeName})',
      ),
    ];

    return _owner.codeGenUtils.createMethod(
      returnType: 'public $targetType',
      methodName: 'to${targetType.firstUp}',
      arguments: params,
      statements: [
        'return $targetType.builder()',
        ...builderCalls,
        '.build();',
      ],
    );
  }

  @override
  String fromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = targetType.firstLow;
    final targetDef = _owner.grammar.types[targetType]!;

    final nullableListDefaultParams =
        plan.nullableListDefaults.map((f) => '${_owner.serializeType(f.sourceField!.type)} default${f.sourceField!.codeName.firstUp}');

    final promotedParams = plan.promoted.map(
      (f) => '${_owner.serializeType(f.sourceField!.type)} ${f.sourceField!.codeName}',
    );

    final inputOnlyParams = plan.inputOnly.map(
      (f) => '${_owner.serializeType(f.type)} ${f.codeName}',
    );

    if (plan.promoted.any((f) => f.sourceField!.type.isList) || plan.inputOnly.any((f) => f.type.isList) || plan.nullableListDefaults.isNotEmpty) {
      def.addImport(JavaImports.list);
    }

    final autoBySource = {for (final f in plan.autoMapped) f.sourceField!.name.token: f};
    final nullableListBySource = {for (final f in plan.nullableListDefaults) f.sourceField!.name.token: f};
    final promotedNames = {for (final f in plan.promoted) f.sourceField!.name.token};
    final inputOnlyNames = {for (final f in plan.inputOnly) f.name.token};

    final fields = def.getSerializableFields(_owner.grammar.mode);
    final constructorArgs = <String>[];
    for (final field in fields) {
      final fieldName = field.name.token;
      if (autoBySource.containsKey(fieldName)) {
        final f = autoBySource[fieldName]!;
        final sourceExpr = '${targetVar}.${_getterFieldName(targetDef, f.targetField, false)}';
        constructorArgs.add(_fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def));
      } else if (nullableListBySource.containsKey(fieldName)) {
        final f = nullableListBySource[fieldName]!;
        final sourceExpr = '${targetVar}.${_getterFieldName(targetDef, f.targetField, false)}';
        final expr = _fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def);
        constructorArgs.add('$expr != null ? $expr : default${f.sourceField!.codeName.firstUp}');
      } else if (promotedNames.contains(fieldName) || inputOnlyNames.contains(fieldName)) {
        constructorArgs.add(field.codeName);
      }
    }

    return _owner.codeGenUtils.createMethod(
      returnType: 'public static ${def.codeName}',
      methodName: 'from${targetType.firstUp}',
      arguments: [
        '$targetType $targetVar',
        ...nullableListDefaultParams,
        ...promotedParams,
        ...inputOnlyParams,
      ],
      statements: [
        'return new ${def.codeName}(',
        ...constructorArgs.asMap().entries.map(
              (e) => e.key < constructorArgs.length - 1 ? '${e.value},' : e.value,
            ),
        ');',
      ],
    );
  }

  /// Returns the Java expression for a toXxx() field assignment.
  /// Uses builder-chain suffix via stream().map().collect() for lists.
  String _toMappingExpr(String variable, GLType sourceType, GLType targetType, int index, GLToken context) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) {
        return variable; // same element type — pass directly
      }
      final varName = 'e$index';
      final inner = _toMappingExpr(varName, sourceType.inlineType, targetType.inlineType, index + 1, context);
      context.addImport(JavaImports.collectors);
      return JavaCodeGenUtils.streamMapCollect(receiver: variable, param: varName, body: inner, nullable: sourceType.nullable);
    }
    final sourceInput = _owner.grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      return JavaCodeGenUtils.safeCall(variable, 'to${_owner.resolveCodeName(targetType.token).firstUp}()', sourceType.nullable);
    }
    return variable; // same type — direct copy
  }

  /// Returns the Java expression for a fromXxx() field assignment.
  String _fromMappingExpr(String variable, String sourceElemToken, GLType targetType, int index, GLToken context) {
    if (targetType.isList) {
      if (sourceElemToken == targetType.firstType.token) {
        return variable; // same element type — pass directly
      }
      final varName = 'e$index';
      final inner = _fromMappingExpr(varName, sourceElemToken, targetType.inlineType, index + 1, context);
      context.addImport(JavaImports.collectors);
      return JavaCodeGenUtils.streamMapCollect(receiver: variable, param: varName, body: inner, nullable: targetType.nullable);
    }
    final sourceInput = _owner.grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = _owner.resolveCodeName(sourceElemToken);
      final targetCodeName = _owner.resolveCodeName(targetType.token);
      return JavaCodeGenUtils.nullSafeExpr(variable, '$sourceCodeName.from${targetCodeName.firstUp}($variable)', targetType.nullable);
    }
    return variable; // same type — direct copy
  }

  String _getterFieldName(GLTokenWithFields owner, GLField field, bool forInput) {
    final isRecord = forInput && _owner.inputsAsRecords || !forInput && _owner.typesAsRecords;
    if (isRecord) return "${field.codeName}()";
    return "${_owner.getterName(owner, field.name.token)}()";
  }
}
