import 'dart:io';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_shcema_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/utils.dart';

class SpringServerSerializer {
  final String? defaultRepositoryBase;

  final GLParser grammar;
  final JavaSerializer serializer;
  final bool generateSchema;
  final bool injectDataFetching;
  final bool reactive;
  final codeGenUtils = JavaCodeGenUtils();

  SpringServerSerializer(this.grammar,
      {this.defaultRepositoryBase,
      JavaSerializer? javaSerializer,
      this.generateSchema = false,
      this.injectDataFetching = false,
      this.reactive = false})
      : assert(grammar.mode == CodeGenerationMode.server,
            "Grammar must be in code generation mode = `CodeGenerationMode.server`"),
        serializer = javaSerializer ??
            JavaSerializer(grammar,
                inputsCheckForNulls: true,
                typesCheckForNulls: grammar.mode == CodeGenerationMode.client) {
    _validateFieldArguments();
    _annotateRepositories();
    _annotateControllers();
    _warnIfUploadScalarsPresent();
    grammar.convertAnnotationsToDecorators(
        _getControllerMixins(),
        (val) => AnnotationSerializer.serializeAnnotation(val,
            multiLineString: false));
  }

  void _warnIfUploadScalarsPresent() {
    if (grammar.uploadScalarNames.isEmpty) return;
    final scalars = grammar.uploadScalarNames.join(', ');
    stdout.writeln('''
ℹ  File upload detected — Spring Boot configuration required
   ─────────────────────────────────────────────────────────
   Upload scalar(s) found: $scalars

   1. Multipart support
      Spring for GraphQL does not handle multipart requests out of the box.
      Add the following library to your project:

        https://github.com/nkonev/multipart-spring-graphql

      Follow its README to register the multipart scalar and configure
      the servlet multipart resolver in application.properties:

        spring.servlet.multipart.enabled=true
        spring.servlet.multipart.max-file-size=10MB
        spring.servlet.multipart.max-request-size=10MB

   2. Prevent schema redefinition errors
      The $scalars scalar is declared in your schema file. If GraphLink
      copies that file to the server output (generateSchema: true), the
      library above will also register the scalar — causing a duplicate
      definition error at startup.

      To avoid this, annotate the scalar in your schema with @glSkipOnServer
      so GraphLink omits it from the generated schema copy:

        scalar Upload @glUpload @glSkipOnServer

      Then enable schema copying in your config:

        "generateSchema": true
        "schemaTargetPath": "src/main/resources/graphql/schema.graphqls"
   ─────────────────────────────────────────────────────────
''');
  }

  List<GLDirectivesMixin> _getControllerMixins() {
    var ctrlList = grammar.controllers.values.toList();
    var fields = ctrlList.expand((ctrl) => ctrl.fields);
    var args = fields.expand((e) => e.arguments);
    return [...ctrlList, ...fields, ...args];
  }

  List<String> serializeServices(String importPrefix) {
    return grammar.services.values.map((service) {
      return serializeService(service, importPrefix);
    }).toList();
  }

  void _validateFieldArguments() {
    final rootTypeNames =
        GLQueryType.values.map((e) => grammar.schema.getByQueryType(e)).toSet();
    grammar.types.values
        .where((type) => !rootTypeNames.contains(type.token))
        .forEach((type) {
      for (var field in type.fields) {
        if (field.arguments.isEmpty) continue;
        final skipOnServer = field.getDirectiveByName(glSkipOnServer);
        if (skipOnServer == null) {
          throw ParseException(
            "Field '${field.name}' on type '${type.token}' has arguments but is missing $glSkipOnServer — "
            "add $glSkipOnServer(batch: false) to generate a @SchemaMapping for it",
            info: field.name,
          );
        }
        final batch = skipOnServer.getArgValue(glBatch) as bool?;
        if (batch == true) {
          throw ParseException(
            "Field '${field.name}' on type '${type.token}' has arguments and cannot use @BatchMapping — "
            "change to $glSkipOnServer(batch: false) to generate a @SchemaMapping instead",
            info: field.name,
          );
        }
      }
    });
  }

  void _annotateRepositories() {
    for (var repo in grammar.repositories.values) {
      var dec = GLDirectiveValue.createGqDecorators(
          decorators: ["@Repository"],
          applyOnClient: false,
          import: "org.springframework.stereotype.Repository");
      repo.addDirective(dec);
    }
  }

  void _annotateControllers() {
    for (var ctrl in grammar.controllers.values) {
      ctrl.addDirective(_createControllerDirective());
      for (var method in ctrl.fields) {
        var queryType = ctrl.getTypeByFieldName(method.name.token)!;
        method.addDirective(_createResolverDirective(queryType));
        for (var arg in method.arguments) {
          arg.addDirective(_createArgumentDirective());
        }
      }
    }
  }

  String serializeController(GLController ctrl, String importPrefix) {
    var body = _serializeControllerBody(ctrl, importPrefix);
    return serializer.serializeWithImport(ctrl, importPrefix, body);
  }

  String _serializeControllerBody(GLController ctrl, String importPrefix) {
    final controllerName = ctrl.token;
    final sericeInstanceName = ctrl.serviceName.firstLow;
    if (!reactive) {
      ctrl.addImport(JavaImports.completableFuture);
    }
    if (ctrl.fields.isNotEmpty && injectDataFetching) {
      ctrl.addImport(SpringImports.gqlDataFetchingEnvironment);
    }
    var decorators =
        serializer.serializeDecorators(ctrl.getDirectives()).trim();

    var buffer = StringBuffer();
    buffer.writeln(decorators);
    buffer.writeln(
        codeGenUtils.createClass(className: controllerName, statements: [
          if(grammar.services.containsKey(ctrl.serviceName))
      'private final ${ctrl.serviceName} $sericeInstanceName;',
      '',
      serializer.generateContructor(
          controllerName,
          [
            if(grammar.services.containsKey(ctrl.serviceName))
            GLField(
                name: sericeInstanceName.toToken(),
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
          sericeInstanceName,
          ctrl,
          qualifier: "public")),
      '',
      // get schema mappings by service name
      ...ctrl.mappings
          .map((m) => serializeMappingMethod(m, sericeInstanceName, ctrl))
    ]));

    return buffer.toString();
  }

  String serializehandlerMethod(GLQueryType type, GLField method,
      String sericeInstanceName, GLToken context,
      {String? qualifier}) {
    final decorators =
        serializer.serializeDecorators(method.getDirectives()).trim();
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    var args = method.arguments.map((arg) {
      final argType = _resolveArgType(arg, context);
      var argDecorators =
          serializer.serializeDecorators(arg.getDirectives()).trim();
      if (argDecorators.isNotEmpty) {
        return "$argDecorators $argType ${arg.token}";
      }
      return "$argType ${arg.token}";
    }).toList();

    if (injectDataFetching) {
      args.add("DataFetchingEnvironment dataFetchingEnvironment");
    }
    var serviceArgs =
        method.arguments.map((arg) => arg.tokenInfo.token).toList();
    if (injectDataFetching) {
      serviceArgs.add('dataFetchingEnvironment');
    }
    final serviceCall = '$sericeInstanceName.${method.name}(${serviceArgs.join(", ")})';
    final String returnType;
    final List<String> statements;

    final validationCall = method.getDirectiveByName(glValidate) != null
        ? '$sericeInstanceName.${GLService.getValidationMethodName(method.name.token)}(${serviceArgs.join(", ")});'
        : null;

    if (type == GLQueryType.subscription) {
      returnType = serializer.serializeTypeReactive(
          context: context,
          glType: createListTypeOnSubscription(
              _getServiceReturnType(method.type), type),
          reactive: true);
      statements = [
        if (validationCall != null) validationCall,
        "return $serviceCall;",
      ];
    } else if (reactive) {
      returnType = serializer.serializeTypeReactive(
          context: context,
          glType: _getServiceReturnType(method.type),
          reactive: true);
      statements = [
        if (validationCall != null) validationCall,
        "return $serviceCall;",
      ];
    } else {
      context.addImport(JavaImports.completableFuture);
      final baseReturnType = serializer.serializeTypeReactive(
          context: context,
          glType: _getServiceReturnType(method.type),
          reactive: false);
      final returnTypeIsVoid = baseReturnType == "void";
      returnType =
          "CompletableFuture<${convertPrimitiveToBoxed(baseReturnType)}>";
      statements = [
        _wrapInCompletableFuture([
          if (validationCall != null) validationCall,
          serviceCall,
        ], returnTypeIsVoid),
      ];
    }

    final fullReturnType =
        qualifier != null ? "$qualifier $returnType" : returnType;

    buffer.writeln(codeGenUtils.createMethod(
        returnType: fullReturnType,
        methodName: method.name.token,
        arguments: args,
        statements: statements));

    return buffer.toString();
  }

  String _wrapInCompletableFuture(List<String> innerStatements, bool returnVoid) {
    final method = returnVoid ? 'runAsync' : 'supplyAsync';
    if (innerStatements.length == 1) {
      return "return CompletableFuture.$method(() -> ${innerStatements.first});";
    }
    // Block lambda needed when validation precedes the service call.
    final preceding = innerStatements.sublist(0, innerStatements.length - 1);
    final last = innerStatements.last;
    final blockStatements = [
      ...preceding,
      returnVoid ? "$last;" : "return $last;",
    ];
    return "return CompletableFuture.$method(() -> ${codeGenUtils.block(blockStatements)});";
  }

  GLType createListTypeOnSubscription(GLType type, GLQueryType queryType) {
    if (queryType == GLQueryType.subscription) {
      return GLListType(type, false);
    }
    return type;
  }

  String serializeRepository(
      GLInterfaceDefinition interface, String importPrefix) {
    var body = _serializeRepositoryBody(interface);
    return serializer.serializeWithImport(interface, importPrefix, body);
  }

  String _serializeRepositoryBody(GLInterfaceDefinition interface) {
    // find the _ field and ignore it
    interface
        .getSerializableFields(grammar.mode)
        .where((f) => f.name.token == "_")
        .forEach((f) {
      f.addDirective(
          GLDirectiveValue(glSkipOnServer.toToken(), [], [], generated: true));
    });
    interface.addImport(SpringImports.repository);

    var gqRepo = interface.getDirectiveByName(glRepository)!;
    var className = gqRepo.getArgValueAsString(glClass);
    if (className == null) {
      className = "JpaRepository";
      interface.addImport(SpringImports.jpaRepository);
    }
    var id = gqRepo.getArgValueAsString(glIdType);
    var ontType = gqRepo.getArgValueAsString(glType)!;

    interface.addInterface(GLInterfaceDefinition(
        name: "$className<$ontType, ${id}>".toToken(),
        nameDeclared: false,
        fields: [],
        directives: [],
        interfaceNames: {},
        extension: false));

    return serializer.serializeInterface(interface, getters: false);
  }

  String serializeService(GLService service, String importPrefix) {
    var body = _serializeServiceBody(service);
    return serializer.serializeWithImport(service, importPrefix, body);
  }

  String _serializeServiceBody(GLService service) {
    var mappings = service.serviceMapping;

    var buffer = StringBuffer();
    buffer.writeln(
        codeGenUtils.createInterface(interfaceName: service.token, statements: [
      '',
      ...service.fields
          .map((n) => serializeMethodDeclaration(
              n, service.getTypeByFieldName(n.name.token)!, service))
          .map((e) => "${e};"),
      '',
      ...mappings
          .map((m) => serializeServiceMappingImplMethodHeader(m, service))
          .map((e) => "${e};")
    ]));
    return buffer.toString();
  }

  String serializeMethodDeclaration(
      GLField method, GLQueryType type, GLToken context,
      {String? argPrefix}) {
    GLType returnType;
    if (method.getDirectiveByName(glValidate)?.generated == true) {
      returnType = GLType('void'.toToken(), false);
    } else {
      returnType = _getServiceReturnType(method.type);
    }
    var result =
        "${serializer.serializeTypeReactive(context: context, glType: createListTypeOnSubscription(returnType, type), reactive: reactive || type == GLQueryType.subscription)} ${method.name}(${serializeArgs(method.arguments, context, argPrefix)}";
    if (injectDataFetching) {
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

  GLType _getServiceReturnType(GLType type) {
    var token = type.token;
    if (grammar.isNonProjectableType(token)) {
      return type;
    }

    var returnType = grammar.getType(type.tokenInfo);

    var skipOnserverDir = returnType.getDirectiveByName(glSkipOnServer);
    if (skipOnserverDir != null) {
      var mapTo = getMapTo(type.tokenInfo);

      var rt = GLType(mapTo.toToken(), false);
      if (type.isList) {
        if (mapTo == "Object") {
          rt = GLType("?".toToken(), false);
        }
        return GLListType(rt, false);
      } else {
        return rt;
      }
    }
    return type;
  }

  String getMapTo(TokenInfo typeToken) {
    var type = grammar.getType(typeToken);
    var dir = type.getDirectiveByName(glSkipOnServer);
    if (dir == null) {
      return type.token;
    }
    var mapTo = dir.getArgValueAsString(glMapTo);
    if (mapTo == null) {
      return "Object";
    }
    var mappedTo = grammar
        .getType(dir.getArgumentByName(glMapTo)!.tokenInfo.ofNewName(mapTo));
    if (mappedTo.getDirectiveByName(glSkipOnServer) != null) {
      throw ParseException(
          "You cannot mapTo ${mappedTo.tokenInfo} because it is annotated with $glSkipOnServer",
          info: mappedTo.tokenInfo);
    }
    return mappedTo.token;
  }

  String serializeArgs(List<GLArgumentDefinition> args, GLToken context,
      [String? prefix]) {
    return args.map((a) => serializeArg(a, context)).map((e) {
      if (prefix != null) {
        return "$prefix $e";
      }
      return e;
    }).join(", ");
  }

  String serializeArg(GLArgumentDefinition arg, GLToken context) {
    return "${_resolveArgType(arg, context)} ${arg.tokenInfo}";
  }

  /// Returns `MultipartFile` / `List<MultipartFile>` for upload scalars in
  /// blocking mode, or `FilePart` / `List<FilePart>` in reactive mode.
  /// Otherwise delegates to the standard type serializer.
  String _resolveArgType(GLArgumentDefinition arg, GLToken context) {
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
      statement.write(', ${arg.tokenInfo}');
    }
    if (injectDataFetching) {
      statement.write(', dataFetchingEnvironment');
    }
    statement.write(')');
    final body = reactive
        ? 'return ${statement};'
        : _wrapInCompletableFuture([statement.toString()], false);
    return '${serializeControllerMethodHeader(mapping, context)} ${codeGenUtils.block([body])}';
  }

  String _getAnnotation(GLSchemaMapping mapping, GLToken context) {
    if (mapping.isBatch) {
      context.addImport(SpringImports.batchMapping);

      return '@BatchMapping(typeName="${mapping.type.tokenInfo}", field="${mapping.field.name}")';
    } else {
      context.addImport(SpringImports.schemaMapping);
      return '@SchemaMapping(typeName="${mapping.type.tokenInfo}", field="${mapping.field.name}")';
    }
  }

  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    var annotation = _getAnnotation(mapping, context);
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
        returnType = "Flux<$boxedType>";
        statement = "return Flux.fromIterable(value);";
      } else {
        context.addImport(JavaImports.mono);
        returnType = "Mono<$boxedType>";
        statement = "return Mono.just(value);";
      }
    } else {
      if (mapping.isBatch) {
        returnType = "List<$boxedType>";
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

  /// Returns the Java getter method name for [fieldName] given its serialized [fieldType].
  /// Records use the bare field name; classes use `get` prefix, except primitive
  /// `boolean` which uses `is`.
  String _getterMethodName(String fieldName, String fieldType) {
    if (serializer.typesAsRecords) return fieldName;
    final prefix = fieldType == 'boolean' ? 'is' : 'get';
    return '$prefix${fieldName.firstUp}';
  }

  /// Generates a @SchemaMapping that forwards a field directly to the matching
  /// accessor on the backing server type, e.g.:
  ///
  ///   @SchemaMapping(typeName="ClientVehicle", field="brand")
  ///   public String clientVehicleBrand(ServerVehicle value) {
  ///       return value.getBrand();
  ///   }
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.writeln(_getAnnotation(mapping, context));

    final fieldName = mapping.field.name.token;
    final fieldType = serializer.serializeTypeReactive(
        context: context, glType: mapping.field.type, reactive: false);
    final boxedFieldType = convertPrimitiveToBoxed(fieldType);
    final argType = serializer.serializeType(
        _getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);

    final getterCall = 'value.${_getterMethodName(fieldName, fieldType)}()';

    final String returnType;
    final String statement;
    if (reactive) {
      context.addImport(JavaImports.mono);
      returnType = 'Mono<$boxedFieldType>';
      statement = 'return Mono.just($getterCall);';
    } else {
      // Simple getter — no async wrapping needed.
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
          _getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
      if (keyType == "Object") {
        keyType = "?";
      }
      context.addImport(JavaImports.map);
      return """
Map<${convertPrimitiveToBoxed(keyType)}, ${convertPrimitiveToBoxed(serializer.serializeType(mapping.field.type, false))}>
      """
          .trim();
    } else {
      return serializer.serializeTypeReactive(
          context: context, glType: mapping.field.type, reactive: false);
    }
  }

  String _getMappingArgument(GLSchemaMapping mapping, GLToken context) {
    var argType = serializer.serializeType(
        _getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
    if (mapping.isBatch) {
      context.addImport(importList);
      return "List<${convertPrimitiveToBoxed(argType)}> value";
    } else {
      return "${argType} value";
    }
  }

  String serializeControllerMethodHeader(GLSchemaMapping mapping, GLToken context) {

    var buffer = StringBuffer();
    buffer.writeln(_getAnnotation(mapping, context));
    buffer.write("public ");
   
    final returnType = _getReturnType(mapping, context);
    if (reactive) {
      context.addImport(JavaImports.mono);
      buffer.write(
          "Mono<${convertPrimitiveToBoxed(returnType)}> ${mapping.key}(${_getMappingArgument(mapping, context)}");
    } else {
      context.addImport(JavaImports.completableFuture);
      buffer.write(
          "CompletableFuture<${convertPrimitiveToBoxed(returnType)}> ${mapping.key}(${_getMappingArgument(mapping, context)}");
    }
    for (var arg in mapping.field.arguments) {
      final argType = _resolveArgType(arg, context);
      context.addImport(SpringImports.gqlArgument);
      buffer.write(', @Argument $argType ${arg.tokenInfo}');
    }
    if (injectDataFetching) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      buffer.write(', DataFetchingEnvironment dataFetchingEnvironment)');
    } else {
      buffer.write(')');
    }
    return buffer.toString();

  }

  String serializeServiceMappingImplMethodHeader(
      GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
   
    
    final returnType = _getReturnType(mapping, context);
    if (reactive) {
      context.addImport(JavaImports.mono);
      buffer.write(
          "Mono<${convertPrimitiveToBoxed(returnType)}> ${mapping.key}(${_getMappingArgument(mapping, context)}");
    } else {
      buffer.write("$returnType ${mapping.key}(${_getMappingArgument(mapping, context)}");
    }
    for (var arg in mapping.field.arguments) {
      final argType = _resolveArgType(arg, context);
      buffer.write(', $argType ${arg.tokenInfo}');

    }
    if (injectDataFetching) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      buffer.write(', DataFetchingEnvironment dataFetchingEnvironment)');
    } else {
      buffer.write(')');
    }
    return buffer.toString();
  }

  GLDirectiveValue _createResolverDirective(GLQueryType type) {
    return GLDirectiveValue(
        "_gqMapping".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), _toMappingAnnotationValue(type)),
          GLArgumentValue(glImport.toToken(), _toMappingAnnotationImport(type)),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  GLDirectiveValue _createControllerDirective() {
    return GLDirectiveValue(
        "_gqController".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), "@Controller"),
          GLArgumentValue(glImport.toToken(), SpringImports.controller),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  GLDirectiveValue _createArgumentDirective() {
    return GLDirectiveValue(
        "_gqController".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), "@Argument"),
          GLArgumentValue(glImport.toToken(), SpringImports.gqlArgument),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  String _toMappingAnnotationValue(GLQueryType queryType) {
    switch (queryType) {
      case GLQueryType.query:
        return "@QueryMapping";
      case GLQueryType.mutation:
        return "@MutationMapping";
      case GLQueryType.subscription:
        return "@SubscriptionMapping";
    }
  }

  String _toMappingAnnotationImport(GLQueryType queryType) {
    switch (queryType) {
      case GLQueryType.query:
        return SpringImports.queryMapping;
      case GLQueryType.mutation:
        return SpringImports.mutationMapping;
      case GLQueryType.subscription:
        return SpringImports.subscriptionMapping;
    }
  }
}
