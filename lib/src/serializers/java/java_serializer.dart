import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';
import 'package:graphlink/src/graphql_string_literal.dart';
import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/json_expressions.dart';
import 'package:graphlink/src/utils.dart';
import 'package:graphlink/src/serializers/java/java_mapping_serializer.dart';
import 'package:graphlink/src/serializers/java/java_interface_serializer.dart';
import 'package:graphlink/src/serializers/java/java_accessor_serializer.dart';

const _list = "List";
const _map = "Map";
const _javaNumbers = {"Byte", "Short", "Integer", "Long", "Float", "Double", "byte", "short", "int", "long", "float", "double"};

const _javaNumberMethods = {
  "Byte": "byteValueExact()",
  "Short": "shortValueExact()",
  "Integer": "intValueExact()",
  "Long": "longValueExact()",
  "Float": "floatValue()",
  "Double": "doubleValue()",
  "byte": "byteValueExact()",
  "short": "shortValueExact()",
  "int": "intValueExact()",
  "long": "longValueExact()",
  "float": "floatValue()",
  "double": "doubleValue()"
};

const Set<String> javaPrimitives = {
  'boolean',
  'byte',
  'short',
  'int',
  'long',
  'float',
  'double',
  'char',
};

String mapOf(String key, String type) {
  return '${_map}<${key}, ${type}>';
}

class JavaSerializer extends GLSerializer with JsonExpressions {
  late final accessors = JavaAccessorSerializer(this);

  late final interfaces = JavaInterfaceSerializer(this);

  @override
  late final GLMappingSerializer mapping = JavaMappingSerializer(this);

  final bool inputsAsRecords;

  final bool typesAsRecords;

  final bool typesCheckForNulls;

  final bool inputsCheckForNulls;

  final bool immutableInputFields;

  final bool immutableTypeFields;

  final bool jspecify;

  final codeGenUtils = JavaCodeGenUtils();

  @override
  Map<String, String> get defaultTypeMap => const {
        "ID": "String",
        "String": "String",
        "Float": "Double",
        "Int": "Integer",
        "Boolean": "Boolean",
        "Long": "Long",
        "Null": "null",
        "gqlMapStrObj": "Map<String, Object>",
        "dynamicValue": "Object",
        "void": "void",
      };

  JavaSerializer(
    super.grammar, {
    this.inputsAsRecords = false,
    this.typesAsRecords = false,
    this.typesCheckForNulls = true,
    this.inputsCheckForNulls = true,
    this.immutableInputFields = true,
    this.immutableTypeFields = false,
    this.jspecify = false,
    super.typeMapOverrides = const {},
    required super.importPrefix,
  }) {
    _initAnnotations();
    if (jspecify) grammar.applyJspecifyAnnotations(isPrimitive: isPrimitiveType);
  }

  @override
  String serializeDefaultLiteral(GLType type, Object? value, {bool needsConst = false}) {
    if (value == null) return 'null';
    if (value is int) {
      // A GraphQL Float default without a decimal point (e.g. `min: Float = 0`)
      // parses as a Dart int, but boxed Double/Float fields don't accept an
      // Int literal in a field initializer (e.g. `private Double min = 0;`
      // fails to compile) — emit a floating literal instead.
      final javaType = getTypeNameFromGQExternal(type.token) ?? resolveCodeName(type.token);
      if (javaType == 'Double' || javaType == 'Float') {
        return _serializeFloatingLiteral(value.toDouble(), javaType);
      }
      if (javaType == 'Long' || javaType == 'long') return '${value}L';
      return '$value';
    }
    if (value is double) {
      final javaType = getTypeNameFromGQExternal(type.token) ?? resolveCodeName(type.token);
      return _serializeFloatingLiteral(value, javaType);
    }
    if (value is bool) return '$value';
    if (value is List) {
      final innerType = type.inlineType;
      final items = value.map((e) => serializeDefaultLiteral(innerType, e)).join(', ');
      return 'Arrays.asList($items)';
    }
    if (value is Map) {
      final inputDef = grammar.inputs[type.token]!;
      final args = inputDef.fields.map((f) {
        return serializeDefaultLiteral(f.type, value[f.name.token]);
      }).join(', ');
      return 'new ${resolveCodeName(type.token)}($args)';
    }
    if (value is String) {
      if (grammar.enums.containsKey(type.token)) {
        return '${resolveCodeName(type.token)}.${grammar.enumConstantName(type.token, value)}';
      }
      return stringLiteral(decodeGraphqlString(value));
    }
    return '"$value"';
  }

  // Dart's double.toString() can emit "NaN"/"Infinity"/"-Infinity", none of
  // which are valid Java literals — those need the Double/Float constants
  // instead. A Java float literal also needs an explicit `f` suffix, since a
  // bare decimal literal defaults to double.
  @override
  String stringLiteral(String decoded) =>
      '"${escapeStringBody(decoded, quote: '"', control: (unit) => '\\u${unit.toRadixString(16).padLeft(4, '0')}')}"';

  String _serializeFloatingLiteral(double value, String javaType) {
    final isFloat = javaType == 'Float';
    if (value.isNaN) return isFloat ? 'Float.NaN' : 'Double.NaN';
    if (value.isInfinite) {
      final sign = value.isNegative ? 'NEGATIVE' : 'POSITIVE';
      return isFloat ? 'Float.${sign}_INFINITY' : 'Double.${sign}_INFINITY';
    }
    return isFloat ? '${value}f' : '$value';
  }

  void _initAnnotations() {
    grammar.handleAnnotations((val) => AnnotationSerializer.serializeAnnotation(val, multiLineString: false));
  }

  String serializeAnnotation(GLDirectiveValue value) {
    return AnnotationSerializer.serializeAnnotation(value, multiLineString: false);
  }

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    var toJson = serializeToJsonForEnum(def);
    var fromJson = serializeFromJsonForEnum(def);
    var enum_ = codeGenUtils.createEnum(
        enumName: def.codeName,
        enumValues: def.allValues.map((e) => doSerializeEnumValue(e)).toList(),
        methods: [if (fromJson.isNotEmpty) fromJson, if (toJson.isNotEmpty) toJson]);
    buffer.writeln(enum_);
    return buffer.toString();
  }

  String serializeToJsonForEnum(GLEnumDefinition def) {
    return codeGenUtils.createMethod(
      returnType: "public String",
      methodName: "toJson",
      statements: [
        codeGenUtils.switchStatement(
          expression: "this",
          cases: [...def.values.map((v) => JavaCaseStatement(caseValue: v.codeName, statement: 'return "${v.value.token}";'))],
          defaultStatements: ['throw new IllegalArgumentException("Invalid ${def.codeName}: " + this);'],
        )
      ],
    );
  }

  String serializeFromJsonForEnum(GLEnumDefinition def) {
    final unknown = def.unknownValue;
    return codeGenUtils.createMethod(
      returnType: "public static ${def.codeName}",
      methodName: "fromJson",
      arguments: ["String value"],
      statements: [
        codeGenUtils.ifStatement(condition: "value == null", ifBlockStatements: ["return null;"]),
        codeGenUtils.switchStatement(
          expression: "value",
          cases: [...def.values.map((v) => JavaCaseStatement(caseValue: '"${v.value.token}"', statement: 'return ${v.codeName};'))],
          defaultStatements: [
            unknown != null
                ? 'return ${unknown.codeName};'
                : 'throw new IllegalArgumentException("Invalid ${def.codeName}: " + value);',
          ],
        )
      ],
    );
  }

  @override
  String doSerializeEnumValue(GLEnumValue value) {
    var deprecation = serializeEnumValueDeprecation(value);
    var decorators = serializeDecorators(value.getDirectives(), joiner: " ");
    if (deprecation.isEmpty && decorators.isEmpty) {
      return value.codeName;
    } else {
      return [deprecation, decorators, value.codeName].where((s) => s.isNotEmpty).join(" ");
    }
  }

  @override
  String serializeFieldDeprecation(GLField field) {
    if (!field.isDeprecated) return '';
    final reason = field.deprecationReason ?? 'No longer supported';
    final safeReason = reason.replaceAll('*/', '*\\/').replaceAll(RegExp(r'[\r\n]+'), ' ');
    return "/** @deprecated $safeReason */\n@Deprecated\n";
  }

  @override
  String serializeEnumValueDeprecation(GLEnumValue value) {
    if (!value.isDeprecated) return '';
    final reason = value.deprecationReason ?? 'No longer supported';
    final safeReason = reason.replaceAll('*/', '*\\/').replaceAll(RegExp(r'[\r\n]+'), ' ');
    return "/** @deprecated $safeReason */ @Deprecated";
  }

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField, {bool isOverride = false}) {
    final type = def.type;
    final name = def.codeName;
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives(), joiner: "\n");
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    buffer.write("private ");
    if (immutable) {
      buffer.write("final ");
    }
    buffer.write('${serializeType(type)} $name');
    // Only emit field initializer for non-final fields — final fields
    // receive their default in the constructor body instead.
    if (!immutable && !isTypeField && def.initialValue != null) {
      buffer.write(' = ${serializeDefaultLiteral(type, def.initialValue)}');
    }
    buffer.write(';');
    return buffer.toString();
  }

  String serializeArgument(GLArgumentDefinition arg) {
    var type = arg.type;
    var name = arg.codeName;
    var decorators = serializeDecorators(arg.getDirectives(), joiner: " ");
    var result = "${serializeType(type)} ${name}";
    if (decorators.isNotEmpty) {
      return "$decorators$result";
    }
    return result;
  }

  String serializeArgumentField(GLField def, {bool withDecorators = false, String decoratorJoiner = "\n", bool isTypeField = false}) {
    final type = def.type;
    final name = def.codeName;
    final buffer = StringBuffer();
    if (withDecorators) {
      var decorators = serializeDecorators(def.getDirectives(), joiner: decoratorJoiner);
      if (decorators.trim().isNotEmpty) {
        buffer.write(decorators.trim());
        buffer.write(decoratorJoiner);
      }
    }
    buffer.write(serializeType(type));
    buffer.write(" ");
    buffer.write(name);
    return buffer.toString();
  }

  bool isPrimitiveType(GLType type) {
    var serialized = serializeType(type);
    return javaPrimitives.contains(serialized);
  }

  @override
  String serializeType(GLType def) {
    final String type;
    if (def is GLVoidType) {
      type = 'void';
    } else if (def is GLMapType) {
      type = mapOf(serializeType(def.keyType).toBoxedType, serializeType(def.valueType).toBoxedType);
    } else if (def is GLListType) {
      type = JavaCodeGenUtils.listOf(grammar, serializeType(def.inlineType));
    } else {
      final token = def.token;
      var baseType = getTypeNameFromGQExternal(token) ?? resolveCodeName(token);
      if (typeIsJavaPrimitive(baseType) && def.nullable) {
        baseType = baseType.toBoxedType;
      }
      type = baseType;
    }
    final wrapper = def.wrapper;
    if (wrapper == null) return type;
    final wrapperImport = def.wrapperImport;
    if (wrapperImport != null) {
      (grammar.types[def.token] ?? grammar.interfaces[def.token])
          ?.addImport(wrapperImport);
    }
    return '$wrapper<${type.toBoxedType}>';
  }

  @override
  String doSerializeInputDefinition(GLInputDefinition def) {
    final decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    if (inputsAsRecords) {
      buffer.writeln(serializeRecord(def.codeName, def.fields, {}, def, extraStatements: generateMappingMethods(def)));
      return buffer.toString();
    }
    var class_ = codeGenUtils.createClass(className: def.codeName, statements: [
      ...def.getSerializableFields(grammar.mode).map((e) => serializeField(e, immutableInputFields, false)),
      "",
      if (!immutableInputFields) accessors.generateContructor(def.codeName, [], "public", def, checkForNulls: inputsCheckForNulls),
      "",
      accessors.generateContructor(def.codeName, def.getSerializableFields(grammar.mode), immutableInputFields ? "public" : "private", def,
          checkForNulls: inputsCheckForNulls),
      accessors.generateBuilder(def.codeName, def.getSerializableFields(grammar.mode), true),
      ...def.getSerializableFields(grammar.mode).map((e) => accessors.serializeGetter(e, def, checkForNulls: inputsCheckForNulls)),
      ...def.getSerializableFields(grammar.mode).where((field) {
        //check for the next directive here
        return !immutableInputFields;
      }).map((e) => accessors.serializeSetter(e, def, checkForNulls: inputsCheckForNulls)),
      generateToJson(def.getSerializableFields(grammar.mode), def),
      generateFromJson(def.getSerializableFields(mode), def.codeName, def),
      ...generateMappingMethods(def),
    ]);
    buffer.write(class_);
    return buffer.toString();
  }

  bool _isNumber(GLType type) {
    if (type.isList) {
      return _isNumber(type.inlineType);
    }
    var serializedType = serializeType(type);
    return _javaNumbers.contains(serializedType);
  }

  String _numberCast(GLType type, String json) {
    final method = _numberValueMethod(type);
    return method.contains('Exact') ? 'new java.math.BigDecimal(((Number)$json).toString()).$method' : '((Number)$json).$method';
  }

  String _numberValueMethod(GLType type) {
    if (type.isList) {
      return _numberValueMethod(type.inlineType);
    }
    return _javaNumberMethods[serializeType(type)]!;
  }

  @override
  String listFromJson(GLType list, String json, String element, String body, GLImportSink? context) {
    context?.addImport(JavaImports.collectors);
    final stream = JavaCodeGenUtils.streamMapCollect(receiver: '((${_list}<?>)$json)', param: element, body: body);
    return JavaCodeGenUtils.nullSafeExpr(json, stream, list.nullable);
  }

  @override
  String enumFromJson(GLType type, String json) =>
      JavaCodeGenUtils.nullSafeExpr(json, '${resolveCodeName(type.token)}.fromJson((String)$json)', type.nullable);

  @override
  String modelFromJson(GLType type, String json) => JavaCodeGenUtils.nullSafeExpr(
      json, '${resolveCodeName(type.token)}.fromJson((${mapOf('String', 'Object')})$json)', type.nullable);

  @override
  String plainFromJson(GLType type, String json) {
    final cast = _isNumber(type) ? _numberCast(type, json) : '(${serializeType(type)})$json';
    return JavaCodeGenUtils.nullSafeExpr(json, cast, type.nullable);
  }

  List<String> _requiredFieldChecks(List<GLField> fields, GLToken context) {
    final token = context.token;
    if (!grammar.restReachableTypeNames.contains(token)) return const [];
    return [
      for (final field in fields)
        if (!field.type.nullable && field.initialValue == null)
          codeGenUtils.ifStatement(
            condition: 'json.get("${field.name.token}") == null',
            ifBlockStatements: ['throw new IllegalArgumentException("$token.${field.name.token} is missing or null in the response");'],
          ),
    ];
  }

  String generateFromJson(List<GLField> fields, String token, GLToken context) {
    var buffer = StringBuffer();
    context.addImport(JavaImports.suppressWarnings);

    buffer.writeln('@SuppressWarnings("unchecked")');
    buffer.writeln(
      codeGenUtils.createMethod(returnType: "public static ${token}", methodName: "fromJson", arguments: [
        '${mapOf('String', 'Object')} json'
      ], statements: [
        ..._requiredFieldChecks(fields, context),
        "return new ${token}(",
        ...fields.map((field) {
          var statement = fromJsonExpr(field.type, 'json.get("${field.name.token}")', context: context);
          if (field != fields.last) {
            return "${statement},";
          }
          return statement;
        }),
        ");"
      ]),
    );
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Mapping methods (@glMapsTo)
  // ---------------------------------------------------------------------------

  String generateToJson(List<GLField> fields, GLToken context) {
    var buffer = StringBuffer();
    context.addImport(JavaImports.hashMap);
    context.addImport(JavaImports.map);

    final typeName = context is GLTypeDefinition ? context.jsonTypeName : null;
    final omitNulls = context is GLInputDefinition && context.isOneOf;

    buffer.writeln(
      codeGenUtils.createMethod(returnType: "public ${mapOf('String', 'Object')}", methodName: "toJson", statements: [
        "${mapOf('String', 'Object')} glMap__ = new HashMap<>();",
        if (typeName != null) 'glMap__.put("__typename", "$typeName");',
        ...fields.map((field) {
          final put = 'glMap__.put("${field.name}", ${toJsonExpr(field.type, field.codeName, context: context)});';
          return omitNulls
              ? codeGenUtils.ifStatement(condition: '${field.codeName} != null', ifBlockStatements: [put])
              : put;
        }),
        'return glMap__;'
      ]),
    );

    return buffer.toString();
  }

  @override
  String listToJson(GLType list, String value, String element, String body, GLImportSink? context) {
    context?.addImport(JavaImports.collectors);
    if (element == body) return JavaCodeGenUtils.streamMapCollect(receiver: value, nullable: list.nullable);
    return JavaCodeGenUtils.streamMapCollect(receiver: value, param: element, body: body, nullable: list.nullable);
  }

  @override
  String modelToJson(GLType type, String value) => JavaCodeGenUtils.safeCall(value, 'toJson()', type.nullable);

  static const _jsonTypeCasts = {
    'String': 'java.util.Objects.requireNonNull((String)@)',
    'Int': 'new java.math.BigDecimal(((Number)@).toString()).longValueExact()',
    'Double': '((Number)@).doubleValue()',
    'Bool': 'java.util.Objects.requireNonNull((Boolean)@)',
    'Map': 'java.util.Objects.requireNonNull((Map<String, Object>)@)',
    'List': 'java.util.Objects.requireNonNull((List<?>)@)',
  };

  @override
  String scalarFromJson(GLScalarCodec codec, String json, {required bool nullable}) {
    final cast = _jsonTypeCasts[codec.jsonType];
    final source = cast != null && codec.canDecode ? cast.replaceAll('@', json) : json;
    return JavaCodeGenUtils.nullSafeExpr(json, codec.decode(source), nullable);
  }

  @override
  String scalarToJson(GLScalarCodec codec, String value, {required bool nullable}) =>
      JavaCodeGenUtils.nullSafeExpr(value, codec.encode(value), nullable);

  String? getJSpecifyAnnoation(GLField field) {
    var decorators = field.getDirectives(skipGenerated: false).where((e) => e.token == glDecorators).toList();
    if (decorators.isEmpty) {
      return null;
    }
    final directive = decorators.first;
    var value = directive.getArgValue("value");
    if (value is List<String>) {
      for (var v in value) {
        var vv = v.substring(1, v.length - 1);
        if (vv == jspecifyNonNull || vv == jspecifyNullable) {
          return vv;
        }
      }
    }
    return null;
  }

  String serializeMethod(GLField field, {String? modifier}) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(field.getDirectives()).trim();
    var args = serializeListText(field.arguments.map(serializeArgument).toList(), withParenthesis: false, join: ", ");
    var result = "${serializeType(field.type)} ${field.codeName}($args)";
    if (modifier != null) {
      result = "$modifier $result";
    }
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    buffer.write(result);
    return buffer.toString();
  }

  String serializeRecord(
    String recordName,
    List<GLField> fields,
    Set<String> interfaceNames,
    GLToken context, {
    List<String> extraStatements = const [],
    bool skipJsonMethods = false,
  }) {
    return codeGenUtils.createRecord(
        recordName: recordName,
        components: fields.map((f) {
          final annotation = isPrimitiveType(f.type) ? null : getJSpecifyAnnoation(f);
          final component = serializeArgumentField(f, withDecorators: true, decoratorJoiner: " ");
          // withDecorators already emits jspecify for type fields; only prepend for input fields
          if (annotation == null || component.startsWith(annotation)) return component;
          return '$annotation $component';
        }).toList(),
        interfaces: interfaceNames.toList(),
        statements: [
          if (!skipJsonMethods) generateToJson(fields, context),
          if (!skipJsonMethods) generateFromJson(fields, recordName, context),
          ...extraStatements,
        ]);
  }

  /// Recursively wildcards every `List<...>` nesting level (e.g.
  /// `List<? extends List<? extends Node>>`) so a narrowed override like
  /// `List<List<Alpha>>` type-checks against `List<List<Node>>` — Java
  /// generics are invariant, so covariance must be threaded through every
  /// nested list layer, not just the outermost one.
  String wildcardListReturnType(GLType type) {
    if (type is GLListType) {
      final inner = wildcardListReturnType(type.inlineType);
      return 'List<? extends $inner>';
    }
    return serializeType(type);
  }

  String getterName(GLTokenWithFields owner, String fieldName) {
    final field = owner.getFieldByName(fieldName);
    if (field == null) {
      throw ArgumentError("No field named '$fieldName' on ${owner.tokenInfo}");
    }
    // An implementer's override must keep the interface's accessor name even
    // when it narrows nullability — narrowing `Boolean` to `Boolean!` would
    // otherwise flip the accessor from `getX` to `isX` and break the override.
    final interfaceField = owner is GLTypeDefinition ? owner.getInterfaceField(field) : null;
    final isBoolean = serializeType(interfaceField?.type ?? field.type) == "boolean";
    final prefix = isBoolean ? "is" : "get";
    return "$prefix${field.codeName.firstUp}";
  }

  /// Java accessor name: `get`/`is`/`set` + capitalised property. Public &
  /// static so client serializers can build input-object getter access without a
  /// [JavaSerializer] instance.
  static String accessorName(String name, {bool setter = false, bool isBoolean = false}) {
    final prefix = setter ? "set" : (isBoolean ? "is" : "get");
    return "$prefix${name.firstUp}";
  }

  /// The getter call for [field] on a generated input/type. Records expose the
  /// bare component accessor (`name()`); otherwise it is `getName()` / `isFlag()`.
  /// [isRecord] and [isBoolean] are passed in because they depend on config and
  /// type resolution the caller already knows.
  static String getterCall(GLField field, {required bool isRecord, required bool isBoolean}) {
    if (isRecord) return "${field.codeName}()";
    return "${accessorName(field.name.token, isBoolean: isBoolean)}()";
  }

  @override
  String doSerializeTypeDefinition(GLTypeDefinition def) {
    if (def is GLInterfaceDefinition) {
      // Internal interfaces always use JavaBean getter style regardless of typesAsRecords,
      // because their implementations are always classes (never records).
      final isInternal = def.getDirectiveByName(glInternal) != null;
      return interfaces.serializeInterface(def,
          getters: def.getDirectiveByName(glInterfaceFieldAsProperties) == null && !def.fieldAsMethods,
          forceClassGetters: isInternal,
          skipJsonConversionMethods: shouldSkipJsonMethods(def));
    } else {
      return _doSerializeTypeDefinition(def);
    }
  }

  String _doSerializeTypeDefinition(GLTypeDefinition def) {
    final codeName = def.codeName;
    final interfaceNames = def.interfaceNames.map((e) => resolveCodeName(e.token)).toSet();

    final decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    if (typesAsRecords && def.getDirectiveByName(glInternal) == null) {
      buffer.writeln(serializeRecord(codeName, def.fields, interfaceNames, def,
          skipJsonMethods: shouldSkipJsonMethods(def)));
      return buffer.toString();
    }
    buffer.writeln(codeGenUtils.createClass(className: codeName, interfaceNames: interfaceNames.toList(), statements: [
      ...def.getSerializableFields(grammar.mode).map((e) => serializeField(e, immutableTypeFields, true)),
      "",
      if (!immutableTypeFields) accessors.generateContructor(codeName, [], "public", def, checkForNulls: typesCheckForNulls, isTypeField: true),
      "",
      accessors.generateContructor(codeName, def.getSerializableFields(grammar.mode), immutableTypeFields ? "public" : "private", def, isTypeField: true),
      "",
      accessors.generateBuilder(codeName, def.getSerializableFields(grammar.mode), false),
      "",
      ...def
          .getSerializableFields(grammar.mode)
          .map((e) => accessors.serializeGetter(e, def, checkForNulls: typesCheckForNulls, isTypeField: true, isOverride: def.isOverride(e))),
      "",
      ...def.getSerializableFields(grammar.mode).where((field) {
        // @TODO check for mutable directive
        return !immutableTypeFields;
      }).map((e) => accessors.serializeSetter(e, def, checkForNulls: typesCheckForNulls)),
      generateEqualsAndHashCode(def),
      if (!shouldSkipJsonMethods(def)) ...[
        generateFromJson(def.getSerializableFields(grammar.mode), codeName, def),
        generateToJson(def.getSerializableFields(grammar.mode), def),
      ],
    ]));
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
    def.addImport("java.util.Objects");
    var buffer = StringBuffer();
    buffer.writeln('@Override');
    buffer.writeln(codeGenUtils.createMethod(returnType: "public boolean", methodName: "equals", arguments: [
      'Object o'
    ], statements: [
      codeGenUtils.ifStatement(condition: '!(o instanceof $token)', ifBlockStatements: ['return false;']),
      '$token o2 = ($token) o;',
      'return ${fields.map((e) => "Objects.equals($e, o2.$e);").join(" && ")}'
    ]));

    buffer.writeln();
    buffer.writeln('@Override');

    buffer.writeln(
      codeGenUtils.createMethod(returnType: 'public int', methodName: 'hashCode', statements: ['return Objects.hash(${fields.join(", ")});']),
    );

    return buffer.toString();
  }

  @override
  String serializeSyntheticInterfaceFromJson(GLInterfaceDefinition interface) {
    return codeGenUtils.createMethod(
      returnType: 'static ${interface.codeName}',
      methodName: 'fromJson',
      arguments: ['${mapOf("String", "Object")} json'],
      statements: ['return ${interface.syntheticImplementation!.codeName}.fromJson(json);'],
    );
  }

  @override
  String getFileNameFor(GLToken token) {
    return "${resolveCodeName(token.token)}.java";
  }

  @override
  String serializeImportToken(GLToken token) {
    String? path;
    final codeName = resolveCodeName(token.token);

    if (grammar.enums.containsKey(token.token)) {
      path = "enums.$codeName";
    } else if (grammar.interfaces.containsKey(token.token) || grammar.projectedInterfaces.containsKey(token.token)) {
      path = "interfaces.$codeName";
    } else if (grammar.types.containsKey(token.token) || grammar.projectedTypes.containsKey(token.token)) {
      path = "types.$codeName";
    } else if (grammar.inputs.containsKey(token.token)) {
      path = "inputs.$codeName";
    } else if (grammar.services.containsKey(token.token)) {
      path = "services.$codeName";
    } else if (grammar.controllers.containsKey(token.token)) {
      path = "controllers.$codeName";
    }
    return "import ${importPrefix}.${path};";
  }

  @override
  String serializeImport(String import) {
    return 'import ${import};';
  }

  @override
  String serializeGlClass(GLClassModel theClass, {bool withImports = true}) {
    if (!withImports || theClass.importDepencies.isEmpty && theClass.imports.isEmpty) {
      return super.serializeGlClass(theClass, withImports: withImports);
    }
    final tokenImports = theClass.importDepencies.map((dep) => serializeImportToken(dep)).where((l) => l.trim().isNotEmpty).toList();
    final simpleImports = theClass.imports.map((imp) => serializeImport(imp)).toList();
    final merged = GLClassModel(
      imports: {...tokenImports, ...simpleImports}.toList(),
      body: theClass.body,
    );
    return super.serializeGlClass(merged, withImports: withImports);
  }
}
