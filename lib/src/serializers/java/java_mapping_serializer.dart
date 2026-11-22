import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
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

  @override
  String mapperFileName(GLTokenWithFields def) => '${mapperName(def)}.java';

  @override
  String mapperImport(GLTokenWithFields def) => 'import ${_owner.importPrefix}.mappers.${mapperName(def)};';

  @override
  String mapperFile(GLTokenWithFields def, List<String> methods, List<String> imports) {
    final body = _owner.codeGenUtils.createClass(
      className: mapperName(def),
      finalClass: true,
      statements: [
        'private ${mapperName(def)}() {}',
        ...methods.expand((m) => ['', m]),
      ],
    );
    final extra = [JavaImports.list, JavaImports.collectors].map((i) => 'import $i;');
    return [...{...imports, ...extra}, '', body].join('\n');
  }

  @override
  String mapperMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan) {
    final targetType = _owner.mappingTypeName(target);
    final sourceType = _owner.mappingTypeName(def);
    final params = [
      '$sourceType source',
      ...plan.requiredParams.map((f) => '${_owner.serializeType(f.targetField.type)} ${f.targetField.codeName}'),
      ...plan.defaultParams.map(
        (f) => '${_owner.serializeType(f.targetField.type)} default${f.targetField.codeName.firstUp}',
      ),
    ];

    String read(GLField f) => 'source.${_accessor(def, f)}';
    final assignments = <String, String>{
      for (final f in plan.autoMapped)
        f.targetField.codeName: _mapperExpr(read(f.sourceField!), f.sourceField!.type, f.targetField.type, 0),
      for (final f in plan.defaultParams)
        f.targetField.codeName: _owner.codeGenUtils.ternaryOp(
          condition: '${read(f.sourceField!)} != null',
          positiveStatement: read(f.sourceField!),
          negativeStatement: 'default${f.targetField.codeName.firstUp}',
        ),
      for (final f in plan.requiredParams) f.targetField.codeName: f.targetField.codeName,
    };

    return _owner.codeGenUtils.createMethod(
      returnType: 'public static $targetType',
      methodName: 'to${target.mappingCodeName.firstUp}',
      arguments: params,
      statements: _construct(target, assignments),
    );
  }

  List<String> _construct(GLTokenWithFields target, Map<String, String> assignments) {
    final targetType = _owner.mappingTypeName(target);
    final targetFields = target.getSerializableFields(_owner.grammar.mode);
    if (target.isExternalType) {
      return [
        '$targetType target = new $targetType();',
        for (final e in assignments.entries) 'target.${_setter(target, e.key)}(${e.value});',
        'return target;',
      ];
    }
    if (_owner.typesAsRecords && target is! GLInputDefinition || _owner.inputsAsRecords && target is GLInputDefinition) {
      final args = [for (final f in targetFields) if (assignments.containsKey(f.codeName)) assignments[f.codeName]!];
      return ['return new $targetType(', ...args.asMap().entries.map((e) => e.key < args.length - 1 ? '${e.value},' : e.value), ');'];
    }
    return [
      'return $targetType.builder()',
      ...assignments.entries.map((e) => '.${e.key}(${e.value})'),
      '.build();',
    ];
  }

  String _setter(GLTokenWithFields target, String fieldName) => 'set${fieldName.firstUp}';

  String _accessor(GLTokenWithFields owner, GLField field) {
    final asRecord = !owner.isExternalType &&
        (owner is GLInputDefinition ? _owner.inputsAsRecords : _owner.typesAsRecords);
    return asRecord ? '${field.codeName}()' : '${_owner.getterName(owner, field.name.token)}()';
  }

  String _mapperExpr(String variable, GLType sourceType, GLType targetType, int index) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _mapperExpr(varName, sourceType.inlineType, targetType.inlineType, index + 1);
      return JavaCodeGenUtils.streamMapCollect(receiver: variable, param: varName, body: inner, nullable: sourceType.nullable);
    }
    final source = _owner.grammar.mappingToken(sourceType.token);
    if (source != null && source.mapsToTarget(targetType.token)) {
      final call = '${mapperName(source)}.to${_owner.resolveCodeName(targetType.token).firstUp}($variable)';
      return sourceType.nullable ? _owner.codeGenUtils.ternaryOp(condition: '$variable != null', positiveStatement: call, negativeStatement: 'null') : call;
    }
    return variable;
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
