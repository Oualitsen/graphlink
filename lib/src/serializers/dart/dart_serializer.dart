import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';
import 'package:graphlink/src/graphql_string_literal.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_rest_discriminator.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/json_expressions.dart';
import 'package:graphlink/src/serializers/dart/dart_mapping_serializer.dart';

class DartSerializer extends GLSerializer with JsonExpressions {
  @override
  late final GLMappingSerializer mapping = DartMappingSerializer(this);

  final codeGenUtils = DartCodeGenUtils();

  @override
  Map<String, String> get defaultTypeMap => const {
    "ID": "String",
    "String": "String",
    "Float": "double",
    "Int": "int",
    "Boolean": "bool",
    "Null": "null",
    "Long": "int",
    "gqlMapStrObj": "Map<String, dynamic>",
    "dynamicValue": "dynamic",
    "void": "void",
  };

  DartSerializer(super.grammar,
      {super.typeMapOverrides = const {}, required super.importPrefix}) {
    _initAnnotations();
  }

  void _initAnnotations() {
    grammar.handleAnnotations(AnnotationSerializer.serializeAnnotation);
  }

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    final decorators = serializeDecorators(def.getDirectives());
    final unknown = def.unknownValue;
    final source = codeGenUtils.createEnum(
      enumName: def.codeName,
      enumValues: def.allValues.map(doSerializeEnumValue).toList(),
      methods: [
        codeGenUtils.createMethod(
          methodName: "toJson",
          returnType: "String",
          arguments: [],
          namedArguments: false,
          statements: [
            codeGenUtils.switchStatement(
              expression: "this",
              cases: [
                ...def.values.map((val) => DartCaseStatement(caseValue: val.codeName, statement: 'return "${val.token}";')),
                if (unknown != null)
                  DartCaseStatement(
                      caseValue: unknown.codeName,
                      statement: 'throw StateError("${def.codeName}.${unknown.codeName} cannot be serialized");'),
              ],
            ),
          ],
        ),
        codeGenUtils.createMethod(
          methodName: "fromJson",
          arguments: ['String value'],
          namedArguments: false,
          returnType: 'static ${def.codeName}',
          statements: [
            codeGenUtils.switchStatement(
              expression: 'value',
              cases: [
                ...def.values.map((val) => DartCaseStatement(
                    caseValue: '"${val.token}"', statement: 'return ${def.codeName}.${val.codeName};')),
              ],
              defaultStatements: [
                unknown != null
                    ? 'return ${def.codeName}.${unknown.codeName};'
                    : 'throw ArgumentError("Invalid ${def.codeName}: \$value");',
              ],
            ),
          ],
        ),
      ],
    );
    return decorators.isEmpty ? "$source\n" : "$decorators\n$source\n";
  }

  @override
  String doSerializeEnumValue(GLEnumValue value) {
    var deprecation = serializeEnumValueDeprecation(value);
    var decorators = serializeDecorators(value.getDirectives(), joiner: " ");
    var parts = [deprecation, decorators, value.codeName].where((s) => s.isNotEmpty).join(" ");
    // Clean up double spaces from empty deprecation or decorators.
    return parts.replaceAll(RegExp(r'  +'), ' ').trim();
  }

  @override
  String serializeFieldDeprecation(GLField field) {
    if (!field.isDeprecated) return '';
    final reason = field.deprecationReason ?? 'No longer supported';
    final escaped = reason.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\r', '').replaceAll('\n', r'\n');
    return "@Deprecated('$escaped')\n";
  }

  @override
  String serializeEnumValueDeprecation(GLEnumValue value) {
    if (!value.isDeprecated) return '';
    final reason = value.deprecationReason ?? 'No longer supported';
    final escaped = reason.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\r', '').replaceAll('\n', r'\n');
    return "@Deprecated('$escaped')";
  }

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField,
      {bool isOverride = false}) {
    final type = def.type;
    final name = def.codeName;
    final builder = StringBuffer(serializeDecorators(def.getDirectives()));
    if (isOverride) {
      builder.writeln("@override");
    }
    if (immutable) {
      builder.write("final ");
    } else {
      builder.write(" ");
    }
    builder.write("${serializeType(type)} $name;");
    return builder.toString();
  }

  @override
  String serializeType(GLType def) {
    if (def is GLVoidType) {
      return 'void';
    }
    String postfix = "";
    if (def.nullable) {
      postfix = "?";
    }
    String dartTpe;
    if (def is GLMapType) {
      dartTpe = "Map<${serializeType(def.keyType)}, ${serializeType(def.valueType)}>";
    } else if (def is GLListType) {
      dartTpe = "List<${serializeType(def.inlineType)}>";
    } else {
      final token = def.token;
      dartTpe = getTypeNameFromGQExternal(token) ?? resolveCodeName(token);
    }
    final wrapper = def.wrapper;
    if (wrapper != null) {
      dartTpe = "$wrapper<$dartTpe>";
    }
    return "$dartTpe$postfix";
  }

  @override
  String doSerializeInputDefinition(GLInputDefinition def) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    final fields = def.getSerializableFields(grammar.mode);
    final mappingMethods = generateMappingMethods(def);
    var inputClass =
        codeGenUtils.createClass(className: def.codeName, statements: [
      ...fields.map((e) => serializeField(e, true, false)),
      codeGenUtils.createMethod(
          methodName: def.codeName,
          namedArguments: true,
          isConst: true,
          arguments: fields.map((e) => toConstructorDeclaration(e)).toList()),
      generateToJson(fields, omitNulls: def.isOneOf),
      generateFromJson(fields, def.codeName),
      ...mappingMethods,
    ]);

    buffer.writeln(inputClass);
    return buffer.toString();
  }

  @override
  String serializeDefaultLiteral(GLType type, Object? value, {bool needsConst = false}) {
    if (value == null) return 'null';
    if (value is int) return '$value';
    if (value is double) return '$value';
    if (value is bool) return '$value';
    if (value is List) {
      final innerType = type.inlineType;
      final items = value.map((e) => serializeDefaultLiteral(innerType, e, needsConst: false)).join(', ');
      return needsConst ? 'const [$items]' : '[$items]';
    }
    if (value is Map) {
      final inputDef = grammar.inputs[type.token];
      final args = value.entries.map((e) {
        final field = inputDef?.fields.firstWhere((f) => f.name.token == e.key);
        final fieldType = field?.type ?? type;
        final key = field?.codeName ?? e.key;
        return '$key: ${serializeDefaultLiteral(fieldType, e.value, needsConst: false)}';
      }).join(', ');
      return needsConst ? 'const ${resolveCodeName(type.token)}($args)' : '${resolveCodeName(type.token)}($args)';
    }
    if (value is String) {
      if (grammar.enums.containsKey(type.token)) {
        return '${resolveCodeName(type.token)}.${grammar.enumConstantName(type.token, value)}';
      }
      return stringLiteral(decodeGraphqlString(value));
    }
    return "'$value'";
  }

  @override
  String stringLiteral(String decoded) =>
      "'${escapeStringBody(decoded, quote: "'", dollar: true, control: (unit) => '\\x${unit.toRadixString(16).padLeft(2, '0')}')}'";

  String toConstructorDeclaration(GLField field) {
    if (grammar.nullableFieldsRequired || (!field.type.nullable && field.initialValue == null)) {
      return "required this.${field.codeName}";
    } else if (field.initialValue != null) {
      final lit = serializeDefaultLiteral(field.type, field.initialValue, needsConst: true);
      return "this.${field.codeName} = $lit";
    } else {
      return "this.${field.codeName}";
    }
  }

  String generateFromJson(List<GLField> fields, String token) {
    var buffer = StringBuffer();

    buffer.writeln(
      codeGenUtils.createMethod(
          methodName: "fromJson",
          returnType: 'static ${token}',
          namedArguments: false,
          arguments: [
            'Map<String, dynamic> json'
          ],
          statements: [
            ..._requiredFieldChecks(fields, token),
            'return ${token}(',
            ...fields.map((e) => fieldFromJson(e)).map((e) => "${e},".ident()),
            ');'
          ]),
    );
    return buffer.toString();
  }

  List<String> _requiredFieldChecks(List<GLField> fields, String token) {
    if (!grammar.restReachableTypeNames.contains(token)) return const [];
    return [
      for (final field in fields)
        if (!field.type.nullable && field.initialValue == null)
          codeGenUtils.inlineIfStatement(
            condition: "json['${field.name}'] == null",
            statement: "throw FormatException('$token.${field.name} is missing or null in the response');",
          ),
    ];
  }

  String generateToJson(List<GLField> fields, {String? typeName, bool omitNulls = false}) {
    var buffer = StringBuffer();

    buffer.writeln(codeGenUtils.method(
        returnType: 'Map<String, dynamic>',
        methodName: 'toJson',
        statements: [
          "return {",
          if (typeName != null) "'__typename': '$typeName',".ident(),
          ...fields
              .map((field) => (omitNulls ? 'if (${field.codeName} != null) ' : '') + fieldToJson(field))
              .map((e) => "${e},".ident()),
          '};'
        ]));
    return buffer.toString();
  }

  String fieldToJson(GLField field) => "'${field.name}': ${toJsonExpr(field.type, field.codeName)}";

  String fieldFromJson(GLField field) => "${field.codeName}: ${fromJsonExpr(field.type, "json['${field.name}']")}";

  @override
  String listToJson(GLType list, String value, String element, String body, GLImportSink? context) =>
      element == body ? value : DartCodeGenUtils.mapToList(receiver: value, param: element, body: body, nullable: list.nullable);

  @override
  String listFromJson(GLType list, String json, String element, String body, GLImportSink? context) =>
      DartCodeGenUtils.mapToList(
          receiver: '($json as List<dynamic>${list.nullable ? '?' : ''})', param: element, body: body, nullable: list.nullable);

  @override
  String modelToJson(GLType type, String value) => '$value${type.nullable ? "?." : "."}toJson()';

  @override
  String enumFromJson(GLType type, String json) => DartCodeGenUtils.nullSafeExpr(
      json, '${resolveCodeName(type.token)}.fromJson($json as String)', type.nullable);

  @override
  String modelFromJson(GLType type, String json) => DartCodeGenUtils.nullSafeExpr(
      json, '${resolveCodeName(type.token)}.fromJson($json as Map<String, dynamic>)', type.nullable);

  @override
  String plainFromJson(GLType type, String json) {
    final serialized = serializeType(type);
    if (serialized == 'double' || serialized == 'double?') {
      return '($json as num${type.nullable ? '?' : ''})${type.nullable ? '?.' : '.'}toDouble()';
    }
    return '$json as $serialized';
  }

  @override
  String scalarFromJson(GLScalarCodec codec, String json, {required bool nullable}) =>
      DartCodeGenUtils.nullSafeExpr(json, codec.decode(json), nullable);

  @override
  String scalarToJson(GLScalarCodec codec, String value, {required bool nullable}) =>
      DartCodeGenUtils.nullSafeExpr(value, codec.encode(nullable ? '$value!' : value), nullable);

  @override
  String doSerializeTypeDefinition(GLTypeDefinition def) {
    if (def is GLInterfaceDefinition) {
      return serializeInterface(def);
    } else {
      return _doSerializeTypeDefinition(def);
    }
  }

  String _doSerializeTypeDefinition(GLTypeDefinition def) {
    final codeName = def.codeName;
    final implementations = def is GLInterfaceDefinition
        ? def.getSerializableImplementations(mode)
        : <GLTypeDefinition>{};

    final interfaceNames = def.interfaceNames.map((e) => resolveCodeName(e.token)).toSet();
    interfaceNames.addAll(implementations.map((e) => e.codeName));
    var decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    final fields = def.getSerializableFields(grammar.mode);
    var equalsHascodeCode = generateEqualsAndHashCode(def);
    buffer.writeln(codeGenUtils.createClass(
      className: codeName,
      baseClassNames: interfaceNames.toList(),
      statements: [
        ...fields.map((e) =>
            serializeField(e, true, true, isOverride: def.isOverride(e))),
        codeGenUtils.createMethod(
            methodName: codeName,
            namedArguments: false,
            isConst: true,
            arguments: [serializeContructorArgs(fields)]),
        if (equalsHascodeCode.isNotEmpty) equalsHascodeCode,
        if (!shouldSkipJsonMethods(def)) ...[
          generateToJson(fields, typeName: def.jsonTypeName),
          generateFromJson(fields, codeName),
        ],
      ],
    ));
    return buffer.toString();
  }

  String generateEqualsAndHashCode(GLTypeDefinition def) {
    var fieldsToInclude = def.getIdentityFields(grammar);
    if (fieldsToInclude.isNotEmpty) {
      return equalsHascodeCode(def, fieldsToInclude);
    }
    return "";
  }

  String equalsHascodeCode(GLTypeDefinition def, Set<String> fields) {
    final token = def.codeName;
    var buffer = StringBuffer();
    buffer.writeln('@override');
    buffer.writeln(codeGenUtils.createMethod(
        returnType: 'bool operator',
        methodName: "==",
        namedArguments: false,
        arguments: [
          'Object other'
        ],
        statements: [
          codeGenUtils.ifStatement(
              condition: 'identical(this, other)',
              ifBlockStatements: ['return true;']),
          'return other is $token &&',
          "${fields.map((e) => "$e == other.$e").join(" && ")};"
        ]));

    buffer.writeln();
    buffer.writeln('@override');
    buffer.writeln(codeGenUtils.createMethod(
        returnType: "int get",
        methodName: "hashCode => Object.hashAll([${fields.join(", ")}])"));

    return buffer.toString();
  }

  String serializeContructorArgs(List<GLField> fields) {
    if (fields.isEmpty) {
      return "";
    }
    String nonCommonFields;
    if (fields.isEmpty) {
      nonCommonFields = "";
    } else {
      nonCommonFields =
          fields.map((e) => toConstructorDeclaration(e)).join(", ");
    }

    var combined =
        [nonCommonFields].where((element) => element.isNotEmpty).toSet();
    if (combined.isEmpty) {
      return "";
    } else if (combined.length == 1) {
      return "{${combined.first}}";
    }
    return "{${[nonCommonFields].join(", ")}}";
  }

  static String _serializeToJsonForInterface(String token) {
    return "Map<String, dynamic> toJson();";
  }

  @override
  String serializeSyntheticInterfaceFromJson(GLInterfaceDefinition interface) {
    return codeGenUtils.createMethod(
        returnType: 'static ${interface.codeName}',
        methodName: 'fromJson',
        namedArguments: false,
        arguments: ['Map<String, dynamic> json'],
        statements: ['return ${interface.syntheticImplementation!.codeName}.fromJson(json);']);
  }

  String _serializeFromJsonForInterface(
    String token,
    Set<GLTypeDefinition> implementations,
  ) {
    return codeGenUtils.createMethod(
        returnType: 'static ${token}',
        methodName: 'fromJson',
        namedArguments: false,
        arguments: [
          'Map<String, dynamic> json'
        ],
        statements: grammar.restDiscriminators.containsKey(token)
            ? _discriminatedFromJsonBody(token, implementations, grammar.restDiscriminators[token]!)
            : [
          "var typename = json['__typename'] as String;",
          codeGenUtils.switchStatement(
            expression: 'typename',
            cases: [
              ...implementations.map((st) => DartCaseStatement(
                  caseValue:
                      "'${st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token}'",
                  statement: 'return ${st.codeName}.fromJson(json);'))
            ],
            defaultStatements:
                ['throw ArgumentError("Invalid type \$typename. \$typename does not implement $token or not defined");'],
          ),
        ]);
  }

  List<String> _discriminatedFromJsonBody(
    String token,
    Set<GLTypeDefinition> implementations,
    GLRestDiscriminator discriminator,
  ) {
    String typeName(GLTypeDefinition t) => t.derivedFromType?.tokenInfo.token ?? t.tokenInfo.token;
    final byTypename = codeGenUtils.switchStatement(
      expression: 'typename',
      cases: [
        for (final t in implementations)
          DartCaseStatement(caseValue: "'${typeName(t)}'", statement: 'return ${t.codeName}.fromJson(json);'),
      ],
    );
    final byValue = codeGenUtils.switchStatement(
      expression: 'discriminator',
      cases: [
        for (final t in implementations)
          DartCaseStatement(
              caseValue: "'${discriminator.valueByType[typeName(t)] ?? typeName(t)}'",
              statement: 'return ${t.codeName}.fromJson(json);'),
      ],
      defaultStatements: [
        "throw ArgumentError('Cannot decode $token: unknown or missing \"${discriminator.field}\" value (\$discriminator)');",
      ],
    );
    return [
      "final typename = json['__typename'];",
      byTypename,
      "final discriminator = json['${discriminator.field}'];",
      byValue,
    ];
  }

  String serializeInterface(GLInterfaceDefinition interface) {
    final codeName = interface.codeName;
    final fields = interface.getSerializableFields(grammar.mode);
    final decorators = serializeDecorators(interface.getDirectives());
    final serialisableImplemenations = interface.getSerializableImplementations(mode);
    final source = codeGenUtils.createInterface(
      className: codeName,
      baseInterfaceNames: interface.interfaces.map((e) => resolveCodeName(e.tokenInfo.token)).toList(),
      statements: [
        for (var field in fields) _serializeInterfaceMember(interface, field),
        if (!shouldSkipJsonMethods(interface)) ...[
          _serializeToJsonForInterface(codeName),
          if (interface.syntheticImplementation != null)
            serializeSyntheticInterfaceFromJson(interface)
          else if (serialisableImplemenations.isNotEmpty)
            _serializeFromJsonForInterface(codeName, serialisableImplemenations),
        ],
      ],
    );
    return decorators.isEmpty ? "$source\n" : "${decorators.trim()}\n$source\n";
  }

  String _serializeInterfaceMember(GLInterfaceDefinition interface, GLField field) {
    final decorators = serializeDecorators(field.getDirectives());
    final declaration =
        interface.fieldAsMethods ? serializeMethodDeclaration(field) : serializeGetterDeclaration(field);
    return decorators.isEmpty ? "$declaration;" : "${decorators.trim()}\n$declaration;";
  }

  String serializeGetterDeclaration(GLField field) {
    return """${serializeType(field.type)} get ${field.codeName}""";
  }

  String serializeMethodDeclaration(GLField field) {
    final args = field.arguments
        .map((a) => "${serializeType(a.type)} ${a.codeName}")
        .join(", ");
    return "${serializeType(field.type)} ${field.codeName}($args)";
  }

  @override
  String getFileNameFor(GLToken token) {
    return "${resolveCodeName(token.token).toSnakeCase()}.dart";
  }

  @override
  String serializeImportToken(GLToken token) {
    String? init;
    if (token is GLEnumDefinition) {
      init = "enums/${getFileNameFor(token)}";
    } else if (token is GLInterfaceDefinition) {
      init = "interfaces/${getFileNameFor(token)}";
    } else if (token is GLTypeDefinition) {
      init = "types/${getFileNameFor(token)}";
    } else if (token is GLInputDefinition) {
      init = "inputs/${getFileNameFor(token)}";
    } 

    return "import '${importPrefix}/${init}';";
  }

  @override
  String serializeImport(String import) {
    return import.startsWith('import ') ? import : """import '$import';""";
  }

  @override
  String serializeGlClass(GLClassModel theClass,
      {bool withImports = true}) {
    if (!withImports || theClass.importDepencies.isEmpty && theClass.imports.isEmpty) {
      return super.serializeGlClass(theClass, withImports: withImports);
    }
    final tokenImports = theClass.importDepencies
        .map((dep) => serializeImportToken(dep))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final simpleImports = theClass.imports.map((imp) => serializeImport(imp)).toList();
    final merged = GLClassModel(
      imports: {...tokenImports, ...simpleImports}.toList(),
      body: theClass.body,
    );
    return super.serializeGlClass(merged, withImports: withImports);
  }
}
