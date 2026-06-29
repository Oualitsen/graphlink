import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/jvm_spring_controller_serializer_base.dart';
import 'package:graphlink/src/utils.dart';

class JavaSpringControllerSerializer extends JvmSpringControllerSerializerBase {
  final JavaSerializer serializer;
  @override
  final JavaCodeGenUtils codeGenUtils = JavaCodeGenUtils();

  JavaSpringControllerSerializer({
    required GLParser grammar,
    required this.serializer,
    required bool reactive,
    required bool injectDataFetching,
    required bool useSpringSecurity,
    required bool generateSchema,
  }) : super(
          grammar: grammar,
          reactive: reactive,
          injectDataFetching: injectDataFetching,
          useSpringSecurity: useSpringSecurity,
          generateSchema: generateSchema,
        );

  // ── Controller ─────────────────────────────────────────────────────────────

  @override
  String serializeController(GLController ctrl) {
    var body = _serializeControllerBody(ctrl);
    return serializer.serializeWithImport(ctrl, body);
  }

  String _serializeControllerBody(GLController ctrl) {
    final controllerName = ctrl.token;
    final serviceInstanceName = ctrl.serviceName.firstLow;
    if (!reactive) {
      ctrl.addImport(JavaImports.completableFuture);
    }
    if (ctrl.fields.isNotEmpty &&
        (injectDataFetching ||
            ctrl.fields.any((f) => f.hasDirective(glReturnsProjection)))) {
      ctrl.addImport(SpringImports.gqlDataFetchingEnvironment);
    }
    var decorators = serializer.serializeDecorators(ctrl.getDirectives()).trim();

    var buffer = StringBuffer();
    buffer.writeln(decorators);
    buffer.writeln(codeGenUtils.createClass(className: controllerName, statements: [
      if (grammar.services.containsKey(ctrl.serviceName))
        'private final ${ctrl.serviceName} $serviceInstanceName;',
      '',
      serializer.generateContructor(
          controllerName,
          [
            if (grammar.services.containsKey(ctrl.serviceName))
              GLField(
                  name: serviceInstanceName.toToken(),
                  type: GLType(ctrl.serviceName.toToken(), false),
                  arguments: [],
                  directives: [])
          ],
          "public",
          ctrl),
      '',
      ...ctrl.fields.map((field) => serializehandlerMethod(
          ctrl.getTypeByFieldName(field.name.token)!,
          field,
          serviceInstanceName,
          ctrl,
          qualifier: "public")),
      '',
      ...ctrl.mappings.map((m) => serializeMappingMethod(m, serviceInstanceName, ctrl))
    ]));

    return buffer.toString();
  }

  @override
  String serializehandlerMethod(GLQueryType type, GLField method,
      String serviceInstanceName, GLToken context,
      {String? qualifier}) {
    final decorators =
        serializer.serializeDecorators(method.getDirectives()).trim();
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    var args = method.arguments.map((arg) {
      final argType = resolveArgType(arg, context);
      var argDecorators =
          serializer.serializeDecorators(arg.getDirectives()).trim();
      if (argDecorators.isNotEmpty) {
        return "$argDecorators $argType ${arg.codeName}";
      }
      return "$argType ${arg.codeName}";
    }).toList();

    final injectFetchingEnv =
        injectDataFetching || method.hasDirective(glReturnsProjection);
    if (injectFetchingEnv) {
      args.add("DataFetchingEnvironment dataFetchingEnvironment");
    }
    var serviceArgs =
        method.arguments.map((arg) => arg.codeName).toList();
    if (injectFetchingEnv) {
      serviceArgs.add('dataFetchingEnvironment');
    }
    final serviceCall =
        '$serviceInstanceName.${method.codeName}(${serviceArgs.join(", ")})';
    final String returnType;
    final List<String> statements;

    final validationMethodCall = method.getDirectiveByName(glValidate) != null
        ? '$serviceInstanceName.${GLService.getValidationMethodName(method.name.token)}(${serviceArgs.join(", ")})'
        : null;
    final validationCall =
        validationMethodCall != null ? '$validationMethodCall;' : null;

    if (type == GLQueryType.subscription) {
      returnType = serializer.serializeTypeReactive(
          context: context,
          glType: createListTypeOnSubscription(
              getServiceReturnType(method.type), type),
          reactive: true);
      statements = [
        if (validationCall != null) validationCall,
        "return $serviceCall;",
      ];
    } else if (reactive) {
      returnType = serializer.serializeTypeReactive(
          context: context,
          glType: getServiceReturnType(method.type),
          reactive: true);
      statements = [
        validationMethodCall != null
            ? "return $validationMethodCall.then($serviceCall);"
            : "return $serviceCall;",
      ];
    } else {
      context.addImport(JavaImports.completableFuture);
      final baseReturnType = serializer.serializeTypeReactive(
          context: context,
          glType: getServiceReturnType(method.type),
          reactive: false);
      final returnTypeIsVoid = baseReturnType == "void";
      returnType =
          "CompletableFuture<${convertPrimitiveToBoxed(baseReturnType)}>";
      statements = _wrapInCompletableFuture([
        if (validationCall != null) validationCall,
        serviceCall,
      ], returnTypeIsVoid, context);
    }

    final fullReturnType =
        qualifier != null ? "$qualifier $returnType" : returnType;

    buffer.writeln(codeGenUtils.createMethod(
        returnType: fullReturnType,
        methodName: method.codeName,
        arguments: args,
        statements: statements));

    return buffer.toString();
  }

  List<String> _wrapInCompletableFuture(
      List<String> innerStatements, bool returnVoid, GLToken context) {
    final method = returnVoid ? 'runAsync' : 'supplyAsync';
    final preceding = innerStatements.sublist(0, innerStatements.length - 1);
    final last = innerStatements.last;
    final bodyStatements = [
      ...preceding,
      returnVoid ? "$last;" : "return $last;",
    ];

    if (!useSpringSecurity) {
      final lambdaBody = bodyStatements.length == 1
          ? innerStatements.first
          : codeGenUtils.block(bodyStatements);
      return ["return CompletableFuture.$method(() -> $lambdaBody);"];
    }

    context.addImport(JavaImports.securityContext);
    context.addImport(JavaImports.securityContextHolder);
    final lambdaBody = codeGenUtils.block([
      "SecurityContextHolder.setContext(securityContext);",
      codeGenUtils.tryCatchFinally(
        tryStatements: bodyStatements,
        finallyStatements: ["SecurityContextHolder.clearContext();"],
      ),
    ]);
    return [
      "SecurityContext securityContext = SecurityContextHolder.getContext();",
      "return CompletableFuture.$method(() -> $lambdaBody);",
    ];
  }

  // ── Mapping methods ────────────────────────────────────────────────────────

  @override
  String serializeMappingMethod(
      GLSchemaMapping mapping, String serviceInstanceName, GLToken context) {
    if (mapping.forwarded) {
      return serializeForwardedMapping(mapping, context);
    }
    if (mapping.forbid && generateSchema) {
      return "";
    }
    if (mapping.forbid) {
      context.addImport(SpringImports.gqlGraphQLException);
      return '${serializeControllerMethodHeader(mapping, context)} ${codeGenUtils.block([
            '''throw new GraphQLException("Access denied to field '${mapping.type.tokenInfo}.${mapping.field.name}'");'''
          ])}';
    }

    if (mapping.identity) {
      return serializeIdentityMapping(mapping, context);
    }

    final statement =
        StringBuffer('$serviceInstanceName.${mapping.key}(value');
    for (var arg in mapping.field.arguments) {
      statement.write(', ${arg.codeName}');
    }
    if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
      statement.write(', dataFetchingEnvironment');
    }
    statement.write(')');
    final bodyStatements = reactive
        ? ['return ${statement};']
        : _wrapInCompletableFuture([statement.toString()], false, context);
    return '${serializeControllerMethodHeader(mapping, context)} ${codeGenUtils.block(bodyStatements)}';
  }

  @override
  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    var annotation = getAnnotationForMapping(mapping, context);
    if (annotation.isNotEmpty) {
      buffer.writeln(annotation);
    }
    final type = serializer.serializeTypeReactive(
        context: context, glType: mapping.field.type, reactive: false);
    final boxedType = convertPrimitiveToBoxed(type);

    final String returnType;
    final String statement;
    if (reactive) {
      if (mapping.isBatch) {
        context.addImport(JavaImports.flux);
        returnType = JavaCodeGenUtils.fluxOf(grammar, type);
        statement = "return Flux.fromIterable(value);";
      } else {
        context.addImport(JavaImports.mono);
        returnType = JavaCodeGenUtils.monoOf(grammar, type);
        statement = "return Mono.just(value);";
      }
    } else {
      if (mapping.isBatch) {
        returnType = JavaCodeGenUtils.listOf(grammar, type);
      } else {
        returnType = type;
      }
      statement = "return value;";
    }

    buffer.writeln(
      codeGenUtils.createMethod(
          returnType: 'public $returnType',
          methodName: mapping.key,
          arguments: [
            mapping.isBatch ? 'List<$boxedType> value' : '$boxedType value'
          ],
          statements: [statement]),
    );

    return buffer.toString();
  }

  String _getterMethodName(String fieldName, String fieldType) {
    if (serializer.typesAsRecords) return fieldName;
    final prefix = fieldType == 'boolean' ? 'is' : 'get';
    return '$prefix${fieldName.firstUp}';
  }

  @override
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.writeln(getAnnotationForMapping(mapping, context));

    final fieldName = mapping.field.name.token;
    final fieldType = serializer.serializeTypeReactive(
        context: context, glType: mapping.field.type, reactive: false);
    final argType = serializer.serializeType(
        getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);

    final getterCall = 'value.${_getterMethodName(fieldName, fieldType)}()';

    final String returnType;
    final String statement;
    if (reactive) {
      context.addImport(JavaImports.mono);
      returnType = JavaCodeGenUtils.monoOf(grammar, fieldType);
      statement = 'return Mono.just($getterCall);';
    } else {
      returnType = fieldType;
      statement = 'return $getterCall;';
    }

    buffer.writeln(codeGenUtils.createMethod(
      returnType: 'public $returnType',
      methodName: mapping.key,
      arguments: ['$argType value'],
      statements: [statement],
    ));

    return buffer.toString();
  }

  String _getReturnType(GLSchemaMapping mapping, GLToken context) {
    if (mapping.isBatch) {
      var keyType = serializer.serializeType(
          getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
      if (keyType == "Object") {
        keyType = "?";
      }
      context.addImport(JavaImports.map);
      return JavaCodeGenUtils.mapOf(
        grammar,
        keyType,
        serializer.serializeType(mapping.field.type, false),
      );
    } else {
      return serializer.serializeTypeReactive(
          context: context, glType: mapping.field.type, reactive: false);
    }
  }

  String _getMappingArgument(GLSchemaMapping mapping, GLToken context) {
    var argType = serializer.serializeType(
        getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
    if (mapping.isBatch) {
      context.addImport(importList);
      return "${JavaCodeGenUtils.listOf(grammar, argType)} value";
    } else {
      return "${argType} value";
    }
  }

  @override
  String serializeControllerMethodHeader(
      GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.writeln(getAnnotationForMapping(mapping, context));
    buffer.write("public ");

    final returnType = _getReturnType(mapping, context);
    if (reactive) {
      context.addImport(JavaImports.mono);
      buffer.write(
          "${JavaCodeGenUtils.monoOf(grammar, returnType)} ${mapping.key}(${_getMappingArgument(mapping, context)}");
    } else {
      context.addImport(JavaImports.completableFuture);
      buffer.write(
          "CompletableFuture<${convertPrimitiveToBoxed(returnType)}> ${mapping.key}(${_getMappingArgument(mapping, context)}");
    }
    for (var arg in mapping.field.arguments) {
      final argType = resolveArgType(arg, context);
      context.addImport(SpringImports.gqlArgument);
      buffer.write(', ${_argumentAnnotation(arg)} $argType ${arg.codeName}');
    }
    if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      buffer.write(', DataFetchingEnvironment dataFetchingEnvironment)');
    } else {
      buffer.write(')');
    }
    return buffer.toString();
  }

  // ── Service declarations ───────────────────────────────────────────────────

  @override
  String serializeMethodDeclaration(
      GLField method, GLQueryType type, GLToken context,
      {String? argPrefix}) {
    GLType returnType;
    if (method.getDirectiveByName(glValidate)?.generated == true) {
      returnType = GLType('void'.toToken(), false);
    } else {
      returnType = getServiceReturnType(method.type);
    }
    var result =
        "${serializer.serializeTypeReactive(context: context, glType: createListTypeOnSubscription(returnType, type), reactive: reactive || type == GLQueryType.subscription)} ${method.codeName}(${serializeArgs(method.arguments, context, argPrefix)}";
    if (injectDataFetching || method.hasDirective(glReturnsProjection)) {
      var inject = "DataFetchingEnvironment dataFetchingEnvironment";
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      if (method.arguments.isNotEmpty) {
        result = "$result, $inject";
      } else {
        result = "$result$inject";
      }
    }
    return "${result})";
  }

  @override
  String serializeServiceMappingImplMethodHeader(
      GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();

    final returnType = _getReturnType(mapping, context);
    if (reactive) {
      context.addImport(JavaImports.mono);
      buffer.write(
          "${JavaCodeGenUtils.monoOf(grammar, returnType)} ${mapping.key}(${_getMappingArgument(mapping, context)}");
    } else {
      buffer.write(
          "$returnType ${mapping.key}(${_getMappingArgument(mapping, context)}");
    }
    for (var arg in mapping.field.arguments) {
      final argType = resolveArgType(arg, context);
      buffer.write(', $argType ${arg.codeName}');
    }
    if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      buffer.write(', DataFetchingEnvironment dataFetchingEnvironment)');
    } else {
      buffer.write(')');
    }
    return buffer.toString();
  }

  /// `@Argument`, pinned to the wire name when the param was sanitized for a
  /// keyword so Spring still binds the correct GraphQL argument.
  String _argumentAnnotation(GLArgumentDefinition arg) =>
      arg.codeName != arg.bareName
          ? '@Argument(name = "${arg.bareName}")'
          : '@Argument';

  // ── Arg type resolution ────────────────────────────────────────────────────

  @override
  String resolveArgType(GLArgumentDefinition arg, GLToken context) {
    final uploadNames = grammar.uploadScalarNames;
    if (uploadNames.contains(arg.type.firstType.token)) {
      if (reactive) {
        context.addImport(SpringImports.filePart);
        if (arg.type.isList) {
          context.addImport(JavaImports.list);
          return 'List<FilePart>';
        }
        return 'FilePart';
      } else {
        context.addImport(SpringImports.multipartFile);
        if (arg.type.isList) {
          context.addImport(JavaImports.list);
          return 'List<MultipartFile>';
        }
        return 'MultipartFile';
      }
    }
    return serializer.serializeType(arg.type, false);
  }
}
