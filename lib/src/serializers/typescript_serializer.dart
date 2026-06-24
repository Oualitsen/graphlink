import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
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
  bool get generateJsonMethods => false;

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
        final fieldType = inputDef?.fields.firstWhere((f) => f.name.token == e.key).type ?? type;
        return '${e.key}: ${serializeDefaultLiteral(fieldType, e.value)}';
      }).join(', ');
      return '{ $entries }';
    }
    if (value is String) {
      if (grammar.enums.containsKey(type.token)) {
        return '${type.token}.$value';
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
    final values = def.values
        .map((e) => doSerializeEnumValue(e))
        .where((e) => e.isNotEmpty)
        .toList();
    return codeGenUtils.createEnum(
      enumName: def.token,
      enumValues: values,
    );
  }

  @override
  String doSerializeEnumValue(GLEnumValue value) {
    if (shouldSkipSerialization(directives: value.getDirectives(), mode: mode)) {
      return '';
    }
    final deprecation = serializeEnumValueDeprecation(value);
    if (deprecation.isEmpty) return value.value.token;
    return '$deprecation\n  ${value.value.token}';
  }

  @override
  String serializeFieldDeprecation(GLField field) {
    if (!field.isDeprecated) return '';
    final reason = field.deprecationReason ?? 'No longer supported';
    final safeReason = reason.replaceAll('*/', '*\\/');
    return "/** @deprecated $safeReason */\n";
  }

  @override
  String serializeEnumValueDeprecation(GLEnumValue value) {
    if (!value.isDeprecated) return '';
    final reason = value.deprecationReason ?? 'No longer supported';
    final safeReason = reason.replaceAll('*/', '*\\/');
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
  String serializeType(GLType def, bool forceNullable, [bool _ = false]) {
    final nullable = forceNullable || def.nullable;

    if (def is GLListType) {
      final elementTs = serializeType(def.inlineType, false);
      // Wrap element in parens when it already contains `|` (i.e. it is nullable)
      final listExpr =
          def.inlineType.nullable ? '($elementTs)[]' : '$elementTs[]';
      return nullable ? '$listExpr | null' : listExpr;
    }

    final token = def.token;
    final tsType = getTypeNameFromGQExternal(token) ?? token;
    return nullable ? '$tsType | null' : tsType;
  }

  // ── Fields ─────────────────────────────────────────────────────────────────

  /// Serializes a single field.
  ///
  /// [immutable] == true  → type context:  `readonly name: Type;`
  /// [immutable] == false → input context: `name?: Type | null;` (when nullable
  ///                        and [optionalNullableInputFields] is true)
  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField) {
    final type = def.type;
    final name = def.name;
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
      interfaceName: def.token,
      fields: fields.map((f) => serializeField(f, false, false)).toList(),
    ));
    final defaultFields = fields.where((f) => f.initialValue != null).toList();
    if (defaultFields.isNotEmpty) {
      final entries = defaultFields
          .map((f) => '  ${f.name.token}: ${serializeDefaultLiteral(f.type, f.initialValue)}')
          .join(',\n');
      buffer.writeln('\nexport const default${def.token}: Partial<${def.token}> = {\n$entries,\n};');
    }
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
    final members = def.getSerializableImplementations(mode).map((t) => t.token).join(' | ');
    return codeGenUtils.createTypeAlias(name: def.token, value: members);
  }

  /// GraphQL `type` → `export interface Foo { readonly field: Type; }`
  String _serializeType(GLTypeDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    return codeGenUtils.createInterface(
      interfaceName: def.token,
      fields: fields.map((f) => serializeField(f, true, true)).toList(),
    );
  }

  /// Overridden to add interface implementations as import deps for union types,
  /// since the base only does this when generateJsonMethods is true.
  @override
  String serializeImports(GLToken token) {
    if (token is GLInterfaceDefinition && !token.isServerProjection && token.getSerializableImplementations(mode).isNotEmpty) {
      var deps = {...token.getImportDependecies(grammar), ...token.getSerializableImplementations(mode)};
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
      "${token.token.toKebabCase()}.ts";

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
    return "import { ${token.token} } from '../$subDir/$file';";
  }

  @override
  String serializeImport(String import) {
    // _list is a Dart/Java sentinel for list imports — arrays are built-in in TS
    if (import == importList) return '';
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
}
