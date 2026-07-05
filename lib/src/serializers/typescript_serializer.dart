import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';
import 'package:graphlink/src/utils.dart';

class TypeScriptSerializer extends GLSerializer {
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
  };

  TypeScriptSerializer(
    super.grammar, {
    this.immutableTypeFields = true,
    this.optionalNullableInputFields = true,
    super.typeMapOverrides = const {},
    required super.importPrefix,
  });

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
      final entries = value.entries.map((e) {
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
      final content = value.startsWith('"') && value.endsWith('"')
          ? value.substring(1, value.length - 1)
          : value;
      return '"$content"';
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
  String serializeType(GLType def, [bool _ = false]) {

    String expr;
    if (def is GLMapType) {
      expr = 'Map<${serializeType(def.keyType, false)}, ${serializeType(def.valueType, false)}>';
    } else if (def is GLListType) {
      final elementTs = serializeType(def.inlineType, false);
      // Wrap element in parens when it already contains `|` (i.e. it is nullable)
      expr = def.inlineType.nullable ? '($elementTs)[]' : '$elementTs[]';
    } else {
      final token = def.token;
      expr = getTypeNameFromGQExternal(token) ?? resolveCodeName(token);
    }

    final wrapper = def.wrapper;
    if (wrapper != null) {
      if (def.wrapperImport != null) {
        grammar.getTokenByKey(def.token)?.addImport(def.wrapperImport!);
      }
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
    final forceNullable = isTypeField && (def.hasInculeOrSkipDiretives);
    final tsType = serializeType(type, forceNullable);

    if (!immutable && (def.type.nullable || forceNullable) && optionalNullableInputFields) {
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
        _generateTypeToJson(def.codeName, fields),
        _generateTypeFromJson(def.codeName, fields),
      ],
    ));
    return buffer.toString();
  }

  // ── Types ──────────────────────────────────────────────────────────────────

  @override
  String doSerializeTypeDefinition(GLTypeDefinition def) {
    if (def is GLInterfaceDefinition && !def.isServerProjection) {
      return _serializeInterfaceAsUnion(def);
    }
    return _serializeType(def);
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
        _serializeUnionToJson(def),
        _serializeUnionFromJson(def),
      ],
    ));
    return buf.toString();
  }

  /// GraphQL `type` → `export interface Foo { readonly field: Type; }`
  String _serializeType(GLTypeDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    final hasRealInterface = def.interfaces.any((i) => !i.isServerProjection);
    final wireTypeName = hasRealInterface ? def.token : null;
    final buf = StringBuffer();
    buf.write(codeGenUtils.createInterface(
      interfaceName: def.codeName,
      fields: [
        if (hasRealInterface) "readonly __typename: '${def.token}';",
        ...fields.map((f) => serializeField(f, true, true)),
      ],
    ));
    buf.writeln();
    buf.write(codeGenUtils.createNamespace(
      namespaceName: def.codeName,
      statements: [
        _generateTypeToJson(def.codeName, fields, wireTypeName: wireTypeName),
        _generateTypeFromJson(def.codeName, fields, wireTypeName: wireTypeName),
      ],
    ));
    return buf.toString();
  }

  /// Overridden to add interface implementations as import deps for union types,
  /// filtering out server projection interfaces (the base always includes them).
  @override
  String serializeImports(GLToken token) {
    if (token is GLInterfaceDefinition && !token.isServerProjection && token.getSerializableImplementations(mode).isNotEmpty) {
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
    return "import '$import';";
  }

  // ── GLClassModel serialization ─────────────────────────────────────────────

  @override
  String serializeGlClass(GLClassModel theClass,
      {bool withImports = true}) {
    if (!withImports || theClass.importDepencies.isEmpty) {
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
    final func = codeGenUtils.createMethod(
      methodName: 'toJson',
      arguments: ['value: ${def.codeName}'],
      returnType: 'string',
      statements: ['return value;'],
    );
    return 'export function $func';
  }

  String _generateEnumFromJson(GLEnumDefinition def) {
    final visibleValues = def.values.where((val) => serialzeEnumValue(val).isNotEmpty).toList();
    final cases = visibleValues.map((val) => TypeScriptCaseStatement(
      caseValue: '"${val.value.token}"',
      statement: 'return ${def.codeName}.${val.codeName};',
    )).toList();
    final switchStmt = codeGenUtils.switchStatement(
      expression: 'value',
      cases: cases,
      defaultStatements: ['throw new Error(`Invalid ${def.codeName}: \${value}`);'],
    );
    final func = codeGenUtils.createMethod(
      methodName: 'fromJson',
      arguments: ['value: string'],
      returnType: def.codeName,
      statements: [switchStmt],
    );
    return 'export function $func';
  }

  String _generateTypeToJson(String typeName, List<GLField> fields, {String? wireTypeName}) {
    final entries = [
      if (wireTypeName != null) '"__typename": "$wireTypeName"',
      ...fields.map(_fieldToJsonExpr),
    ].map((e) => '$e,').toList();
    final func = codeGenUtils.createMethod(
      methodName: 'toJson',
      arguments: ['obj: $typeName'],
      returnType: 'Record<string, unknown>',
      statements: ['return ${codeGenUtils.block(entries)};'],
    );
    return 'export function $func';
  }

  String _generateTypeFromJson(String typeName, List<GLField> fields, {String? wireTypeName}) {
    final entries = [
      if (wireTypeName != null) "__typename: '$wireTypeName'",
      ...fields.map(_fieldFromJsonExpr),
    ].map((e) => '$e,').toList();
    final func = codeGenUtils.createMethod(
      methodName: 'fromJson',
      arguments: ['json: Record<string, unknown>'],
      returnType: typeName,
      statements: ['return ${codeGenUtils.block(entries)};'],
    );
    return 'export function $func';
  }

  String _serializeUnionToJson(GLInterfaceDefinition def) {
    final impls = def.getSerializableImplementations(mode).toList();
    final cases = impls.map((t) => TypeScriptCaseStatement(
      caseValue: '"${t.token}"',
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

  String _serializeUnionFromJson(GLInterfaceDefinition def) {
    final impls = def.getSerializableImplementations(mode).toList();
    final cases = impls.map((t) => TypeScriptCaseStatement(
      caseValue: '"${t.token}"',
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

  String _fieldToJsonExpr(GLField field) {
    final wireKey = field.name.token;
    final expr = _callToJson('obj.${field.codeName}', field.type, 0);
    return '"$wireKey": $expr';
  }

  String _fieldFromJsonExpr(GLField field) {
    final wireKey = field.name.token;
    final jsonExpr = 'json["$wireKey"]';
    final expr = _callFromJson(jsonExpr, field.type, 0);
    return '${field.codeName}: $expr';
  }

  String callToJson(String varName, GLType type) => _callToJson(varName, type, 0);

  String _callToJson(String varName, GLType type, int depth) {
    if (type is GLListType) {
      final varEl = 'e$depth';
      final elementCall = _callToJson(varEl, type.inlineType, depth + 1);
      final mapExpr = '$varName.map(($varEl) => $elementCall)';
      return type.nullable ? '$varName != null ? $mapExpr : null' : mapExpr;
    }
    if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) {
      final call = '${resolveCodeName(type.token)}.toJson($varName)';
      return type.nullable ? '$varName != null ? $call : null' : call;
    }
    return varName;
  }

  String _callFromJson(String jsonExpr, GLType type, int depth) {
    if (type is GLListType) {
      final varEl = 'e$depth';
      final elementCall = _callFromJson(varEl, type.inlineType, depth + 1);
      final mapExpr = '($jsonExpr as unknown[]).map(($varEl) => $elementCall)';
      return type.nullable ? '$jsonExpr != null ? $mapExpr : null' : mapExpr;
    }
    if (grammar.isEnum(type.token)) {
      final call = '${resolveCodeName(type.token)}.fromJson($jsonExpr as string)';
      return type.nullable ? '$jsonExpr != null ? $call : null' : call;
    }
    if (grammar.isProjectableType(type.token)) {
      final call = '${resolveCodeName(type.token)}.fromJson($jsonExpr as Record<string, unknown>)';
      return type.nullable ? '$jsonExpr != null ? $call : null' : call;
    }
    // Scalar — pure type assertion, no runtime cost
    return '$jsonExpr as ${serializeType(type, false)}';
  }
}
