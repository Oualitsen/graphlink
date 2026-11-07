import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/graphql_string_literal.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_defaults_extension.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_rest_discriminator.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/json_expressions.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';
import 'package:graphlink/src/utils.dart';

class TypeScriptSerializer extends GLSerializer with JsonExpressions {
  final codeGenUtils = TypeScriptCodeGenUtils();
  final bool immutableTypeFields;
  final bool optionalNullableInputFields;

  @override
  Map<String, String> get defaultTypeMap => const {
    'ID': 'string',
    'String': 'string',
    'Int': 'number',
    'Float': 'number',
    'Boolean': 'boolean',
    'gqlMapStrObj': 'Record<string, unknown>',
    'dynamicValue': 'unknown',
    'void': 'void',
  };

  TypeScriptSerializer(
    super.grammar, {
    this.immutableTypeFields = true,
    this.optionalNullableInputFields = true,
    super.typeMapOverrides = const {},
    required super.importPrefix,
  });

  @override
  String stringLiteral(String decoded) =>
      '"${escapeStringBody(decoded, quote: '"', control: (unit) => '\\x${unit.toRadixString(16).padLeft(2, '0')}')}"';

  @override
  String serializeDefaultLiteral(GLType type, Object? value, {bool needsConst = false}) {
    if (value == null) return 'null';
    if (value is int) return '$value';
    if (value is double) return '$value';
    if (value is bool) return '$value';
    if (value is List) {
      final innerType = type.inlineType;
      final items = value.map((e) => serializeDefaultLiteral(innerType, e)).join(', ');
      return '[$items]';
    }
    if (value is Map) {
      final inputDef = grammar.inputs[type.token];
      final entries = grammar.completeInputDefault(type.token, value).entries.map((e) {
        final field = inputDef?.fields.firstWhere((f) => f.name.token == e.key);
        final fieldType = field?.type ?? type;
        final key = field?.codeName ?? e.key;
        return '$key: ${serializeDefaultLiteral(fieldType, e.value)}';
      }).join(', ');
      return '{ $entries }';
    }
    if (value is String) {
      if (grammar.enums.containsKey(type.token)) {
        return '${resolveCodeName(type.token)}.${grammar.enumConstantName(type.token, value)}';
      }
      return stringLiteral(decodeGraphqlString(value));
    }
    return '"$value"';
  }

  // ── Enums ──────────────────────────────────────────────────────────────────

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    final entries = <String>[];
    for (final value in def.values) {
      final deprecation = serializeEnumValueDeprecation(value);
      final codeName = serialzeEnumValue(value);
      if (codeName.isEmpty) continue;
      final wireName = value.value.token;
      if (deprecation.isNotEmpty) {
        entries.add('$deprecation\n$codeName = \'$wireName\',');
      } else {
        entries.add('$codeName = \'$wireName\',');
      }
    }
    final unknown = def.unknownValue;
    if (unknown != null) {
      entries.add('${unknown.codeName} = \'${unknown.value.token}\',');
    }
    final buf = StringBuffer();
    buf.write('export enum ${def.codeName} ');
    buf.write(codeGenUtils.block(entries));
    buf.writeln();
    buf.write(codeGenUtils.createNamespace(
      namespaceName: def.codeName,
      statements: [
        _generateEnumToJson(def),
        _generateEnumFromJson(def),
      ],
    ));
    return buf.toString();
  }

  @override
  String doSerializeEnumValue(GLEnumValue value) {
    if (shouldSkipSerialization(directives: value.getDirectives(), mode: mode)) {
      return '';
    }
    return value.codeName;
  }

  @override
  String serializeFieldDeprecation(GLField field) {
    if (!field.isDeprecated) return '';
    final reason = field.deprecationReason ?? 'No longer supported';
    final safeReason = reason.replaceAll('*/', '*\\/').replaceAll(RegExp(r'[\r\n]+'), ' ');
    return "/** @deprecated $safeReason */\n";
  }

  @override
  String serializeEnumValueDeprecation(GLEnumValue value) {
    if (!value.isDeprecated) return '';
    final reason = value.deprecationReason ?? 'No longer supported';
    final safeReason = reason.replaceAll('*/', '*\\/').replaceAll(RegExp(r'[\r\n]+'), ' ');
    return "/** @deprecated $safeReason */";
  }

  // ── Type serialization ─────────────────────────────────────────────────────

  /// Converts a [GLType] to its TypeScript representation.
  ///
  /// Nullability rules:
  ///   `String!`      → `string`
  ///   `String`       → `string | null`
  ///   `[String!]!`   → `string[]`
  ///   `[String!]`    → `string[] | null`
  ///   `[String]!`    → `(string | null)[]`
  ///   `[String]`     → `(string | null)[] | null`
  @override
  String serializeType(GLType def) {

    if (def is GLVoidType) {
      return 'void';
    }
    String expr;
    if (def is GLMapType) {
      expr = 'Map<${serializeType(def.keyType)}, ${serializeType(def.valueType)}>';
    } else if (def is GLListType) {
      final elementTs = serializeType(def.inlineType);
      // Wrap element in parens when it already contains `|` (i.e. it is nullable)
      expr = def.inlineType.nullable ? '($elementTs)[]' : '$elementTs[]';
    } else {
      final token = def.token;
      expr = getTypeNameFromGQExternal(token) ?? resolveCodeName(token);
    }

    final wrapper = def.wrapper;
    if (wrapper != null) {
      expr = '$wrapper<$expr>';
    }

    return def.nullable ? '$expr | null' : expr;
  }

  // ── Fields ─────────────────────────────────────────────────────────────────

  /// Serializes a single field.
  ///
  /// [immutable] == true  → type context:  `readonly name: Type;`
  /// [immutable] == false → input context: `name?: Type | null;` (when nullable
  ///                        and [optionalNullableInputFields] is true)
  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField,
      {bool isOverride = false}) {
    final type = def.type;
    final name = def.codeName;
    final tsType = serializeType(type);

    if (!immutable && (def.type.nullable) && optionalNullableInputFields) {
      return '$name?: $tsType;';
    }

    final prefix = (immutable && immutableTypeFields) ? 'readonly ' : '';
    return '$prefix$name: $tsType;';
  }

  // ── Inputs ─────────────────────────────────────────────────────────────────

  @override
  String doSerializeInputDefinition(GLInputDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    final buffer = StringBuffer();
    buffer.write(codeGenUtils.createInterface(
      interfaceName: def.codeName,
      fields: fields.map((f) => serializeField(f, false, false)).toList(),
    ));
    final defaultFields = fields.where((f) => f.initialValue != null).toList();
    if (defaultFields.isNotEmpty) {
      final entries = defaultFields
          .map((f) => '  ${f.codeName}: ${serializeDefaultLiteral(f.type, f.initialValue)}')
          .join(',\n');
      buffer.writeln('\nexport const default${def.codeName}: Partial<${def.codeName}> = {\n$entries,\n};');
    }
    buffer.writeln();
    buffer.write(codeGenUtils.createNamespace(
      namespaceName: def.codeName,
      statements: [
        _generateTypeToJson(def.codeName, fields, omitNulls: def.isOneOf),
        _generateTypeFromJson(def.codeName, fields),
      ],
    ));
    return buffer.toString();
  }

  // ── Types ──────────────────────────────────────────────────────────────────

  @override
  String doSerializeTypeDefinition(GLTypeDefinition def) {
    if (def is GLInterfaceDefinition) {
      if (def.fieldAsMethods) {
        return _serializeInterfaceWithMethods(def);
      }
      return _serializeInterfaceAsUnion(def);
    }
    return _serializeType(def);
  }

  /// A developer-implemented interface (e.g. `GraphLinkInterceptor`) whose fields are
  /// method contracts, not data properties — `export interface Foo { bar(x: T): R; }`.
  String _serializeInterfaceWithMethods(GLInterfaceDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    final interfaceNames = def.interfaceNames.map((e) => resolveCodeName(e.token)).toList();
    return codeGenUtils.createInterface(
      interfaceName: def.codeName,
      extendsNames: interfaceNames.isEmpty ? null : interfaceNames,
      fields: fields.map((f) => "${_serializeMethodSignature(f)};").toList(),
    );
  }

  String _serializeMethodSignature(GLField field) {
    final args = field.arguments.map((a) => "${a.codeName}: ${serializeType(a.type)}").join(', ');
    return "${field.codeName}($args): ${serializeType(field.type)}";
  }

  /// GraphQL `interface` / `union` → `export type Animal = Dog | Cat;`
  String _serializeInterfaceAsUnion(GLInterfaceDefinition def) {
    if (def.getSerializableImplementations(mode).isEmpty) return '';
    final members = def.getSerializableImplementations(mode).map((t) => t.codeName).join(' | ');
    final buf = StringBuffer();
    buf.write(codeGenUtils.createTypeAlias(name: def.codeName, value: members));
    buf.writeln();
    buf.write(codeGenUtils.createNamespace(
      namespaceName: def.codeName,
      statements: [
        if (!shouldSkipJsonMethods(def))
          def.syntheticImplementation != null ? _serializeSyntheticUnionToJson(def) : _serializeUnionToJson(def),
        if (!shouldSkipJsonMethods(def))
          def.syntheticImplementation != null ? serializeSyntheticInterfaceFromJson(def) : _serializeUnionFromJson(def),
      ],
    ));
    return buf.toString();
  }

  /// GraphQL `type` → `export interface Foo { readonly field: Type; }`
  String _serializeType(GLTypeDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    final hasRealInterface = def.interfaces.isNotEmpty;
    final wireTypeName = hasRealInterface && !def.isSyntheticImplementation ? (def.jsonTypeName ?? def.token) : null;
    final buf = StringBuffer();
    buf.write(codeGenUtils.createInterface(
      interfaceName: def.codeName,
      fields: [
        if (wireTypeName != null) "readonly __typename: '$wireTypeName';",
        ...fields.map((f) => serializeField(f, true, true)),
      ],
    ));
    buf.writeln();
    if (!shouldSkipJsonMethods(def)) {
      buf.write(codeGenUtils.createNamespace(
        namespaceName: def.codeName,
        statements: [
          _generateTypeToJson(def.codeName, fields, wireTypeName: wireTypeName),
          _generateTypeFromJson(def.codeName, fields,
              wireTypeName: wireTypeName, requiredChecksFor: def.token),
        ],
      ));
    }
    return buf.toString();
  }

  /// Overridden to add interface implementations as import deps for union types,
  /// filtering out server projection interfaces (the base always includes them).
  @override
  String serializeImports(GLToken token) {
    if (token is GLInterfaceDefinition && token.getSerializableImplementations(mode).isNotEmpty) {
      var deps = {...token.getImportDependecies(grammar).where((d) => d != token), ...token.getSerializableImplementations(mode)};
      final buffer = StringBuffer();
      for (final dep in deps) {
        final import = serializeImportToken(dep);
        if (import.isNotEmpty) buffer.writeln(import);
      }
      for (final i in token.getImports(grammar)) {
        final import = serializeImport(i);
        if (import.isNotEmpty) buffer.writeln(import);
      }
      return buffer.toString();
    }
    return super.serializeImports(token);
  }

  // ── File naming & imports ──────────────────────────────────────────────────

  @override
  String getFileNameFor(GLToken token) =>
      "${resolveCodeName(token.token).toKebabCase()}.ts";

  @override
  String serializeImportToken(GLToken token) {
    String? subDir;
    if (token is GLEnumDefinition) {
      subDir = "enums";
    } else if (token is GLInterfaceDefinition) {
      subDir = "interfaces";
    } else if (token is GLTypeDefinition) {
      subDir = "types";
    } else if (token is GLInputDefinition) {
      subDir = "inputs";
    }
    if (subDir == null) return "";
    final file = getFileNameFor(token).replaceAll('.ts', '.js');
    return "import { ${resolveCodeName(token.token)} } from '../$subDir/$file';";
  }

  @override
  String serializeImport(String import) {
    return import.startsWith('import ') ? import : "import '$import';";
  }

  // ── GLClassModel serialization ─────────────────────────────────────────────

  @override
  String serializeGlClass(GLClassModel theClass,
      {bool withImports = true}) {
    if (!withImports || theClass.importDepencies.isEmpty && theClass.imports.isEmpty) {
      return super.serializeGlClass(theClass,
          withImports: withImports);
    }
    final tokenImports = theClass.importDepencies
        .map((dep) => serializeImportToken(dep))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final simpleImports =
        theClass.imports.map((imp) => serializeImport(imp)).toList();
    final merged = GLClassModel(
      imports: {...tokenImports, ...simpleImports}.toList(),
      body: theClass.body,
    );
    return super.serializeGlClass(merged,
        withImports: withImports);
  }

  // ── JSON serialization helpers ─────────────────────────────────────────────

  String _generateEnumToJson(GLEnumDefinition def) {
    final unknown = def.unknownValue;
    final func = codeGenUtils.createMethod(
      methodName: 'toJson',
      arguments: ['value: ${def.codeName}'],
      returnType: 'string',
      statements: [
        if (unknown != null)
          codeGenUtils.ifStatement(
            condition: 'value === ${def.codeName}.${unknown.codeName}',
            ifBlockStatements: ['throw new Error(`${def.codeName}.${unknown.codeName} cannot be serialized`);'],
          ),
        'return value;',
      ],
    );
    return 'export function $func';
  }

  String _generateEnumFromJson(GLEnumDefinition def) {
    final unknown = def.unknownValue;
    final visibleValues = def.values.where((val) => serialzeEnumValue(val).isNotEmpty).toList();
    final cases = visibleValues.map((val) => TypeScriptCaseStatement(
      caseValue: '"${val.value.token}"',
      statement: 'return ${def.codeName}.${val.codeName};',
    )).toList();
    final switchStmt = codeGenUtils.switchStatement(
      expression: 'value',
      cases: cases,
      defaultStatements: [
        unknown != null
            ? 'return ${def.codeName}.${unknown.codeName};'
            : 'throw new Error(`Invalid ${def.codeName}: \${value}`);',
      ],
    );
    final func = codeGenUtils.createMethod(
      methodName: 'fromJson',
      arguments: ['value: string'],
      returnType: def.codeName,
      statements: [switchStmt],
    );
    return 'export function $func';
  }

  String _generateTypeToJson(String typeName, List<GLField> fields, {String? wireTypeName, bool omitNulls = false}) {
    final entries = [
      if (wireTypeName != null) '"__typename": "$wireTypeName"',
      ...fields.map(_fieldToJsonExpr),
    ].map((e) => '$e,').toList();
    final func = codeGenUtils.createMethod(
      methodName: 'toJson',
      arguments: ['obj: $typeName'],
      returnType: 'Record<string, unknown>',
      statements: [
        omitNulls
            ? 'return Object.fromEntries(Object.entries(${codeGenUtils.block(entries)}).filter(([, v]) => v != null));'
            : 'return ${codeGenUtils.block(entries)};'
      ],
    );
    return 'export function $func';
  }

  List<String> _requiredFieldChecks(List<GLField> fields, String? token) {
    if (token == null || !grammar.restReachableTypeNames.contains(token)) return const [];
    return [
      for (final field in fields)
        if (!field.type.nullable && field.initialValue == null)
          codeGenUtils.ifStatement(
            condition: 'json["${field.name.token}"] == null',
            ifBlockStatements: ["throw new Error('$token.${field.name.token} is missing or null in the response');"],
          ),
    ];
  }

  String _generateTypeFromJson(String typeName, List<GLField> fields, {String? wireTypeName, String? requiredChecksFor}) {
    final entries = [
      if (wireTypeName != null) "__typename: '$wireTypeName'",
      ...fields.map(_fieldFromJsonExpr),
    ].map((e) => '$e,').toList();
    final func = codeGenUtils.createMethod(
      methodName: 'fromJson',
      arguments: ['json: Record<string, unknown>'],
      returnType: typeName,
      statements: [
        ..._requiredFieldChecks(fields, requiredChecksFor),
        'return ${codeGenUtils.block(entries)};',
      ],
    );
    return 'export function $func';
  }

  String _serializeSyntheticUnionToJson(GLInterfaceDefinition def) {
    final func = codeGenUtils.createMethod(
      methodName: 'toJson',
      arguments: ['obj: ${def.codeName}'],
      returnType: 'Record<string, unknown>',
      statements: ['return ${def.syntheticImplementation!.codeName}.toJson(obj);'],
    );
    return 'export function $func';
  }

  @override
  String serializeSyntheticInterfaceFromJson(GLInterfaceDefinition interface) {
    final func = codeGenUtils.createMethod(
      methodName: 'fromJson',
      arguments: ['json: Record<string, unknown>'],
      returnType: interface.codeName,
      statements: ['return ${interface.syntheticImplementation!.codeName}.fromJson(json);'],
    );
    return 'export function $func';
  }

  String _serializeUnionToJson(GLInterfaceDefinition def) {
    final impls = def.getSerializableImplementations(mode).toList();
    final cases = impls.map((t) => TypeScriptCaseStatement(
      caseValue: '"${t.jsonTypeName ?? t.token}"',
      statement: 'return ${t.codeName}.toJson(obj as ${t.codeName});',
    )).toList();
    final switchStmt = codeGenUtils.switchStatement(
      expression: 'obj.__typename',
      cases: cases,
      defaultStatements: ['throw new Error(`Unknown ${def.codeName}: \${(obj as any).__typename}`);'],
    );
    final func = codeGenUtils.createMethod(
      methodName: 'toJson',
      arguments: ['obj: ${def.codeName}'],
      returnType: 'Record<string, unknown>',
      statements: [switchStmt],
    );
    return 'export function $func';
  }

  List<String> _discriminatedFromJsonBody(
    GLInterfaceDefinition def,
    List<GLTypeDefinition> impls,
    GLRestDiscriminator discriminator,
  ) {
    String typeName(GLTypeDefinition t) => t.derivedFromType?.tokenInfo.token ?? t.token;
    final byTypename = codeGenUtils.switchStatement(
      expression: 'typename',
      cases: [
        for (final t in impls)
          TypeScriptCaseStatement(caseValue: '"${typeName(t)}"', statement: 'return ${t.codeName}.fromJson(json);'),
      ],
    );
    final byValue = codeGenUtils.switchStatement(
      expression: 'discriminator',
      cases: [
        for (final t in impls)
          TypeScriptCaseStatement(
              caseValue: '"${discriminator.valueByType[typeName(t)] ?? typeName(t)}"',
              statement: 'return ${t.codeName}.fromJson(json);'),
      ],
      defaultStatements: [
        'throw new Error(`Cannot decode ${def.token}: unknown or missing "${discriminator.field}" value (\${discriminator})`);',
      ],
    );
    return [
      'const typename = json["__typename"];',
      byTypename,
      'const discriminator = json["${discriminator.field}"];',
      byValue,
    ];
  }

  String _serializeUnionFromJson(GLInterfaceDefinition def) {
    final impls = def.getSerializableImplementations(mode).toList();
    final discriminator = grammar.restDiscriminators[def.token];
    if (discriminator != null) {
      return 'export function ${codeGenUtils.createMethod(
        methodName: 'fromJson',
        arguments: ['json: Record<string, unknown>'],
        returnType: def.codeName,
        statements: _discriminatedFromJsonBody(def, impls, discriminator),
      )}';
    }
    final cases = impls.map((t) => TypeScriptCaseStatement(
      caseValue: '"${t.jsonTypeName ?? t.token}"',
      statement: 'return ${t.codeName}.fromJson(json);',
    )).toList();
    final switchStmt = codeGenUtils.switchStatement(
      expression: 'json["__typename"] as string',
      cases: cases,
      defaultStatements: ['throw new Error(`Unknown ${def.codeName}: \${json["__typename"]}`);'],
    );
    final func = codeGenUtils.createMethod(
      methodName: 'fromJson',
      arguments: ['json: Record<string, unknown>'],
      returnType: def.codeName,
      statements: [switchStmt],
    );
    return 'export function $func';
  }

  String _fieldToJsonExpr(GLField field) => '"${field.name.token}": ${toJsonExpr(field.type, 'obj.${field.codeName}')}';

  String _fieldFromJsonExpr(GLField field) =>
      '${field.codeName}: ${fromJsonExpr(field.type, 'json["${field.name.token}"]')}';

  // A nullable list falls back to `value` itself (not a hardcoded `null`) so an omitted
  // (undefined) field stays omitted, triggering the server-side default, while an explicit
  // null is preserved and overrides it.
  @override
  String listToJson(GLType list, String value, String element, String body, GLImportSink? context) {
    final mapped = '$value.map(($element) => $body)';
    return list.nullable ? '$value != null ? $mapped : $value' : mapped;
  }

  @override
  String listFromJson(GLType list, String json, String element, String body, GLImportSink? context) {
    final mapped = '($json as unknown[]).map(($element) => $body)';
    return list.nullable ? '$json != null ? $mapped : null' : mapped;
  }

  @override
  String modelToJson(GLType type, String value) {
    final call = '${resolveCodeName(type.token)}.toJson($value)';
    return type.nullable ? '$value != null ? $call : $value' : call;
  }

  @override
  String enumFromJson(GLType type, String json) {
    final call = '${resolveCodeName(type.token)}.fromJson($json as string)';
    return type.nullable ? '$json != null ? $call : null' : call;
  }

  @override
  String modelFromJson(GLType type, String json) {
    final call = '${resolveCodeName(type.token)}.fromJson($json as Record<string, unknown>)';
    return type.nullable ? '$json != null ? $call : null' : call;
  }

  @override
  String plainFromJson(GLType type, String json) => '$json as ${serializeType(type)}';

  @override
  String scalarFromJson(GLScalarCodec codec, String json, {required bool nullable}) =>
      nullable ? '$json != null ? ${codec.decode(json)} : null' : codec.decode(json);

  @override
  String scalarToJson(GLScalarCodec codec, String value, {required bool nullable}) =>
      nullable ? '$value != null ? ${codec.encode(value)} : $value' : codec.encode(value);
}
