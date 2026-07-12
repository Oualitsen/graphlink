import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';

class DartSerializer extends GLSerializer {
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
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    buffer.writeln("enum ${def.codeName} {");
    buffer.write(def.values
        .map((e) => doSerializeEnumValue(e))
        .toList()
        .join(", ")
        .ident());
    buffer.writeln(";");
    // toJson
    buffer.writeln(codeGenUtils
        .createMethod(
            methodName: "toJson",
            returnType: "String",
            arguments: [],
            namedArguments: false,
            statements: [
              codeGenUtils.switchStatement(expression: "this", cases: [
                ...def.values.map((val) => DartCaseStatement(
                    caseValue: val.codeName,
                    statement: 'return "${val.token}";'))
              ])
            ])
        .ident());

    // end toJson
    // fromJson
    buffer.writeln(codeGenUtils
        .createMethod(
            methodName: "fromJson",
            arguments: ['String value'],
            namedArguments: false,
            returnType: 'static ${def.codeName}',
            statements: [
              codeGenUtils.switchStatement(
                  expression: 'value',
                  cases: [
                    ...def.values.map((val) => DartCaseStatement(
                        caseValue: '"${val.token}"',
                        statement: 'return ${def.codeName}.${val.codeName};'))
                  ],
                  defaultStatements:
                      ['throw ArgumentError("Invalid ${def.codeName}: \$value");'])
            ])
        .ident());
    buffer.writeln("}");
    return buffer.toString();
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
      generateToJson(fields),
      generateFromJson(fields, def.codeName),
      ...mappingMethods,
    ]);

    buffer.writeln(inputClass);
    return buffer.toString();
  }

  @override
  String generateToMethod(
      GLInputDefinition def, String targetType, ToMappingPlan plan) {
    final params = [
      ...plan.requiredParams.map(
        (f) =>
            'required ${serializeType(f.targetField.type)} ${f.targetField.codeName}',
      ),
      ...plan.defaultParams.map(
        (f) =>
            'required ${serializeType(f.targetField.type)} default${f.targetField.codeName.firstUp}',
      ),
    ];

    final assignments = [
      ...plan.autoMapped.map((f) {
        final suffix =
            _callToMapping(f.sourceField!.type, f.targetField.type, 0);
        return '${f.targetField.codeName}: ${f.sourceField!.codeName}$suffix';
      }),
      ...plan.defaultParams.map(
        (f) =>
            '${f.targetField.codeName}: ${f.sourceField!.codeName} ?? default${f.targetField.codeName.firstUp}',
      ),
      ...plan.requiredParams.map(
        (f) => '${f.targetField.codeName}: ${f.targetField.codeName}',
      ),
    ];

    return codeGenUtils.createMethod(
      returnType: targetType,
      methodName: 'to${targetType.firstUp}',
      namedArguments: true,
      arguments: params,
      statements: ['return $targetType(${assignments.join(', ')});'],
    );
  }

  @override
  String generateFromMethod(
      GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = targetType.firstLow;

    final autoMappedAssignments = plan.autoMapped.map((f) {
      final variable = '$targetVar.${f.targetField.codeName}';
      final expr = _callFromMapping(variable, f.sourceField!.type.firstType.token, f.targetField.type, 0);
      return '${f.sourceField!.codeName}: $expr';
    });

    final nullableListDefaultParams = plan.nullableListDefaults.map((f) =>
        '${serializeType(f.sourceField!.type)} default${f.sourceField!.codeName.firstUp} = const []');
    final nullableListAssignments = plan.nullableListDefaults.map((f) {
      final variable = '$targetVar.${f.targetField.codeName}';
      final expr = _callFromMapping(variable, f.sourceField!.type.firstType.token, f.targetField.type, 0);
      return '${f.sourceField!.codeName}: $expr ?? default${f.sourceField!.codeName.firstUp}';
    });

    final promotedParams = plan.promoted.map(
      (f) => 'required ${serializeType(f.sourceField!.type)} ${f.sourceField!.codeName}',
    );
    final promotedAssignments = plan.promoted.map(
      (f) => '${f.sourceField!.codeName}: ${f.sourceField!.codeName}',
    );

    final inputOnlyParams = plan.inputOnly.map(
      (f) => '${f.type.nullable ? '' : 'required '}${serializeType(f.type)} ${f.codeName}',
    );
    final inputOnlyAssignments = plan.inputOnly.map(
      (f) => '${f.codeName}: ${f.codeName}',
    );

    return codeGenUtils.createMethod(
      returnType: 'static ${def.codeName}',
      methodName: 'from${targetType.firstUp}',
      namedArguments: true,
      arguments: [
        'required $targetType $targetVar',
        ...nullableListDefaultParams,
        ...promotedParams,
        ...inputOnlyParams,
      ],
      statements: [
        'return ${def.codeName}(${[
          ...autoMappedAssignments,
          ...nullableListAssignments,
          ...promotedAssignments,
          ...inputOnlyAssignments,
        ].join(', ')});',
      ],
    );
  }

  /// Returns a suffix to append to a source field value for toXxx() assignments.
  /// e.g. '' for direct copy, '.map((e0) => e0.toTag()).toList()' for mapped lists.
  String _callToMapping(GLType sourceType, GLType targetType, int index) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) {
        return DartCodeGenUtils.toListCopy('', sourceType.nullable); // same element type — copy the list
      }
      final varName = 'e$index';
      final inner = _callToMapping(
          sourceType.inlineType, targetType.inlineType, index + 1);
      return DartCodeGenUtils.mapToList(
          receiver: '', param: varName, body: '$varName$inner', nullable: sourceType.nullable);
    }
    final sourceInput = grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      final dot = sourceType.nullable ? '?.' : '.';
      return '${dot}to${resolveCodeName(targetType.token).firstUp}()';
    }
    return ''; // same type — direct copy
  }

  /// Returns the full expression for a fromXxx() field assignment.
  /// e.g. 'order.tags.map((e0) => TagInput.fromTag(e0)).toList()'
  String _callFromMapping(
      String variable, String sourceElemToken, GLType targetType, int index) {
    if (targetType.isList) {
      if (sourceElemToken == targetType.firstType.token) {
        return DartCodeGenUtils.toListCopy(variable, targetType.nullable); // same element type — copy the list
      }
      final varName = 'e$index';
      final inner = _callFromMapping(
          varName, sourceElemToken, targetType.inlineType, index + 1);
      return DartCodeGenUtils.mapToList(
          receiver: variable, param: varName, body: inner, nullable: targetType.nullable);
    }
    final sourceInput = grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = resolveCodeName(sourceElemToken);
      final targetCodeName = resolveCodeName(targetType.token);
      if (targetType.nullable) {
        return '$variable != null ? $sourceCodeName.from${targetCodeName.firstUp}(${targetCodeName.firstLow}: $variable!) : null';
      }
      return '$sourceCodeName.from${targetCodeName.firstUp}(${targetCodeName.firstLow}: $variable)';
    }
    return variable; // same type — direct copy
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
      // quoted string — strip surrounding quotes, emit as Dart single-quoted string
      final content = value.startsWith('"') && value.endsWith('"')
          ? value.substring(1, value.length - 1)
          : value;
      return "'$content'";
    }
    return "'$value'";
  }

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
            'return ${token}(',
            ...fields.map((e) => fieldFromJson(e)).map((e) => "${e},".ident()),
            ');'
          ]),
    );
    return buffer.toString();
  }

  String generateToJson(List<GLField> fields, {String? typeName}) {
    var buffer = StringBuffer();

    buffer.writeln(codeGenUtils.method(
        returnType: 'Map<String, dynamic>',
        methodName: 'toJson',
        statements: [
          "return {",
          if (typeName != null) "'__typename': '$typeName',".ident(),
          ...fields
              .map((field) => fieldToJson(field).ident())
              .map((e) => "${e},"),
          '};'
        ]));
    return buffer.toString();
  }

  String fieldToJson(GLField field) {
    // Wire key keeps the original GraphQL name; value reads the safe identifier.
    var buffer = StringBuffer("'${field.name}': ");
    var toJosnCall = callToJson(field, field.type, 0);
    buffer.write("${field.codeName}${toJosnCall}");
    return buffer.toString();
  }

  String fieldFromJson(GLField field) {
    // Constructor param uses the safe identifier; json lookup uses the wire key.
    var buffer = StringBuffer('${field.codeName}: ');
    var toJosnCall =
        callFromJson("json['${field.name}']", field, field.type, 0);
    buffer.write(toJosnCall);
    return buffer.toString();
  }

  String castDynamicToType(String variable, GLType type) {
    String dot = type.nullable ? "?." : ".";
    String serializedType = serializeType(type);
    String numSuffix = type.nullable ? "?" : "";

    if (type.isList) {
      return "(${variable} as List<dynamic>${numSuffix})";
    }
    if (grammar.isEnum(type.token)) {
      var enumFromJson = "${resolveCodeName(type.token)}.fromJson(${variable} as String)";
      return DartCodeGenUtils.nullSafeExpr(variable, enumFromJson, type.nullable);
    }
    if (grammar.isProjectableType(type.token)) {
      var typeFromJson =
          "${resolveCodeName(type.token)}.fromJson(${variable} as Map<String, dynamic>)";
      return DartCodeGenUtils.nullSafeExpr(variable, typeFromJson, type.nullable);
    }

    if (serializedType == "double" || serializedType == "double?") {
      return "(${variable} as num${numSuffix})${dot}toDouble()";
    }

    var result = "${variable} as ${serializedType}";

    if (type is GLListType ||
        grammar.isProjectableType(type.token) ||
        grammar.isEnum(type.token)) {
      return "(${result})";
    }

    return result;
  }

  String callFromJson(String variable, GLField field, GLType type, int index) {
    String fromJsonCall = castDynamicToType(variable, type);
    if (type.isList) {
      String varName = "e${index}";
      var inlneCallToJson =
          callFromJson(varName, field, type.inlineType, index + 1);
      return DartCodeGenUtils.mapToList(
          receiver: fromJsonCall, param: varName, body: inlneCallToJson, nullable: type.nullable);
    }
    return fromJsonCall;
  }

  String callToJson(GLField field, GLType type, int index) {
    var fieldType = field.type.inlineType;
    String toJsonCall;
    String dot = type.nullable ? "?." : ".";
    //check if enum
    if (grammar.isProjectableType(fieldType.token) ||
        grammar.isEnum(fieldType.token)) {
      toJsonCall = '${dot}toJson()';
    } else {
      toJsonCall = '';
    }
    if (type.isList) {
      String varName = "e${index}";
      var inlneCallToJson = callToJson(field, type.inlineType, index + 1);
      return DartCodeGenUtils.mapToList(
          receiver: '', param: varName, body: '$varName$inlneCallToJson', nullable: type.nullable);
    }
    return toJsonCall;
  }

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
        statements: [
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

  String serializeInterface(GLInterfaceDefinition interface) {
    final codeName = interface.codeName;
    final interfaces = interface.interfaces;
    final fields = interface.getSerializableFields(grammar.mode);
    var buffer = StringBuffer();
    var decorators = serializeDecorators(interface.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    buffer.write("abstract class $codeName ");
    if (interfaces.isNotEmpty) {
      buffer.write("extends ${interfaces.map((e) => resolveCodeName(e.tokenInfo.token)).join(", ")} ");
    }
    buffer.writeln("{");
    for (var field in fields) {
      var fieldDecorators = serializeDecorators(field.getDirectives());
      if (fieldDecorators.isNotEmpty) {
        buffer.writeln(fieldDecorators.trim().ident());
      }
      final declaration = interface.fieldAsMethods
          ? serializeMethodDeclaration(field)
          : serializeGetterDeclaration(field);
      buffer.writeln("$declaration;".ident());
    }

    if (!shouldSkipJsonMethods(interface)) {
      buffer.writeln(_serializeToJsonForInterface(codeName).ident());
      final serialisableImplemenations = interface.getSerializableImplementations(mode);
      if (serialisableImplemenations.isNotEmpty) {
        buffer.writeln(
            _serializeFromJsonForInterface(codeName, serialisableImplemenations)
                .ident());
      }
    }

    buffer.writeln("}");
    return buffer.toString();
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
    return """import '$import';""";
  }

  @override
  String serializeGlClass(GLClassModel theClass,
      {bool withImports = true}) {
    if (!withImports || theClass.importDepencies.isEmpty) {
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
