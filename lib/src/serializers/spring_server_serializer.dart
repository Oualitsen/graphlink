import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/gl_grammar.dart';
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
import 'package:graphlink/src/utils.dart';

class SpringServerSerializer {
  final String? defaultRepositoryBase;

  final GLGrammar grammar;
  final JavaSerializer serializer;
  final bool generateSchema;
  final bool injectDataFetching;
  final codeGenUtils = JavaCodeGenUtils();

  SpringServerSerializer(this.grammar,
      {this.defaultRepositoryBase,
      JavaSerializer? javaSerializer,
      this.generateSchema = false,
      this.injectDataFetching = false})
      : assert(grammar.mode == CodeGenerationMode.server,
            "Grammar must be in code generation mode = `CodeGenerationMode.server`"),
        serializer = javaSerializer ??
            JavaSerializer(grammar,
                inputsCheckForNulls: true, typesCheckForNulls: grammar.mode == CodeGenerationMode.client) {
    _annotateRepositories();
    _annotateControllers();
    grammar.convertAnnotationsToDecorators(
        _getControllerMixins(), (val) => AnnotationSerializer.serializeAnnotation(val, multiLineString: false));
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

  void _annotateRepositories() {
    for (var repo in grammar.repositories.values) {
      var dec = GLDirectiveValue.createGqDecorators(
          decorators: ["@Repository"], applyOnClient: false, import: "org.springframework.stereotype.Repository");
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

    if (ctrl.fields.isNotEmpty && injectDataFetching) {
      ctrl.addImport(SpringImports.gqlDataFetchingEnvironment);
    }
    var decorators = serializer.serializeDecorators(ctrl.getDirectives()).trim();

    var buffer = StringBuffer();
    buffer.writeln(decorators);
    buffer.writeln(codeGenUtils.createClass(className: controllerName, statements: [
      'private final ${ctrl.serviceName} $sericeInstanceName;',
      '',
      serializer.generateContructor(
          controllerName,
          [
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
          ctrl.getTypeByFieldName(field.name.token)!, field, sericeInstanceName, ctrl,
          qualifier: "public")),
      '',
      // get schema mappings by service name
      ...ctrl.mappings.map((m) => serializeMappingMethod(m, sericeInstanceName, ctrl))
    ]));

    return buffer.toString();
  }

  String serializehandlerMethod(GLQueryType type, GLField method, String sericeInstanceName, GLToken context,
      {String? qualifier}) {
    final decorators = serializer.serializeDecorators(method.getDirectives()).trim();
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    var args = method.arguments.map((arg) {
      var argDecorators = serializer.serializeDecorators(arg.getDirectives()).trim();
      if (argDecorators.isNotEmpty) {
        return "$argDecorators ${serializer.serializeType(arg.type, false)} ${arg.token}";
      }
      return "${serializer.serializeType(arg.type, false)} ${arg.token}";
    }).toList();

    if (injectDataFetching) {
      args.add("DataFetchingEnvironment dataFetchingEnvironment");
    }
    var serviceArgs = method.arguments.map((arg) => arg.tokenInfo.token).toList();
    if (injectDataFetching) {
      serviceArgs.add('dataFetchingEnvironment');
    }
    String returnType = serializer.serializeTypeReactive(
        context: context,
        glType: createListTypeOnSubscription(_getServiceReturnType(method.type), type),
        reactive: type == GLQueryType.subscription);
    bool returnTypeIsVoid = returnType == "void";

    if (qualifier != null) {
      returnType = "${qualifier} ${returnType}";
    }
    buffer.writeln(
        codeGenUtils.createMethod(returnType: returnType, methodName: method.name.token, arguments: args, statements: [
      if (method.getDirectiveByName(glValidate) != null)
        '$sericeInstanceName.${GLService.getValidationMethodName(method.name.token)}(${serviceArgs.join(", ")});',
      if (returnTypeIsVoid)
        '$sericeInstanceName.${method.name}(${serviceArgs.join(", ")});'
      else
        'return $sericeInstanceName.${method.name}(${serviceArgs.join(", ")});',
    ]));

    return buffer.toString();
  }

  GLType createListTypeOnSubscription(GLType type, GLQueryType queryType) {
    if (queryType == GLQueryType.subscription) {
      return GLListType(type, false);
    }
    return type;
  }

  String serializeRepository(GLInterfaceDefinition interface, String importPrefix) {
    var body = _serializeRepositoryBody(interface);
    return serializer.serializeWithImport(interface, importPrefix, body);
  }

  String _serializeRepositoryBody(GLInterfaceDefinition interface) {
    // find the _ field and ignore it
    interface.getSerializableFields(grammar.mode).where((f) => f.name.token == "_").forEach((f) {
      f.addDirective(GLDirectiveValue(glSkipOnServer.toToken(), [], [], generated: true));
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
    buffer.writeln(codeGenUtils.createInterface(interfaceName: service.token, statements: [
      '',
      ...service.fields
          .map((n) => serializeMethodDeclaration(n, service.getTypeByFieldName(n.name.token)!, service))
          .map((e) => "${e};"),
      '',
      ...mappings
          .map((m) => serializeMappingImplMethodHeader(m, service, skipAnnotation: true, skipQualifier: true))
          .map((e) => "${e};")
    ]));
    return buffer.toString();
  }

  String serializeMethodDeclaration(GLField method, GLQueryType type, GLToken context, {String? argPrefix}) {
    GLType returnType;
    if (method.getDirectiveByName(glValidate)?.generated == true) {
      returnType = GLType('void'.toToken(), false);
    } else {
      returnType = _getServiceReturnType(method.type);
    }
    var result =
        "${serializer.serializeTypeReactive(context: context, glType: createListTypeOnSubscription(returnType, type), reactive: type == GLQueryType.subscription)} ${method.name}(${serializeArgs(method.arguments, argPrefix)}";
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
    var mappedTo = grammar.getType(dir.getArgumentByName(glMapTo)!.tokenInfo.ofNewName(mapTo));
    if (mappedTo.getDirectiveByName(glSkipOnServer) != null) {
      throw ParseException("You cannot mapTo ${mappedTo.tokenInfo} because it is annotated with $glSkipOnServer",
          info: mappedTo.tokenInfo);
    }
    return mappedTo.token;
  }

  String serializeArgs(List<GLArgumentDefinition> args, [String? prefix]) {
    return args.map((a) => serializeArg(a)).map((e) {
      if (prefix != null) {
        return "$prefix $e";
      }
      return e;
    }).join(", ");
  }

  String serializeArg(GLArgumentDefinition arg) {
    return "${serializer.serializeType(arg.type, false)} ${arg.tokenInfo}";
  }

  String serializeMappingMethod(GLSchemaMapping mapping, String serviceInstanceName, GLToken context) {
    if (mapping.forbid && generateSchema) {
      return "";
    }
    if (mapping.forbid) {
      context.addImport(SpringImports.gqlGraphQLException);

      return '${serializeMappingImplMethodHeader(mapping, context)} ${codeGenUtils.block([
            '''throw new GraphQLException("Access denied to field '${mapping.type.tokenInfo}.${mapping.field.name}'");'''
          ])}';
    }

    if (mapping.identity) {
      return serializeIdentityMapping(mapping, context);
    }

    final statement = StringBuffer('return $serviceInstanceName.${mapping.key}(value');
    if (injectDataFetching) {
      statement.write(', dataFetchingEnvironment');
    }
    statement.write(');');
    return '${serializeMappingImplMethodHeader(mapping, context)} ${codeGenUtils.block([statement.toString()])}';
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
    final type = serializer.serializeTypeReactive(context: context, glType: mapping.field.type, reactive: false);
    final String returnType;
    if (mapping.isBatch) {
      returnType = "List<${convertPrimitiveToBoxed(type)}>";
    } else {
      returnType = type;
    }
    buffer.writeln(
      codeGenUtils.createMethod(
          returnType: 'public ${returnType}',
          methodName: mapping.key,
          arguments: ['$returnType value'],
          statements: ['return value;']),
    );

    return buffer.toString();
  }

  String _getReturnType(GLSchemaMapping mapping, GLToken context) {
    if (mapping.isBatch) {
      var keyType = serializer.serializeType(_getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
      if (keyType == "Object") {
        keyType = "?";
      }
      context.addImport(JavaImports.map);
      return """
Map<${convertPrimitiveToBoxed(keyType)}, ${convertPrimitiveToBoxed(serializer.serializeType(mapping.field.type, false))}>
      """
          .trim();
    } else {
      return serializer.serializeTypeReactive(context: context, glType: mapping.field.type, reactive: false);
    }
  }

  String _getMappingArgument(GLSchemaMapping mapping, GLToken context) {
    var argType = serializer.serializeType(_getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
    if (mapping.isBatch) {
      context.addImport(importList);
      return "List<${convertPrimitiveToBoxed(argType)}> value";
    } else {
      return "${argType} value";
    }
  }

  String serializeMappingImplMethodHeader(GLSchemaMapping mapping, GLToken context,
      {bool skipAnnotation = false, bool skipQualifier = false}) {
    var buffer = StringBuffer();
    if (!skipAnnotation) {
      buffer.writeln(_getAnnotation(mapping, context));
    }
    if (!skipQualifier) {
      buffer.write("public ");
    }
    buffer.write("${_getReturnType(mapping, context)} ${mapping.key}(${_getMappingArgument(mapping, context)}");
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
