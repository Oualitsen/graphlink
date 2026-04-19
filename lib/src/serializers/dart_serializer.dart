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
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/ui/flutter/gl_type_view.dart';

class DartSerializer extends GLSerializer {
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
  String doSerializeEnumDefinition(GLEnumDefinition def) {
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
  String doSerializeEnumValue(GLEnumValue value) {
    var decorators = serializeDecorators(value.getDirectives(), joiner: " ");
    if (decorators.isEmpty) {
      return value.value.token;
    } else {
      return "$decorators ${value.value.token}";
    }
  }

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField) {
    final type = def.type;
    final name = def.name;
    final forceNullable = isTypeField && (def.hasInculeOrSkipDiretives || forceFieldNullable);
    final builder = StringBuffer(serializeDecorators(def.getDirectives()));
    if (immutable) {
      builder.write("final ");
    } else {
      builder.write(" ");
    }
    builder.write("${serializeType(type, forceNullable)} $name;");
    return builder.toString();
  }

  @override
  String serializeType(GLType def, bool forceNullable, [bool _ = false]) {
    String postfix = "";
    if (forceNullable || def.nullable) {
      postfix = "?";
    }
    if (def is GLListType) {
      return "List<${serializeType(def.inlineType, false)}>$postfix";
    }
    final token = def.token;
    var dartTpe = getTypeNameFromGQExternal(token) ?? token;
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
        codeGenUtils.createClass(className: def.token, statements: [
      ...fields.map((e) => serializeField(e, true, false)),
      codeGenUtils.createMethod(
          methodName: def.token,
          namedArguments: true,
          arguments: fields.map((e) => toConstructorDeclaration(e)).toList()),
      if (generateJsonMethods) ...[
        generateToJson(fields),
        generateFromJson(fields, def.token)
      ],
      ...mappingMethods,
    ]);

    buffer.writeln(inputClass);
    return buffer.toString();
  }

  @override
  String generateToMethod(
      GLInputDefinition def, String targetType, MappingPlan plan) {
    final params = [
      ...plan.requiredParams.map(
        (f) =>
            'required ${serializeType(f.targetField.type, false)} ${f.targetField.name.token}',
      ),
      ...plan.defaultParams.map(
        (f) =>
            'required ${serializeType(f.targetField.type, false)} default${f.targetField.name.token.firstUp}',
      ),
    ];

    final assignments = [
      ...plan.autoMapped.map((f) {
        final suffix =
            _callToMapping(f.sourceField!.type, f.targetField.type, 0);
        return '${f.targetField.name.token}: ${f.sourceField!.name.token}$suffix';
      }),
      ...plan.defaultParams.map(
        (f) =>
            '${f.targetField.name.token}: ${f.sourceField!.name.token} ?? default${f.targetField.name.token.firstUp}',
      ),
      ...plan.requiredParams.map(
        (f) => '${f.targetField.name.token}: ${f.targetField.name.token}',
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
      GLInputDefinition def, String targetType, MappingPlan plan) {
    final mapped = [...plan.autoMapped, ...plan.defaultParams];

    // Fields where the target has a nullable element at some list depth but the
    // input has a non-null element — cannot auto-map safely; become required params.
    final elementMismatch = mapped
        .where((f) => _hasElementNullabilityMismatch(f.sourceField!.type, f.targetField.type))
        .toList();
    final autoMappable = mapped
        .where((f) => !_hasElementNullabilityMismatch(f.sourceField!.type, f.targetField.type))
        .toList();

    final mappedAssignments = autoMappable.map((f) {
      final variable = '${targetType.firstLow}.${f.targetField.name.token}';
      var expr = _callFromMapping(
          variable, f.sourceField!.type.firstType.token, f.targetField.type, 0);
      // target type field is nullable but input field is non-null list → use caller-supplied default
      if (f.targetField.type.nullable &&
          !f.sourceField!.type.nullable &&
          f.sourceField!.type.isList) {
        expr = '$expr ?? default${f.sourceField!.name.token.firstUp}';
      }
      return '${f.sourceField!.name.token}: $expr';
    });
    final nullableListDefaultParams = autoMappable
        .where((f) =>
            f.targetField.type.nullable &&
            !f.sourceField!.type.nullable &&
            f.sourceField!.type.isList)
        .map((f) =>
            '${serializeType(f.sourceField!.type, false)} default${f.sourceField!.name.token.firstUp} = const []');
    final elementMismatchParams = elementMismatch.map(
      (f) => 'required ${serializeType(f.sourceField!.type, false)} ${f.sourceField!.name.token}',
    );
    final elementMismatchAssignments = elementMismatch.map(
      (f) => '${f.sourceField!.name.token}: ${f.sourceField!.name.token}',
    );
    final inputOnlyParams = plan.inputOnlyFields.map(
      (f) =>
          '${f.type.nullable ? '' : 'required '}${serializeType(f.type, false)} ${f.name.token}',
    );
    final inputOnlyAssignments = plan.inputOnlyFields.map(
      (f) => '${f.name.token}: ${f.name.token}',
    );

    return codeGenUtils.createMethod(
      returnType: 'static ${def.token}',
      methodName: 'from${targetType.firstUp}',
      namedArguments: true,
      arguments: [
        'required $targetType ${targetType.firstLow}',
        ...nullableListDefaultParams,
        ...elementMismatchParams,
        ...inputOnlyParams,
      ],
      statements: [
        'return ${def.token}(${[
          ...mappedAssignments,
          ...elementMismatchAssignments,
          ...inputOnlyAssignments
        ].join(', ')});',
      ],
    );
  }

  /// Returns true if [targetType] contains a nullable element at any list depth
  /// where the corresponding [sourceType] element is non-null, making a safe
  /// fromXxx() lambda call impossible.
  bool _hasElementNullabilityMismatch(GLType sourceType, GLType targetType) {
    if (!sourceType.isList || !targetType.isList) return false;
    final sourceElem = sourceType.inlineType;
    final targetElem = targetType.inlineType;
    if (targetElem.nullable && !sourceElem.nullable) return true;
    return _hasElementNullabilityMismatch(sourceElem, targetElem);
  }

  /// Returns a suffix to append to a source field value for toXxx() assignments.
  /// e.g. '' for direct copy, '.map((e0) => e0.toTag()).toList()' for mapped lists.
  String _callToMapping(GLType sourceType, GLType targetType, int index) {
    final dot = sourceType.nullable ? '?.' : '.';
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) {
        return '${dot}toList()'; // same element type — copy the list
      }
      final varName = 'e$index';
      final inner = _callToMapping(
          sourceType.inlineType, targetType.inlineType, index + 1);
      return '${dot}map(($varName) => $varName$inner).toList()';
    }
    final sourceInput = grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      return '${dot}to${targetType.token.firstUp}()';
    }
    return ''; // same type — direct copy
  }

  /// Returns the full expression for a fromXxx() field assignment.
  /// e.g. 'order.tags.map((e0) => TagInput.fromTag(e0)).toList()'
  String _callFromMapping(
      String variable, String sourceElemToken, GLType targetType, int index) {
    final dot = targetType.nullable ? '?.' : '.';
    if (targetType.isList) {
      if (sourceElemToken == targetType.firstType.token) {
        return '$variable${dot}toList()'; // same element type — copy the list
      }
      final varName = 'e$index';
      final inner = _callFromMapping(
          varName, sourceElemToken, targetType.inlineType, index + 1);
      return '$variable${dot}map(($varName) => $inner).toList()';
    }
    final sourceInput = grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      return '$sourceElemToken.from${targetType.token.firstUp}(${targetType.token.firstLow}: $variable)';
    }
    return variable; // same type — direct copy
  }

  String toConstructorDeclaration(GLField field) {
    if (grammar.nullableFieldsRequired || !field.type.nullable) {
      return "required this.${field.name}";
    } else {
      return "this.${field.name}";
    }
  }

  String generateFromJson(List<GLField> fields, String token) {
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

  String generateToJson(List<GLField> fields) {
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

  String fieldToJson(GLField field) {
    var buffer = StringBuffer("'${field.name}': ");
    var toJosnCall = callToJson(field, field.type, 0);
    buffer.write("${field.name}${toJosnCall}");
    return buffer.toString();
  }

  String fieldFromJson(GLField field) {
    var buffer = StringBuffer('${field.name}: ');
    var toJosnCall =
        callFromJson("json['${field.name}']", field, field.type, 0);
    buffer.write(toJosnCall);
    return buffer.toString();
  }

  String castDynamicToType(String variable, GLType type) {
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

    if (type is GLListType ||
        grammar.isProjectableType(type.token) ||
        grammar.isEnum(type.token)) {
      return "(${result})";
    }

    return result;
  }

  String callFromJson(String variable, GLField field, GLType type, int index) {
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
      return "${dot}map((${varName}) => ${varName}${inlneCallToJson}).toList()";
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
    final token = def.token;
    final implementations = def is GLInterfaceDefinition
        ? def.implementations
        : <GLTypeDefinition>{};

    final interfaceNames = def.interfaceNames.map((e) => e.token).toSet();
    interfaceNames.addAll(implementations.map((e) => e.token));
    var decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    final fields = def.getSerializableFields(grammar.mode);
    var equalsHascodeCode = generateEqualsAndHashCode(def);
    buffer.writeln(codeGenUtils.createClass(
      className: token,
      baseClassNames: interfaceNames.toList(),
      statements: [
        ...fields.map((e) => serializeField(e, true, true)),
        codeGenUtils.createMethod(
            methodName: token,
            namedArguments: false,
            arguments: [serializeContructorArgs(fields)]),
        if (equalsHascodeCode.isNotEmpty) equalsHascodeCode,
        if (generateJsonMethods) ...[
          generateToJson(fields),
          generateFromJson(fields, def.token)
        ]
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
                  statement: 'return ${st.tokenInfo.token}.fromJson(json);'))
            ],
            defaultStatement:
                'throw ArgumentError("Invalid type \$typename. \$typename does not implement $token or not defined");',
          ),
        ]);
  }

  String serializeInterface(GLInterfaceDefinition interface) {
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

  String serializeGetterDeclaration(GLField field) {
    return """${serializeType(field.type, false)} get ${field.name}""";
  }

  @override
  String getFileNameFor(GLToken token) {
    return "${token.token.toSnakeCase()}.dart";
  }

  @override
  String serializeImportToken(GLToken token, String importPrefix) {
    String? init;
    if (token is GLEnumDefinition) {
      init = "enums/${getFileNameFor(token)}";
    } else if (token is GLInterfaceDefinition) {
      init = "interfaces/${getFileNameFor(token)}";
    } else if (token is GLTypeDefinition) {
      init = "types/${getFileNameFor(token)}";
    } else if (token is GLInputDefinition) {
      init = "inputs/${getFileNameFor(token)}";
    } else if (token is GLTypeView) {
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

  @override
  String serializeGlClass(GLClassModel theClass,
      {bool withImports = true, required String importPrefix}) {
    if (!withImports || theClass.importDepencies.isEmpty) {
      return super.serializeGlClass(theClass, withImports: withImports, importPrefix: importPrefix);
    }
    final tokenImports = theClass.importDepencies
        .map((dep) => serializeImportToken(dep, importPrefix))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final simpleImports = theClass.imports.map((imp) => serializeImport(imp)).toList();
    final merged = GLClassModel(
      imports: {...tokenImports, ...simpleImports}.toList(),
      body: theClass.body,
    );
    return super.serializeGlClass(merged, withImports: withImports, importPrefix: importPrefix);
  }
}
