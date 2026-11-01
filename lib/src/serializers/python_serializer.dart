import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/parser_extensions/gl_validation_extension.dart';
import 'package:graphlink/src/python_code_gen_utils.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';

const pythonModelBaseName = 'GraphLinkModel';
const pythonModelBaseModule = 'client/graph_link_model';

class PythonSerializer extends GLSerializer {
  final codeGenUtils = PythonCodeGenUtils();
  final bool immutableTypeFields;

  @override
  Map<String, String> get defaultTypeMap => const {
        'ID': 'str',
        'String': 'str',
        'Float': 'float',
        'Int': 'int',
        'Boolean': 'bool',
        'Null': 'None',
        'Long': 'int',
        'gqlMapStrObj': 'Dict[str, Any]',
        'dynamicValue': 'Any',
        'void': 'None',
      };

  PythonSerializer(
    super.grammar, {
    this.immutableTypeFields = true,
    super.typeMapOverrides = const {},
    super.importPrefix = '',
  });

  // ── Types ──────────────────────────────────────────────────────────────────

  @override
  String serializeType(GLType def) {
    if (def is GLVoidType) return 'None';
    String type;
    if (def is GLMapType) {
      type = 'Dict[${serializeType(def.keyType)}, ${serializeType(def.valueType)}]';
    } else if (def is GLListType) {
      type = 'List[${serializeType(def.inlineType)}]';
    } else {
      final token = def.token;
      type = getTypeNameFromGQExternal(token) ?? resolveCodeName(token);
    }
    return def.nullable ? 'Optional[$type]' : type;
  }

  String pythonStringLiteral(String value) {
    final escaped = value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\r', '\\r')
        .replaceAll('\n', '\\n');
    return '"$escaped"';
  }

  @override
  String serializeFieldDeprecation(GLField field) => '';

  @override
  String serializeEnumValueDeprecation(GLEnumValue value) {
    if (!value.isDeprecated) return '';
    final reason = (value.deprecationReason ?? 'No longer supported').replaceAll(RegExp(r'[\r\n]+'), ' ');
    return '# Deprecated: $reason';
  }

  // ── Enums ──────────────────────────────────────────────────────────────────

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    final unknown = def.unknownValue;
    final toJson = codeGenUtils.createMethod(
      methodName: 'to_json',
      arguments: ['self'],
      returnType: 'str',
      statements: [
        if (unknown != null)
          codeGenUtils.ifStatement(
            condition: 'self is ${def.codeName}.${unknown.codeName}',
            ifBlockStatements: ['raise ValueError("${def.codeName}.${unknown.codeName} cannot be serialized")'],
          ),
        'return self.value',
      ],
    );
    final fromJson = codeGenUtils.createMethod(
      decorators: ['@classmethod'],
      methodName: 'from_json',
      arguments: ['cls', 'value: str'],
      returnType: '"${def.codeName}"',
      statements: ['return cls(value)'],
    );
    final missing = unknown == null
        ? null
        : codeGenUtils.createMethod(
            decorators: ['@classmethod'],
            methodName: '_missing_',
            arguments: ['cls', 'value: object'],
            returnType: '"${def.codeName}"',
            statements: ['return cls.${unknown.codeName}'],
          );
    return codeGenUtils.createClass(
      className: def.codeName,
      baseClassNames: ['str', 'Enum'],
      statements: [
        ...def.allValues.map(doSerializeEnumValue),
        '',
        toJson,
        '',
        fromJson,
        if (missing != null) ...['', missing],
      ],
    );
  }

  @override
  String doSerializeEnumValue(GLEnumValue value) {
    final deprecation = serializeEnumValueDeprecation(value);
    final line = '${value.codeName} = ${pythonStringLiteral(value.value.token)}';
    return deprecation.isEmpty ? line : '$deprecation\n$line';
  }

  // ── Fields ─────────────────────────────────────────────────────────────────

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField, {bool isOverride = false}) =>
      fieldDeclaration(def);

  bool _isMutableDefault(Object? value) => value is List || value is Map;

  String fieldDeclaration(GLField f) {
    final type = serializeType(f.type);
    final params = <String>[];
    var plainDefault = '';
    if (f.initialValue != null) {
      final literal = serializeDefaultLiteral(f.type, f.initialValue);
      if (_isMutableDefault(f.initialValue)) {
        params.add('default_factory=${codeGenUtils.lambda([], literal)}');
      } else {
        plainDefault = literal;
        params.add('default=$literal');
      }
    } else if (f.type.nullable && !grammar.nullableFieldsRequired) {
      plainDefault = 'None';
      params.add('default=None');
    }
    final aliasNeeded = f.name.token != f.codeName;
    if (aliasNeeded) params.add('alias=${pythonStringLiteral(f.name.token)}');
    if (f.isDeprecated) {
      params.add('deprecated=${pythonStringLiteral(f.deprecationReason ?? 'No longer supported')}');
    }
    if (params.isEmpty) return '${f.codeName}: $type';
    if (params.length == 1 && plainDefault.isNotEmpty) return '${f.codeName}: $type = $plainDefault';
    return '${f.codeName}: $type = Field(${params.join(', ')})';
  }

  String _modelConfig() => immutableTypeFields
      ? 'model_config = ConfigDict(frozen=True)'
      : 'model_config = ConfigDict()';

  // ── Inputs ─────────────────────────────────────────────────────────────────

  @override
  String doSerializeInputDefinition(GLInputDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    return codeGenUtils.createClass(
      className: def.codeName,
      baseClassNames: [pythonModelBaseName],
      statements: [
        _modelConfig(),
        '',
        if (fields.isEmpty) 'pass' else ...fields.map(fieldDeclaration),
        ...generateMappingMethods(def).expand((m) => ['', m]),
      ],
    );
  }

  // ── Types & interfaces ─────────────────────────────────────────────────────

  @override
  String doSerializeTypeDefinition(GLTypeDefinition def) {
    if (def is GLInterfaceDefinition) return _serializeInterface(def);
    final fields = def.getSerializableFields(grammar.mode);
    final bases = def.interfaceNames.map((e) => resolveCodeName(e.token)).toSet().toList();
    final identity = def.getIdentityFields(grammar);
    return codeGenUtils.createClass(
      className: def.codeName,
      baseClassNames: bases.isEmpty ? [pythonModelBaseName] : bases,
      statements: [
        _modelConfig(),
        if (!shouldSkipJsonMethods(def) && def.jsonTypeName != null)
          'GL_TYPENAME: ClassVar[Optional[str]] = ${pythonStringLiteral(def.jsonTypeName!)}',
        '',
        if (fields.isEmpty) 'pass' else ...fields.map(fieldDeclaration),
        if (identity.isNotEmpty) ..._equalsAndHash(def, identity),
      ],
    );
  }

  List<String> _equalsAndHash(GLTypeDefinition def, Set<String> identityFields) {
    final names = identityFields
        .map((wire) => def.getSerializableFields(grammar.mode).firstWhere((f) => f.name.token == wire).codeName)
        .toList();
    final tuple = names.map((n) => 'self.$n').join(', ');
    final otherTuple = names.map((n) => 'other.$n').join(', ');
    return [
      '',
      codeGenUtils.createMethod(
        methodName: '__eq__',
        arguments: ['self', 'other: object'],
        returnType: 'bool',
        statements: [
          codeGenUtils.ifStatement(condition: 'self is other', ifBlockStatements: ['return True']),
          codeGenUtils.ifStatement(
            condition: 'not isinstance(other, ${def.codeName})',
            ifBlockStatements: ['return NotImplemented'],
          ),
          'return ($tuple${names.length == 1 ? ',' : ''}) == ($otherTuple${names.length == 1 ? ',' : ''})',
        ],
      ),
      '',
      codeGenUtils.createMethod(
        methodName: '__hash__',
        arguments: ['self'],
        returnType: 'int',
        statements: ['return hash(($tuple${names.length == 1 ? ',' : ''}))'],
      ),
    ];
  }

  String _serializeInterface(GLInterfaceDefinition interface) {
    final fields = interface.getSerializableFields(grammar.mode);
    final bases = interface.interfaces.map((e) => resolveCodeName(e.tokenInfo.token)).toList();
    final implementations = interface.getSerializableImplementations(mode);
    final skipJson = shouldSkipJsonMethods(interface);
    final name = interface.codeName;
    final resolver = '_${name.toSnakeCase()}_implementations';

    final classSource = codeGenUtils.createClass(
      className: name,
      baseClassNames: bases.isEmpty ? [pythonModelBaseName] : bases,
      statements: [
        _modelConfig(),
        '',
        if (fields.isEmpty) 'pass' else ...fields.map(fieldDeclaration),
        if (!skipJson && implementations.isNotEmpty) ...[
          '',
          codeGenUtils.createMethod(
            decorators: ['@model_validator(mode="wrap")', '@classmethod'],
            methodName: '_dispatch_by_typename',
            arguments: ['cls', 'data: Any', 'handler: Any'],
            returnType: 'Any',
            statements: [
              codeGenUtils.ifStatement(
                condition: 'cls is $name and isinstance(data, dict) and "__typename" in data',
                ifBlockStatements: [
                  codeGenUtils.constDecl('typename', 'data["__typename"]'),
                  codeGenUtils.constDecl('target', '$resolver().get(typename)'),
                  codeGenUtils.ifStatement(
                    condition: 'target is None',
                    ifBlockStatements: [
                      'raise ValueError(f"Invalid type {typename}. {typename} does not implement $name or not defined")',
                    ],
                  ),
                  'return target.model_validate(data)',
                ],
              ),
              'return handler(data)',
            ],
          ),
        ],
      ],
    );
    if (skipJson || implementations.isEmpty) return classSource;
    final resolverSource = codeGenUtils.createMethod(
      methodName: resolver,
      returnType: 'Dict[str, Any]',
      statements: [
        ...implementations.map((impl) => 'from ..${_subdirFor(impl)}.${moduleNameFor(impl)} import ${impl.codeName}'),
        'return {${implementations.map((impl) => '"${impl.derivedFromType?.tokenInfo.token ?? impl.tokenInfo.token}": ${impl.codeName}').join(', ')}}',
      ],
    );
    return '$classSource\n\n\n$resolverSource';
  }

  // ── Default literals ───────────────────────────────────────────────────────

  @override
  String serializeDefaultLiteral(GLType type, Object? value, {bool needsConst = false}) {
    if (value == null) return 'None';
    if (value is bool) return value ? 'True' : 'False';
    if (value is int || value is double) return '$value';
    if (value is List) {
      final innerType = type.inlineType;
      return '[${value.map((e) => serializeDefaultLiteral(innerType, e)).join(', ')}]';
    }
    if (value is Map) {
      final inputDef = grammar.inputs[type.token];
      final args = value.entries.map((e) {
        final field = inputDef?.fields.firstWhere((f) => f.name.token == e.key);
        final fieldType = field?.type ?? type;
        final key = field?.codeName ?? e.key;
        return '$key=${serializeDefaultLiteral(fieldType, e.value)}';
      }).join(', ');
      return '${resolveCodeName(type.token)}($args)';
    }
    if (value is String) {
      if (grammar.enums.containsKey(type.token)) {
        return '${resolveCodeName(type.token)}.${grammar.enumConstantName(type.token, value)}';
      }
      final content = value.startsWith('"') && value.endsWith('"') ? value.substring(1, value.length - 1) : value;
      return pythonStringLiteral(content);
    }
    return pythonStringLiteral('$value');
  }

  // ── @glMapsTo ──────────────────────────────────────────────────────────────

  String _snake(String codeName) => codeName.toSnakeCaseWords();

  @override
  String generateToMethod(GLInputDefinition def, String targetType, ToMappingPlan plan) {
    final params = [
      ...plan.requiredParams.map((f) => '${f.targetField.codeName}: ${serializeType(f.targetField.type)}'),
      ...plan.defaultParams.map((f) => 'default_${f.targetField.codeName}: ${serializeType(f.targetField.type)}'),
    ];
    final assignments = [
      ...plan.autoMapped.map((f) =>
          '${f.targetField.codeName}=${_mapToExpr('self.${f.sourceField!.codeName}', f.sourceField!.type, f.targetField.type, 0)}'),
      ...plan.defaultParams.map((f) {
        final source = 'self.${f.sourceField!.codeName}';
        return '${f.targetField.codeName}=${codeGenUtils.ternaryOp(condition: '$source is not None', positiveStatement: source, negativeStatement: 'default_${f.targetField.codeName}')}';
      }),
      ...plan.requiredParams.map((f) => '${f.targetField.codeName}=${f.targetField.codeName}'),
    ];
    return codeGenUtils.createMethod(
      methodName: 'to_${_snake(targetType)}',
      arguments: ['self', if (params.isNotEmpty) '*', ...params],
      returnType: '"$targetType"',
      statements: ['return ${codeGenUtils.callExpression(targetType, assignments)}'],
    );
  }

  @override
  String generateFromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = _snake(targetType);
    final autoMapped = plan.autoMapped.map((f) =>
        '${f.sourceField!.codeName}=${_mapFromExpr('$targetVar.${f.targetField.codeName}', f.sourceField!.type.firstType.token, f.targetField.type, 0)}');
    final nullableListParams = plan.nullableListDefaults
        .map((f) => 'default_${f.sourceField!.codeName}: Optional[${serializeType(f.sourceField!.type)}] = None');
    final nullableListAssignments = plan.nullableListDefaults.map((f) {
      final expr = _mapFromExpr('$targetVar.${f.targetField.codeName}', f.sourceField!.type.firstType.token, f.targetField.type, 0);
      final fallback = 'default_${f.sourceField!.codeName}';
      return '${f.sourceField!.codeName}=${codeGenUtils.ternaryOp(condition: '$expr is not None', positiveStatement: expr, negativeStatement: codeGenUtils.ternaryOp(condition: '$fallback is not None', positiveStatement: fallback, negativeStatement: '[]'))}';
    });
    final promotedParams = plan.promoted.map((f) => '${f.sourceField!.codeName}: ${serializeType(f.sourceField!.type)}');
    final promotedAssignments = plan.promoted.map((f) => '${f.sourceField!.codeName}=${f.sourceField!.codeName}');
    final inputOnlyAssignments = plan.inputOnly.map((f) => '${f.codeName}=${f.codeName}');

    final requiredParams = [
      '$targetVar: "$targetType"',
      ...promotedParams,
      ...plan.inputOnly.where((f) => !f.type.nullable).map((f) => '${f.codeName}: ${serializeType(f.type)}'),
    ];
    final optionalParams = [
      ...nullableListParams,
      ...plan.inputOnly.where((f) => f.type.nullable).map((f) => '${f.codeName}: ${serializeType(f.type)} = None'),
    ];
    return codeGenUtils.createMethod(
      decorators: ['@classmethod'],
      methodName: 'from_${_snake(targetType)}',
      arguments: ['cls', '*', ...requiredParams, ...optionalParams],
      returnType: '"${def.codeName}"',
      statements: [
        'return ${codeGenUtils.callExpression('cls', [
          ...autoMapped,
          ...nullableListAssignments,
          ...promotedAssignments,
          ...inputOnlyAssignments,
        ])}',
      ],
    );
  }

  String _mapToExpr(String expr, GLType sourceType, GLType targetType, int index) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) {
        return codeGenUtils.nullSafe(expr, 'list($expr)', sourceType.nullable);
      }
      final variable = 'e$index';
      final inner = _mapToExpr(variable, sourceType.inlineType, targetType.inlineType, index + 1);
      return codeGenUtils.nullSafe(
          expr, codeGenUtils.listComprehension(expression: inner, variable: variable, iterable: expr), sourceType.nullable);
    }
    final sourceInput = grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      return codeGenUtils.nullSafe(expr, '$expr.to_${_snake(resolveCodeName(targetType.token))}()', sourceType.nullable);
    }
    return expr;
  }

  String _mapFromExpr(String variable, String sourceElemToken, GLType targetType, int index) {
    if (targetType.isList) {
      if (sourceElemToken == targetType.firstType.token) {
        return codeGenUtils.nullSafe(variable, 'list($variable)', targetType.nullable);
      }
      final element = 'e$index';
      final inner = _mapFromExpr(element, sourceElemToken, targetType.inlineType, index + 1);
      return codeGenUtils.nullSafe(
          variable, codeGenUtils.listComprehension(expression: inner, variable: element, iterable: variable), targetType.nullable);
    }
    final sourceInput = grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = resolveCodeName(sourceElemToken);
      final targetCodeName = resolveCodeName(targetType.token);
      final call = '$sourceCodeName.from_${_snake(targetCodeName)}(${_snake(targetCodeName)}=$variable)';
      return codeGenUtils.nullSafe(variable, call, targetType.nullable);
    }
    return variable;
  }

  // ── Files & imports ────────────────────────────────────────────────────────

  String moduleNameFor(GLToken token) {
    final name = resolveCodeName(token.token).toSnakeCaseWords();
    return pythonReservedWords.contains(name) ? '${name}_' : name;
  }

  @override
  String getFileNameFor(GLToken token) => '${moduleNameFor(token)}.py';

  String _subdirFor(GLToken token) {
    if (token is GLEnumDefinition) return 'enums';
    if (token is GLInterfaceDefinition) return 'interfaces';
    if (token is GLTypeDefinition) return 'types';
    if (token is GLInputDefinition) return 'inputs';
    return 'types';
  }

  @override
  String serializeImportToken(GLToken token) =>
      'from ..${_subdirFor(token)}.${moduleNameFor(token)} import ${resolveCodeName(token.token)}';

  @override
  String serializeImport(String import) => import;

  @override
  String serializeWithImport(GLToken token, String data) {
    final deps = token.getImportDependecies(grammar).where((d) => d != token).toSet();
    final baseNames = <String>{
      if (token is GLTypeDefinition) ...token.interfaceNames.map((e) => e.token),
    };
    final runtime = <String>[];
    final typeChecking = <String>[];
    for (final dep in deps) {
      final line = serializeImportToken(dep);
      final isBase = baseNames.contains(dep.token);
      if (dep is GLEnumDefinition || isBase) {
        runtime.add(line);
      } else {
        typeChecking.add(line);
      }
    }
    return _assembleModule(
      body: data,
      runtimeImports: runtime,
      typeCheckingImports: typeChecking,
      usesModelBase: token is! GLEnumDefinition,
    );
  }

  String _assembleModule({
    required String body,
    List<String> runtimeImports = const [],
    List<String> typeCheckingImports = const [],
    bool usesModelBase = true,
  }) {
    final typing = <String>[
      if (body.contains('Any')) 'Any',
      if (body.contains('ClassVar')) 'ClassVar',
      if (body.contains('Dict[')) 'Dict',
      if (body.contains('List[')) 'List',
      if (body.contains('Optional[')) 'Optional',
      if (typeCheckingImports.isNotEmpty) 'TYPE_CHECKING',
    ]..sort();
    final pydantic = <String>[
      if (body.contains('ConfigDict(')) 'ConfigDict',
      if (body.contains('Field(')) 'Field',
      if (body.contains('model_validator')) 'model_validator',
    ];
    final lines = <String>[
      'from __future__ import annotations',
      '',
      if (body.contains('Enum')) 'from enum import Enum',
      if (typing.isNotEmpty) 'from typing import ${typing.join(', ')}',
      '',
      if (pydantic.isNotEmpty) 'from pydantic import ${pydantic.join(', ')}',
      if (usesModelBase && body.contains(pythonModelBaseName))
        'from ..$pythonModelBaseModule import $pythonModelBaseName'.replaceAll('/', '.'),
      ...{...runtimeImports},
      if (typeCheckingImports.isNotEmpty) ...[
        '',
        'if TYPE_CHECKING:',
        ...{...typeCheckingImports}.map((l) => l.identPy()),
      ],
      '',
      '',
      body.trimRight(),
    ];
    return lines.join('\n').replaceAll(RegExp(r'\n{4,}'), '\n\n\n');
  }

  @override
  String serializeGlClass(GLClassModel theClass, {bool withImports = true}) {
    if (!withImports || theClass.importDepencies.isEmpty) {
      return super.serializeGlClass(theClass, withImports: withImports);
    }
    final tokenImports = theClass.importDepencies.map(serializeImportToken).where((l) => l.trim().isNotEmpty);
    return super.serializeGlClass(
      GLClassModel(imports: {...tokenImports, ...theClass.imports}.toList(), body: theClass.body),
      withImports: withImports,
    );
  }
}
