import 'package:retrofit_graphql/src/code_gen_utils.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_interface_definition.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_token_with_fields.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/serializers/annotation_serializer.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';
import 'package:retrofit_graphql/src/ui/flutter/gq_type_view.dart';

class DartSerializer extends GqSerializer {
  final codeGenUtils = DartCodeGenUtils();
  @override
  final bool generateJsonMethods;
  DartSerializer(super.grammar, {this.generateJsonMethods = true}) {
    _initAnnotations();
  }

  void _initAnnotations() {
    grammar.handleAnnotations(AnnotationSerializer.serializeAnnotation);
  }

  @override
  String doSerializeEnumDefinition(GQEnumDefinition def) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    buffer.writeln("enum ${def.tokenInfo} {");
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
                    caseValue: val.token, statement: 'return "${val.token}";'))
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
            returnType: 'static ${def.token}',
            statements: [
              codeGenUtils.switchStatement(
                  expression: 'value',
                  cases: [
                    ...def.values.map((val) => DartCaseStatement(
                        caseValue: '"${val.token}"',
                        statement: 'return ${val.token};'))
                  ],
                  defaultStatement:
                      'throw ArgumentError("Invalid ${def.token}: \$value");')
            ])
        .ident());
    buffer.writeln("}");
    return buffer.toString();
  }

  @override
  String doSerializeEnumValue(GQEnumValue value) {
    var decorators = serializeDecorators(value.getDirectives(), joiner: " ");
    if (decorators.isEmpty) {
      return value.value.token;
    } else {
      return "$decorators ${value.value.token}";
    }
  }

  @override
  String doSerializeField(GQField def) {
    final type = def.type;
    final name = def.name;
    final hasInculeOrSkipDiretives = def.hasInculeOrSkipDiretives;
    return "${serializeDecorators(def.getDirectives())}final ${serializeType(type, hasInculeOrSkipDiretives)} $name;";
  }

  @override
  String serializeType(GQType def, bool forceNullable, [bool _ = false]) {
    String postfix = "";
    if (forceNullable || def.nullable) {
      postfix = "?";
    }
    if (def is GQListType) {
      return "List<${serializeType(def.inlineType, false)}>$postfix";
    }
    final token = def.token;
    var dartTpe = getTypeNameFromGQExternal(token) ?? token;
    return "$dartTpe$postfix";
  }

  @override
  String doSerializeInputDefinition(GQInputDefinition def) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    var inputClass =
        codeGenUtils.createClass(className: def.token, statements: [
      ...def.getSerializableFields(grammar.mode).map((e) => serializeField(e)),
      codeGenUtils.createMethod(
          methodName: def.token,
          namedArguments: true,
          arguments: def
              .getSerializableFields(grammar.mode)
              .map((e) => toConstructorDeclaration(e))
              .map((e) => "${e},")
              .toList()),
      if (generateJsonMethods) ...[
        generateToJson(def.getSerializableFields(mode)),
        generateFromJson(def.getSerializableFields(mode), def.token)
      ]
    ]);

    buffer.writeln(inputClass);
    return buffer.toString();
  }

  String toConstructorDeclaration(GQField field) {
    if (grammar.nullableFieldsRequired || !field.type.nullable) {
      return "required this.${field.name}";
    } else {
      return "this.${field.name}";
    }
  }

  String generateFromJson(List<GQField> fields, String token) {
    if (!generateJsonMethods) {
      return "";
    }
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

  String generateToJson(List<GQField> fields) {
    var buffer = StringBuffer();

    buffer.writeln(codeGenUtils.method(
        returnType: 'Map<String, dynamic>',
        methodName: 'toJson',
        statements: [
          "return {",
          ...fields
              .map((field) => fieldToJson(field).ident())
              .map((e) => "${e},"),
          '};'
        ]));
    return buffer.toString();
  }

  String fieldToJson(GQField field) {
    var buffer = StringBuffer("'${field.name}': ");
    var toJosnCall = callToJson(field, field.type, 0);
    buffer.write("${field.name}${toJosnCall}");
    return buffer.toString();
  }

  String fieldFromJson(GQField field) {
    var buffer = StringBuffer('${field.name}: ');
    var toJosnCall =
        callFromJson("json['${field.name}']", field, field.type, 0);
    buffer.write(toJosnCall);
    return buffer.toString();
  }

  String castDynamicToType(String variable, GQType type) {
    String dot = type.nullable ? "?." : ".";
    String serializedType = serializeType(type, false);
    String numSuffix = type.nullable ? "?" : "";

    if (type.isList) {
      return "(${variable} as List<dynamic>${numSuffix})";
    }
    if (grammar.isEnum(type.token)) {
      var enumFromJson = "${type.token}.fromJson(${variable} as String)";
      if (type.nullable) {
        return "${variable} == null ? null : ${enumFromJson}";
      } else {
        return enumFromJson;
      }
    }
    if (grammar.isProjectableType(type.token)) {
      var typeFromJson =
          "${type.token}.fromJson(${variable} as Map<String, dynamic>)";
      if (type.nullable) {
        return "${variable} == null ? null : ${typeFromJson}";
      } else {
        return typeFromJson;
      }
    }

    if (serializedType == "double" || serializedType == "double?") {
      return "(${variable} as num${numSuffix})${dot}toDouble()";
    }

    var result = "${variable} as ${serializedType}";

    if (type is GQListType ||
        grammar.isProjectableType(type.token) ||
        grammar.isEnum(type.token)) {
      return "(${result})";
    }

    return result;
  }

  String callFromJson(String variable, GQField field, GQType type, int index) {
    String fromJsonCall;
    String dot = type.nullable ? "?." : ".";
    fromJsonCall = castDynamicToType(variable, type);
    if (type.isList) {
      String varName = "e${index}";
      var inlneCallToJson =
          callFromJson(varName, field, type.inlineType, index + 1);
      return "${fromJsonCall}${dot}map((${varName}) => ${inlneCallToJson}).toList()";
    }
    return fromJsonCall;
  }

  String callToJson(GQField field, GQType type, int index) {
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
      return "${dot}map((${varName}) => ${varName}${inlneCallToJson}).toList()";
    }
    return toJsonCall;
  }

  @override
  String doSerializeTypeDefinition(GQTypeDefinition def) {
    if (def is GQInterfaceDefinition) {
      return serializeInterface(def);
    } else {
      return _doSerializeTypeDefinition(def);
    }
  }

  String _doSerializeTypeDefinition(GQTypeDefinition def) {
    final token = def.token;
    final implementations = def is GQInterfaceDefinition
        ? def.implementations
        : <GQTypeDefinition>{};

    final interfaceNames = def.interfaceNames.map((e) => e.token).toSet();
    interfaceNames.addAll(implementations.map((e) => e.token));
    var decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    var equalsHascodeCode = generateEqualsAndHashCode(def);
    buffer.writeln(codeGenUtils.createClass(
      className: token,
      baseClassNames: interfaceNames.toList(),
      statements: [
        ...def
            .getSerializableFields(grammar.mode)
            .map((e) => serializeField(e)),
        codeGenUtils.createMethod(
            methodName: token,
            namedArguments: false,
            arguments: [serializeContructorArgs(def, grammar)]),
        if (equalsHascodeCode.isNotEmpty) equalsHascodeCode,
        if (generateJsonMethods) ...[
          generateToJson(def.getSerializableFields(mode)),
          generateFromJson(def.getSerializableFields(mode), def.token)
        ]
      ],
    ));
    return buffer.toString();
  }

  String generateEqualsAndHashCode(GQTypeDefinition def) {
    var fieldsToInclude = def.getIdentityFields(grammar);
    if (fieldsToInclude.isNotEmpty) {
      return equalsHascodeCode(def, fieldsToInclude);
    }
    return "";
  }

  String equalsHascodeCode(GQTypeDefinition def, Set<String> fields) {
    final token = def.tokenInfo;
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

  String serializeContructorArgs(GQTypeDefinition def, GQGrammar grammar) {
    var fields = def.getSerializableFields(grammar.mode);
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
    Set<GQTypeDefinition> implementations,
  ) {
    return codeGenUtils
        .createMethod(returnType: 'static ${token}', methodName: 'fromJson', namedArguments: false, arguments: [
      'Map<String, dynamic> json'
    ], statements: [
      "var typename = json['__typename'] as String;",
      codeGenUtils.switchStatement(
        expression: 'typename',
        cases: [
          ...implementations.map((st) => DartCaseStatement(
              caseValue:
                  "'${st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token}'",
              statement: 'return ${st.tokenInfo.token}.fromJson(json);'))
        ],
        defaultStatement:
            'throw ArgumentError("Invalid type \$typename. \$typename does not implement $token or not defined");',
      ),
    ]);
  }


  String serializeInterface(GQInterfaceDefinition interface) {
    final token = interface.tokenInfo.token;
    final interfaces = interface.interfaces;
    final fields = interface.getSerializableFields(grammar.mode);
    var buffer = StringBuffer();
    var decorators = serializeDecorators(interface.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    buffer.write("abstract class $token ");
    if (interfaces.isNotEmpty) {
      buffer.write("extends ${interfaces.map((e) => e.tokenInfo).join(", ")} ");
    }
    buffer.writeln("{");
    for (var field in fields) {
      var fieldDecorators = serializeDecorators(field.getDirectives());
      if (fieldDecorators.isNotEmpty) {
        buffer.writeln(fieldDecorators.trim().ident());
      }
      buffer.writeln("${serializeGetterDeclaration(field)};".ident());
    }

    if (generateJsonMethods) {
      buffer.writeln(_serializeToJsonForInterface(token).ident());
    }
    if (generateJsonMethods && interface.implementations.isNotEmpty) {
      buffer.writeln(
          _serializeFromJsonForInterface(token, interface.implementations)
              .ident());
    }

    buffer.writeln("}");
    return buffer.toString();
  }

  String serializeGetterDeclaration(GQField field) {
    return """${serializeType(field.type, false)} get ${field.name}""";
  }

  @override
  String getFileNameFor(GQToken token) {
    return "${token.token.toSnakeCase()}.dart";
  }

  @override
  String serializeImportToken(GQToken token, String importPrefix) {
    String? init;
    if (token is GQEnumDefinition) {
      init = "enums/${getFileNameFor(token)}";
    } else if (token is GQInterfaceDefinition) {
      init = "interfaces/${getFileNameFor(token)}";
    } else if (token is GQTypeDefinition) {
      init = "types/${getFileNameFor(token)}";
    } else if (token is GQInputDefinition) {
      init = "inputs/${getFileNameFor(token)}";
    } else if (token is GQTypeView) {
      init = "widgets/${getFileNameFor(token)}";
    }

    return "import '${importPrefix}/${init}';";
  }

  @override
  String serializeImport(String import) {
    if (import == importList) {
      return "";
    }
    return """import '$import';""";
  }
}
