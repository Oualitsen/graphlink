import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/graphql_string_literal.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_validation_extension.dart';
import 'package:graphlink/src/python_code_gen_utils.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/json_expressions.dart';
import 'package:graphlink/src/serializers/python/python_mapping_serializer.dart';

const pythonModelBaseName = 'GraphLinkModel';
const pythonModelBaseModule = 'client/graph_link_model';

class PythonSerializer extends GLSerializer with JsonExpressions {
  @override
  late final GLMappingSerializer mapping = PythonMappingSerializer(this);

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

  String pythonStringLiteral(String value) =>
      '"${escapeStringBody(value, quote: '"', control: (unit) => '\\x${unit.toRadixString(16).padLeft(2, '0')}')}"';

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
        ..._jsonMethods(def, fields, omitNulls: def.isOneOf),
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
        '',
        if (fields.isEmpty) 'pass' else ...fields.map(fieldDeclaration),
        if (!shouldSkipJsonMethods(def)) ..._jsonMethods(def, fields, typename: def.jsonTypeName),
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
    final discriminatorResolver = '_${name.toSnakeCase()}_by_discriminator';
    final discriminator = grammar.restDiscriminators[interface.token];

    final classSource = codeGenUtils.createClass(
      className: name,
      baseClassNames: bases.isEmpty ? [pythonModelBaseName] : bases,
      statements: [
        _modelConfig(),
        '',
        if (fields.isEmpty) 'pass' else ...fields.map(fieldDeclaration),
        if (!skipJson) ...[
          '',
          _toJsonMethod(fields),
          '',
          if (implementations.isNotEmpty && interface.syntheticImplementation != null)
            serializeSyntheticInterfaceFromJson(interface)
          else
            _fromJsonMethod(interface, fields, dispatch: implementations.isEmpty ? const [] : _dispatch(name, resolver, discriminatorResolver, discriminator)),
        ],
      ],
    );
    if (skipJson || implementations.isEmpty || interface.syntheticImplementation != null) return classSource;
    final resolverSource = codeGenUtils.createMethod(
      methodName: resolver,
      returnType: 'Dict[str, Any]',
      statements: [
        ...implementations.map((impl) => 'from ..${_subdirFor(impl)}.${moduleNameFor(impl)} import ${impl.codeName}'),
        'return {${implementations.map((impl) => '"${impl.derivedFromType?.tokenInfo.token ?? impl.tokenInfo.token}": ${impl.codeName}').join(', ')}}',
      ],
    );
    final discriminatorSource = discriminator == null
        ? null
        : codeGenUtils.createMethod(
            methodName: discriminatorResolver,
            returnType: 'Dict[Any, Any]',
            statements: [
              ...implementations.map((impl) => 'from ..${_subdirFor(impl)}.${moduleNameFor(impl)} import ${impl.codeName}'),
              'return {${implementations.map((impl) {
                final typeName = impl.derivedFromType?.tokenInfo.token ?? impl.tokenInfo.token;
                return '${pythonStringLiteral(discriminator.valueByType[typeName] ?? typeName)}: ${impl.codeName}';
              }).join(', ')}}',
            ],
          );
    return [classSource, resolverSource, if (discriminatorSource != null) discriminatorSource].join('\n\n\n');
  }

  @override
  String serializeSyntheticInterfaceFromJson(GLInterfaceDefinition interface) {
    final impl = interface.syntheticImplementation!;
    return _fromJsonMethod(
      interface,
      interface.getSerializableFields(grammar.mode),
      dispatch: [
        codeGenUtils.ifStatement(
          condition: 'cls is ${interface.codeName}',
          ifBlockStatements: [
            'from ..${_subdirFor(impl)}.${moduleNameFor(impl)} import ${impl.codeName}',
            'return ${impl.codeName}.from_json(json)',
          ],
        ),
      ],
    );
  }

  List<String> _dispatch(String name, String resolver, String discriminatorResolver, dynamic discriminator) {
    if (discriminator == null) {
      return [
        codeGenUtils.ifStatement(
          condition: 'cls is $name and "__typename" in json',
          ifBlockStatements: _typenameDispatch(name, resolver),
        ),
      ];
    }
    return [
      codeGenUtils.ifStatement(
        condition: 'cls is $name',
        ifBlockStatements: [
          codeGenUtils.ifStatement(
            condition: '"__typename" in json',
            ifBlockStatements: _typenameDispatch(name, resolver),
          ),
          codeGenUtils.constDecl('discriminator', 'json.get(${pythonStringLiteral(discriminator.field)})'),
          codeGenUtils.constDecl('target', '$discriminatorResolver().get(discriminator)'),
          codeGenUtils.ifStatement(
            condition: 'target is None',
            ifBlockStatements: [
              'raise ValueError(f"Cannot decode $name: unknown or missing \\"${discriminator.field}\\" value ({discriminator})")',
            ],
          ),
          'return target.from_json(json)',
        ],
      ),
    ];
  }

  List<String> _typenameDispatch(String name, String resolver) => [
        codeGenUtils.constDecl('typename', 'json["__typename"]'),
        codeGenUtils.constDecl('target', '$resolver().get(typename)'),
        codeGenUtils.ifStatement(
          condition: 'target is None',
          ifBlockStatements: [
            'raise ValueError(f"Invalid type {typename}. {typename} does not implement $name or not defined")',
          ],
        ),
        'return target.from_json(json)',
      ];

  List<String> _jsonMethods(GLTokenWithFields def, List<GLField> fields, {String? typename, bool omitNulls = false}) => [
        '',
        _toJsonMethod(fields, typename: typename, omitNulls: omitNulls),
        '',
        _fromJsonMethod(def, fields),
      ];

  String _toJsonMethod(List<GLField> fields, {String? typename, bool omitNulls = false}) {
    final entries = [
      if (typename != null) '"__typename": ${pythonStringLiteral(typename)}',
      for (final f in fields) '${pythonStringLiteral(f.name.token)}: ${toJsonExpr(f.type, 'self.${f.codeName}')}',
    ];
    final body = entries.isEmpty ? '' : '\n${entries.join(',\n').identPy()}\n';
    final dict = omitNulls ? 'return {k: v for k, v in {$body}.items() if v is not None}' : 'return {$body}';
    return codeGenUtils.createMethod(
      methodName: 'to_json',
      arguments: ['self'],
      returnType: 'Dict[str, Any]',
      statements: [dict],
    );
  }

  String _fromJsonMethod(GLTokenWithFields def, List<GLField> fields, {List<String> dispatch = const []}) {
    final args = fields.map((f) => '${f.codeName}=${fromJsonExpr(f.type, _jsonAccess(f))}');
    return codeGenUtils.createMethod(
      decorators: ['@classmethod'],
      methodName: 'from_json',
      arguments: ['cls', 'json: Dict[str, Any]'],
      returnType: '"${resolveCodeName(def.token)}"',
      statements: [
        ..._lazyImports(def, fields),
        ...dispatch,
        ..._requiredKeyCheck(def, fields),
        args.isEmpty ? 'return cls()' : 'return cls(\n${args.join(',\n').identPy()}\n)',
      ],
    );
  }

  List<String> _requiredKeyCheck(GLTokenWithFields def, List<GLField> fields) {
    final keys = fields.where((f) => f.initialValue == null && !f.type.nullable).map((f) => pythonStringLiteral(f.name.token));
    if (keys.isEmpty) return const [];
    return [
      codeGenUtils.forEachLoop(
        variable: 'key',
        iterable: '(${keys.join(', ')},)',
        statements: [
          codeGenUtils.ifStatement(
            condition: 'key not in json',
            ifBlockStatements: [
              "raise ValueError(f'Cannot decode ${resolveCodeName(def.token)}: missing required field \"{key}\"')",
            ],
          ),
        ],
      ),
    ];
  }

  String _jsonAccess(GLField f) {
    final key = pythonStringLiteral(f.name.token);
    if (f.initialValue != null) return 'json.get($key, ${serializeDefaultLiteral(f.type, f.initialValue)})';
    return f.type.nullable ? 'json.get($key)' : 'json[$key]';
  }

  List<String> _lazyImports(GLTokenWithFields def, List<GLField> fields) {
    final tokens = <String>{
      for (final f in fields)
        if (f.type.token != def.token && grammar.isProjectableType(f.type.token) && !grammar.isEnum(f.type.token)) f.type.token,
    };
    return [
      for (final t in tokens)
        if (grammar.getTokenByKey(t) != null) serializeImportToken(grammar.getTokenByKey(t)!),
    ];
  }

  @override
  String listToJson(GLType list, String value, String element, String body, GLImportSink? context) => _listComprehension(list, value, element, body);

  @override
  String listFromJson(GLType list, String json, String element, String body, GLImportSink? context) => _listComprehension(list, json, element, body);

  String _listComprehension(GLType list, String iterable, String element, String body) {
    if (body == element) return iterable;
    return codeGenUtils.nullSafe(
      iterable,
      codeGenUtils.listComprehension(expression: body, variable: element, iterable: iterable),
      list.nullable,
    );
  }

  @override
  String modelToJson(GLType type, String value) => codeGenUtils.nullSafe(value, '$value.to_json()', type.nullable);

  @override
  String enumFromJson(GLType type, String json) => modelFromJson(type, json);

  @override
  String modelFromJson(GLType type, String json) =>
      codeGenUtils.nullSafe(json, '${resolveCodeName(type.token)}.from_json($json)', type.nullable);

  @override
  String plainFromJson(GLType type, String json) =>
      type.token == 'Float' ? codeGenUtils.nullSafe(json, 'float($json)', type.nullable) : json;

  @override
  String scalarFromJson(GLScalarCodec codec, String json, {required bool nullable}) =>
      codeGenUtils.nullSafe(json, codec.decode(json), nullable);

  @override
  String scalarToJson(GLScalarCodec codec, String value, {required bool nullable}) =>
      codeGenUtils.nullSafe(value, codec.encode(value), nullable);

  // ── Default literals ───────────────────────────────────────────────────────

  @override
  String stringLiteral(String decoded) => pythonStringLiteral(decoded);

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
      return stringLiteral(decodeGraphqlString(value));
    }
    return pythonStringLiteral('$value');
  }

  // ── @glMapsTo ──────────────────────────────────────────────────────────────

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
    if (token is GLTokenWithFields) runtime.addAll(grammar.scalarImportsOfFields(token).map(serializeImport));
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
