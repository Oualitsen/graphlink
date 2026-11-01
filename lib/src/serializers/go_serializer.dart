import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/go_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/parser_extensions/gl_validation_extension.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';

const _importBySelector = {
  'json': 'encoding/json',
  'fmt': 'fmt',
  'reflect': 'reflect',
  'context': 'context',
  'http': 'net/http',
  'sync': 'sync',
  'atomic': 'sync/atomic',
  'time': 'time',
  'bytes': 'bytes',
  'strings': 'strings',
  'strconv': 'strconv',
  'io': 'io',
  'errors': 'errors',
  'hex': 'encoding/hex',
  'sha256': 'crypto/sha256',
  'rand': 'math/rand',
  'sort': 'sort',
  'url': 'net/url',
  'multipart': 'mime/multipart',
  'textproto': 'net/textproto',
  'os': 'os',
  'big': 'math/big',
  'math': 'math',
  'fnv': 'hash/fnv',
  'filepath': 'path/filepath',
  'mime': 'mime',
  'websocket': 'github.com/coder/websocket',
  'uuid': 'github.com/google/uuid',
};

class GoSerializer extends GLSerializer {
  final codeGenUtils = GoCodeGenUtils();
  final String packageName;

  @override
  Map<String, String> get defaultTypeMap => const {
        'ID': 'string',
        'String': 'string',
        'Float': 'float64',
        'Int': 'int',
        'Boolean': 'bool',
        'Null': 'any',
        'Long': 'int64',
        'gqlMapStrObj': 'map[string]any',
        'dynamicValue': 'any',
        'void': '',
      };

  GoSerializer(
    super.grammar, {
    this.packageName = 'graphlink',
    super.typeMapOverrides = const {},
    super.importPrefix = '',
  });

  // ── Types ──────────────────────────────────────────────────────────────────

  bool isInterfaceLike(String token) =>
      grammar.interfaces.containsKey(token) ||
      grammar.projectedInterfaces.containsKey(token) ||
      grammar.unions.containsKey(token);

  String _baseTypeName(GLType def) {
    final token = def.token;
    return getTypeNameFromGQExternal(token) ?? resolveCodeName(token);
  }

  /// True for Go types whose zero value already encodes "absent".
  bool _isNilable(GLType def) {
    if (def is GLListType || def is GLMapType) return true;
    final name = _baseTypeName(def);
    return name == 'any' || name.startsWith('map[') || name.startsWith('[]') || isInterfaceLike(def.token);
  }

  bool usesPointer(GLType def) => def.nullable && !_isNilable(def);

  @override
  String serializeType(GLType def) {
    if (def is GLVoidType) return '';
    final base = nonPointerType(def);
    return usesPointer(def) ? '*$base' : base;
  }

  String nonPointerType(GLType def) {
    if (def is GLMapType) return 'map[${serializeType(def.keyType)}]${serializeType(def.valueType)}';
    if (def is GLListType) return '[]${serializeType(def.inlineType)}';
    return _baseTypeName(def);
  }

  String stringLiteral(String value) {
    final escaped = value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\r', '\\r')
        .replaceAll('\n', '\\n')
        .replaceAll('\t', '\\t');
    return '"$escaped"';
  }

  @override
  String serializeFieldDeprecation(GLField field) {
    if (!field.isDeprecated) return '';
    final reason = (field.deprecationReason ?? 'No longer supported').replaceAll(RegExp(r'[\r\n]+'), ' ');
    return '// Deprecated: $reason\n';
  }

  @override
  String serializeEnumValueDeprecation(GLEnumValue value) {
    if (!value.isDeprecated) return '';
    final reason = (value.deprecationReason ?? 'No longer supported').replaceAll(RegExp(r'[\r\n]+'), ' ');
    return '// Deprecated: $reason';
  }

  // ── Enums ──────────────────────────────────────────────────────────────────

  String enumConstantName(GLEnumDefinition def, GLEnumValue value) => '${def.codeName}${value.codeName.firstUp}';

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    final name = def.codeName;
    final unknown = def.unknownValue;
    final known = def.values;
    final constants = def.allValues.map(doSerializeEnumValueFor(def)).join('\n');
    final knownNames = known.map((v) => enumConstantName(def, v)).join(', ');
    final marshal = codeGenUtils.createMethod(
      receiver: 'v $name',
      methodName: 'MarshalJSON',
      returnType: '([]byte, error)',
      statements: [
        if (known.isNotEmpty)
          codeGenUtils.ifStatement(
            condition: 'v == ${knownNames.split(', ').join(' || v == ')}',
            ifBlockStatements: ['return json.Marshal(string(v))'],
          ),
        'return nil, fmt.Errorf("$name %q cannot be serialized", string(v))',
      ],
    );
    final unmarshal = codeGenUtils.createMethod(
      receiver: 'v *$name',
      methodName: 'UnmarshalJSON',
      returnType: 'error',
      arguments: ['data []byte'],
      statements: [
        'var s string',
        codeGenUtils.ifStatement(
          condition: 'err := json.Unmarshal(data, &s); err != nil',
          ifBlockStatements: ['return err'],
        ),
        if (known.isNotEmpty)
          codeGenUtils.switchStatement(
            expression: '$name(s)',
            cases: [
              GoCaseBranch(caseValue: knownNames, statement: '*v = $name(s)\nreturn nil'),
            ],
          ),
        if (unknown != null) ...[
          '*v = ${enumConstantName(def, unknown)}',
          'return nil',
        ] else
          'return fmt.Errorf("invalid $name: %s", s)',
      ],
    );
    return [
      'type $name string',
      'const (\n${constants.identGo()}\n)',
      marshal,
      unmarshal,
    ].join('\n\n');
  }

  String Function(GLEnumValue) doSerializeEnumValueFor(GLEnumDefinition def) => (value) {
        final deprecation = serializeEnumValueDeprecation(value);
        final line = '${enumConstantName(def, value)} ${def.codeName} = ${stringLiteral(value.value.token)}';
        return deprecation.isEmpty ? line : '$deprecation\n$line';
      };

  @override
  String doSerializeEnumValue(GLEnumValue value) => value.codeName;

  // ── Fields ─────────────────────────────────────────────────────────────────

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField, {bool isOverride = false}) =>
      '${def.codeName} ${serializeType(def.type)} `json:"${def.name.token}"`';

  List<GLField> serializableFields(dynamic def) =>
      (def.getSerializableFields(grammar.mode) as List<GLField>).where((f) => serializeField(f, true, true).isNotEmpty).toList();

  String _fieldLines(List<GLField> fields) => fields.map((f) {
        final line = serializeField(f, true, true);
        return line.trimRight();
      }).join('\n');

  // ── Inputs ─────────────────────────────────────────────────────────────────

  @override
  String doSerializeInputDefinition(GLInputDefinition def) {
    final fields = serializableFields(def);
    final withDefaults = fields.where((f) => f.initialValue != null).toList();
    return [
      codeGenUtils.structDecl(def.codeName, [_fieldLines(fields)]),
      if (withDefaults.isNotEmpty) _constructorWithDefaults(def.codeName, withDefaults),
      ...generateMappingMethods(def),
    ].join('\n\n');
  }

  String _constructorWithDefaults(String name, List<GLField> withDefaults) {
    final assignments = withDefaults
        .map((f) => '${f.codeName}: ${serializeDefaultLiteral(f.type, f.initialValue)},')
        .join('\n');
    return codeGenUtils.createMethod(
      methodName: 'New$name',
      returnType: name,
      statements: ['return $name{\n${assignments.identGo()}\n}'],
    );
  }

  // ── Types & interfaces ─────────────────────────────────────────────────────

  Set<String> allInterfaceTokens(GLTypeDefinition def) {
    final result = <String>{};
    void visit(String token) {
      if (!result.add(token)) return;
      final iface = grammar.interfaces[token] ?? grammar.projectedInterfaces[token];
      iface?.interfaceNames.forEach((n) => visit(n.token));
    }

    def.interfaceNames.forEach((n) => visit(n.token));
    return result;
  }

  GLInterfaceDefinition? _interfaceFor(String token) =>
      grammar.interfaces[token] ?? grammar.projectedInterfaces[token];

  @override
  String doSerializeTypeDefinition(GLTypeDefinition def) {
    if (def is GLInterfaceDefinition) return _serializeInterface(def);
    final name = def.codeName;
    final fields = serializableFields(def);
    final blocks = <String>[
      codeGenUtils.structDecl(name, [_fieldLines(fields)]),
    ];
    for (final token in allInterfaceTokens(def)) {
      final iface = _interfaceFor(token);
      final ifaceName = iface?.codeName ?? resolveCodeName(token);
      blocks.add(codeGenUtils.createMethod(receiver: 'v $name', methodName: 'Is$ifaceName'));
      if (iface == null) continue;
      for (final f in serializableFields(iface)) {
        final own = fields.where((o) => o.name.token == f.name.token).firstOrNullGl;
        if (own == null) continue;
        blocks.add(_getter(name, own, f));
      }
    }
    if (!shouldSkipJsonMethods(def)) {
      final typeName = def.jsonTypeName;
      if (typeName != null) blocks.add(_marshalWithTypename(name, typeName));
      final polymorphic = fields.where((f) => _isPolymorphic(f.type)).toList();
      if (polymorphic.isNotEmpty) blocks.add(_unmarshalWithPolymorphicFields(name, polymorphic));
    }
    final identity = def.getIdentityFields(grammar);
    if (identity.isNotEmpty) blocks.add(_equals(name, fields, identity));
    return blocks.join('\n\n');
  }

  String _getter(String typeName, GLField own, GLField declared) {
    final ownType = serializeType(own.type);
    final declaredType = serializeType(declared.type);
    final accessor = 'v.${own.codeName}';
    final String body;
    if (ownType == declaredType) {
      body = 'return $accessor';
    } else if (declaredType == '*$ownType') {
      body = 'copied := $accessor\nreturn &copied';
    } else if (ownType == '*$declaredType') {
      body = codeGenUtils.ifStatement(
            condition: '$accessor == nil',
            ifBlockStatements: ['var zero $declaredType', 'return zero'],
          ) +
          '\nreturn *$accessor';
    } else {
      body = 'return $accessor';
    }
    return codeGenUtils.createMethod(
      receiver: 'v $typeName',
      methodName: 'Get${declared.codeName}',
      returnType: declaredType,
      statements: [body],
    );
  }

  String _marshalWithTypename(String name, String typeName) {
    return codeGenUtils.createMethod(
      receiver: 'v $name',
      methodName: 'MarshalJSON',
      returnType: '([]byte, error)',
      statements: [
        'type alias $name',
        'return json.Marshal(struct {\n${'alias\nTypename string `json:"__typename"`'.identGo()}\n}{alias(v), ${stringLiteral(typeName)}})',
      ],
    );
  }

  String _equals(String name, List<GLField> fields, Set<String> identityWireNames) {
    final names = identityWireNames
        .map((wire) => fields.where((f) => f.name.token == wire).firstOrNullGl?.codeName)
        .whereType<String>()
        .toList();
    if (names.isEmpty) return '';
    return codeGenUtils.createMethod(
      receiver: 'v $name',
      methodName: 'Equals',
      arguments: ['other $name'],
      returnType: 'bool',
      statements: ['return ${names.map((n) => 'reflect.DeepEqual(v.$n, other.$n)').join(' && ')}'],
    );
  }

  // ── Polymorphic decoding ───────────────────────────────────────────────────

  bool _isPolymorphic(GLType type) {
    if (type is GLMapType) return false;
    final inner = type.inlineType;
    if (type is GLListType) return _isPolymorphic(inner);
    return isInterfaceLike(type.token);
  }

  String decoderFor(GLType type) {
    if (type is GLListType) {
      final elem = serializeType(type.inlineType);
      return 'func(r json.RawMessage) ([]$elem, error) {\n'
          '\treturn glDecodeList(r, ${decoderFor(type.inlineType).identGo().trimLeft()})\n'
          '}';
    }
    return 'unmarshal${resolveCodeName(type.token)}';
  }

  String _unmarshalWithPolymorphicFields(String name, List<GLField> polymorphic) {
    final auxFields = polymorphic.map((f) => '${f.codeName} json.RawMessage `json:"${f.name.token}"`').join('\n');
    final statements = <String>[
      'type alias $name',
      'aux := struct {\n${'*alias\n$auxFields'.identGo()}\n}{alias: (*alias)(v)}',
      codeGenUtils.ifStatement(
        condition: 'err := json.Unmarshal(data, &aux); err != nil',
        ifBlockStatements: ['return err'],
      ),
      'var err error',
      for (final f in polymorphic) ...[
        'v.${f.codeName}, err = ${decoderFor(f.type)}(aux.${f.codeName})',
        codeGenUtils.nilCheckReturn('err'),
      ],
      'return nil',
    ];
    return codeGenUtils.createMethod(
      receiver: 'v *$name',
      methodName: 'UnmarshalJSON',
      arguments: ['data []byte'],
      returnType: 'error',
      statements: statements,
    );
  }

  String _serializeInterface(GLInterfaceDefinition interface) {
    final name = interface.codeName;
    final fields = serializableFields(interface);
    final parents = interface.interfaces.map((e) => e.codeName).toList();
    final members = <String>[
      ...parents,
      'Is$name()',
      ...fields.map((f) => 'Get${f.codeName}() ${serializeType(f.type)}'),
    ];
    final blocks = <String>[codeGenUtils.interfaceDecl(name, members)];
    final implementations = interface.getSerializableImplementations(mode);
    if (!shouldSkipJsonMethods(interface) && implementations.isNotEmpty) {
      blocks.add(_dispatchFunction(name, implementations));
    }
    return blocks.join('\n\n');
  }

  String _dispatchFunction(String name, Set<GLTypeDefinition> implementations) {
    final cases = implementations.map((impl) {
      final wire = impl.derivedFromType?.tokenInfo.token ?? impl.tokenInfo.token;
      return GoCaseBranch(
        caseValue: stringLiteral(wire),
        statement: [
          'var v ${impl.codeName}',
          codeGenUtils.ifStatement(
            condition: 'err := json.Unmarshal(data, &v); err != nil',
            ifBlockStatements: ['return nil, err'],
          ),
          'return v, nil',
        ].join('\n'),
      );
    }).toList();
    return codeGenUtils.createMethod(
      methodName: 'unmarshal$name',
      arguments: ['data json.RawMessage'],
      returnType: '($name, error)',
      statements: [
        codeGenUtils.ifStatement(
          condition: 'glIsNull(data)',
          ifBlockStatements: ['return nil, nil'],
        ),
        'var probe struct {\n${'Typename string `json:"__typename"`'.identGo()}\n}',
        codeGenUtils.ifStatement(
          condition: 'err := json.Unmarshal(data, &probe); err != nil',
          ifBlockStatements: ['return nil, err'],
        ),
        codeGenUtils.switchStatement(
          expression: 'probe.Typename',
          cases: cases,
          defaultStatements: [
            'return nil, fmt.Errorf("Invalid type %s. %s does not implement $name or not defined", probe.Typename, probe.Typename)',
          ],
        ),
      ],
    );
  }

  // ── Default literals ───────────────────────────────────────────────────────

  @override
  String serializeDefaultLiteral(GLType type, Object? value, {bool needsConst = false}) {
    if (value == null) return 'nil';
    final literal = _literalFor(type, value);
    return usesPointer(type) ? 'Ptr[${nonPointerType(type)}]($literal)' : literal;
  }

  String _literalFor(GLType type, Object value) {
    if (value is bool || value is int || value is double) return '$value';
    if (value is List) {
      final innerType = type.inlineType;
      final items = value.map((e) => serializeDefaultLiteral(innerType, e)).join(', ');
      return '${nonPointerType(type)}{$items}';
    }
    if (value is Map) {
      final inputDef = grammar.inputs[type.token];
      final args = value.entries.map((e) {
        final field = inputDef?.fields.firstWhere((f) => f.name.token == e.key);
        final fieldType = field?.type ?? type;
        final key = field?.codeName ?? e.key;
        return '$key: ${serializeDefaultLiteral(fieldType, e.value)}';
      }).join(', ');
      return '${resolveCodeName(type.token)}{$args}';
    }
    if (value is String) {
      final enumDef = grammar.enums[type.token];
      if (enumDef != null) {
        return '${enumDef.codeName}${grammar.enumConstantName(type.token, value).firstUp}';
      }
      final content = value.startsWith('"') && value.endsWith('"') ? value.substring(1, value.length - 1) : value;
      return stringLiteral(content);
    }
    return stringLiteral('$value');
  }

  // ── @glMapsTo ──────────────────────────────────────────────────────────────

  String _lowerFirst(String s) => s.firstLow;

  @override
  String generateToMethod(GLInputDefinition def, String targetType, ToMappingPlan plan) {
    final params = [
      ...plan.requiredParams
          .map((f) => '${_lowerFirst(f.targetField.codeName)} ${serializeType(f.targetField.type)}'),
      ...plan.defaultParams.map((f) => 'default${f.targetField.codeName.firstUp} ${serializeType(f.targetField.type)}'),
    ];
    final prelude = <String>[];
    final assignments = [
      ...plan.autoMapped.map((f) =>
          '${f.targetField.codeName}: ${_mapToExpr('v.${f.sourceField!.codeName}', f.sourceField!.type, f.targetField.type, 0)},'),
      ...plan.defaultParams.map((f) {
        final local = 'resolved${f.targetField.codeName.firstUp}';
        final source = 'v.${f.sourceField!.codeName}';
        prelude.add(codeGenUtils.constDecl(local, 'default${f.targetField.codeName.firstUp}'));
        prelude.add(codeGenUtils.ifStatement(
          condition: '$source != nil',
          ifBlockStatements: ['$local = ${usesPointer(f.sourceField!.type) ? '*$source' : source}'],
        ));
        return '${f.targetField.codeName}: $local,';
      }),
      ...plan.requiredParams
          .map((f) => '${f.targetField.codeName}: ${_lowerFirst(f.targetField.codeName)},'),
    ];
    return codeGenUtils.createMethod(
      receiver: 'v ${def.codeName}',
      methodName: 'To${targetType.firstUp}',
      arguments: params,
      returnType: targetType,
      statements: [...prelude, 'return $targetType{\n${assignments.join('\n').identGo()}\n}'],
    );
  }

  @override
  String generateFromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = targetType.firstLow;
    final preludes = <String>[];
    final assignments = <String>[
      ...plan.autoMapped.map((f) =>
          '${f.sourceField!.codeName}: ${_mapFromExpr('$targetVar.${f.targetField.codeName}', f.sourceField!.type.firstType.token, f.targetField.type, 0)},'),
      ...plan.nullableListDefaults.map((f) {
        final expr = _mapFromExpr(
            '$targetVar.${f.targetField.codeName}', f.sourceField!.type.firstType.token, f.targetField.type, 0);
        final local = 'resolved${f.sourceField!.codeName.firstUp}';
        preludes.add(codeGenUtils.constDecl(local, expr));
        preludes.add(codeGenUtils.ifStatement(
          condition: '$local == nil',
          ifBlockStatements: ['$local = default${f.sourceField!.codeName.firstUp}'],
        ));
        return '${f.sourceField!.codeName}: $local,';
      }),
      ...plan.promoted.map((f) => '${f.sourceField!.codeName}: ${_lowerFirst(f.sourceField!.codeName)},'),
      ...plan.inputOnly.map((f) => '${f.codeName}: ${_lowerFirst(f.codeName)},'),
    ];
    final params = [
      '$targetVar $targetType',
      ...plan.nullableListDefaults
          .map((f) => 'default${f.sourceField!.codeName.firstUp} ${serializeType(f.sourceField!.type)}'),
      ...plan.promoted.map((f) => '${_lowerFirst(f.sourceField!.codeName)} ${serializeType(f.sourceField!.type)}'),
      ...plan.inputOnly.map((f) => '${_lowerFirst(f.codeName)} ${serializeType(f.type)}'),
    ];
    return codeGenUtils.createMethod(
      methodName: '${def.codeName}From${targetType.firstUp}',
      arguments: params,
      returnType: def.codeName,
      statements: [...preludes, 'return ${def.codeName}{\n${assignments.join('\n').identGo()}\n}'],
    );
  }

  String _mapToExpr(String expr, GLType sourceType, GLType targetType, int index) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) return expr;
      final variable = 'e$index';
      final inner = _mapToExpr(variable, sourceType.inlineType, targetType.inlineType, index + 1);
      return 'glMapSlice($expr, func($variable ${serializeType(sourceType.inlineType)}) ${serializeType(targetType.inlineType)} { return $inner })';
    }
    final sourceInput = grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      final target = resolveCodeName(targetType.token).firstUp;
      return sourceType.nullable
          ? 'glMapPtr($expr, func(x ${sourceInput!.codeName}) ${serializeType(targetType)} { return x.To$target() })'
          : '$expr.To$target()';
    }
    return expr;
  }

  String _mapFromExpr(String variable, String sourceElemToken, GLType targetType, int index) {
    if (targetType.isList) {
      if (sourceElemToken == targetType.firstType.token) return variable;
      final element = 'e$index';
      final inner = _mapFromExpr(element, sourceElemToken, targetType.inlineType, index + 1);
      final sourceInput = grammar.inputs[sourceElemToken];
      return 'glMapSlice($variable, func($element ${serializeType(targetType.inlineType)}) ${sourceInput?.codeName ?? serializeType(targetType.inlineType)} { return $inner })';
    }
    final sourceInput = grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = resolveCodeName(sourceElemToken);
      final targetCodeName = resolveCodeName(targetType.token);
      final call = '${sourceCodeName}From${targetCodeName.firstUp}';
      if (targetType.nullable) {
        return 'glMapPtr($variable, func(x $targetCodeName) $sourceCodeName { return $call(x) })';
      }
      return '$call($variable)';
    }
    return variable;
  }

  // ── Files & imports ────────────────────────────────────────────────────────

  static const _buildConstraintSuffixes = {
    'aix', 'android', 'darwin', 'dragonfly', 'freebsd', 'hurd', 'illumos', 'ios', 'js', 'linux', 'nacl', 'netbsd',
    'openbsd', 'plan9', 'solaris', 'wasip1', 'windows', 'zos', '386', 'amd64', 'arm', 'arm64', 'loong64', 'mips',
    'mipsle', 'mips64', 'mips64le', 'ppc64', 'ppc64le', 'riscv64', 's390x', 'wasm', 'test',
  };

  String fileStem(String codeName) {
    final stem = codeName.toSnakeCaseWords();
    final last = stem.split('_').last;
    return _buildConstraintSuffixes.contains(last) ? '${stem}_gl' : stem;
  }

  @override
  String getFileNameFor(GLToken token) => '${fileStem(resolveCodeName(token.token))}.go';

  @override
  String serializeImportToken(GLToken token) => '';

  @override
  String serializeImport(String import) => import;

  @override
  String serializeWithImport(GLToken token, String data) => assembleFile(data);

  Set<String> _importsFor(String body) {
    final imports = <String>{};
    for (final match in RegExp(r'(?<![\w.$"])([a-z][a-z0-9]*)\.[A-Za-z]').allMatches(body)) {
      final path = _importBySelector[match.group(1)];
      if (path != null) imports.add(path);
    }
    return imports;
  }

  String assembleFile(String body, {Set<String> extraImports = const {}}) {
    final imports = {..._importsFor(body), ...extraImports}.toList()..sort();
    final importBlock = imports.isEmpty
        ? ''
        : imports.length == 1
            ? 'import "${imports.first}"\n\n'
            : 'import (\n${imports.map((i) => '"$i"').join('\n').identGo()}\n)\n\n';
    return 'package $packageName\n\n$importBlock${body.trim()}\n';
  }

  @override
  String serializeGlClass(GLClassModel theClass, {bool withImports = true}) {
    if (!withImports) return theClass.body.trim();
    final extra = theClass.imports.map(_unquoteImport).where((i) => i.isNotEmpty).toSet();
    return assembleFile(theClass.body, extraImports: extra);
  }

  String _unquoteImport(String line) {
    final match = RegExp(r'"([^"]+)"').firstMatch(line);
    return match?.group(1) ?? '';
  }
}

extension _FirstOrNullGl<T> on Iterable<T> {
  T? get firstOrNullGl => isEmpty ? null : first;
}
