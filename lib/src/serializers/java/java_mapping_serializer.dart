import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

class JavaMappingSerializer extends GLMappingSerializer {
  final JavaSerializer _owner;
  const JavaMappingSerializer(this._owner);

  @override
  String toMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) {
    final targetType = target.mappingCodeName;
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
      final targetFields = target.getSerializableFields(_owner.grammar.mode);

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
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      return JavaCodeGenUtils.safeCall(variable, 'to${_owner.resolveCodeName(targetType.token).firstUp}()', sourceType.nullable);
    }
    return variable; // same type — direct copy
  }

  String _getterFieldName(GLTokenWithFields owner, GLField field, bool forInput) {
    final isRecord = forInput && _owner.inputsAsRecords || !forInput && _owner.typesAsRecords;
    if (isRecord) return "${field.codeName}()";
    return "${_owner.getterName(owner, field.name.token)}()";
  }
}
