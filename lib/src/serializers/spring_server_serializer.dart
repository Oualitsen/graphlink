import 'package:retrofit_graphql/src/code_gen_utils.dart';
import 'package:retrofit_graphql/src/constants.dart';
import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_controller.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_interface_definition.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_service.dart';
import 'package:retrofit_graphql/src/model/gq_shcema_mapping.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_token_with_fields.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/utils.dart';

class SpringServerSerializer {
  final String? defaultRepositoryBase;

  final GQGrammar grammar;
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
                inputsCheckForNulls: true,
                typesCheckForNulls: grammar.mode == CodeGenerationMode.client) {
    _annotateRepositories();
    _annotateControllers();
  }

  List<String> serializeServices(String importPrefix) {
    return grammar.services.values.map((service) {
      return serializeService(service, importPrefix);
    }).toList();
  }

  void _annotateRepositories() {
    for (var repo in grammar.repositories.values) {
      var dec = GQDirectiveValue.createGqDecorators(
          decorators: ["@Repository"],
          applyOnClient: false,
          import: "org.springframework.stereotype.Repository");
      repo.addDirective(dec);
    }
  }

  void _annotateControllers() {
    for (var ctrl in grammar.controllers.values) {
      for (var method in ctrl.fields) {
        var annotations =
            method.getDirectives().where((d) => d.getArgValue(gqAnnotation) == true).toList();
        if (annotations.isNotEmpty) {
          for (var an in annotations) {
            String? import = an.getArgValueAsString(gqImport);
            var dec = GQDirectiveValue.createGqDecorators(
                decorators: [serializer.serializeAnnotation(an)],
                applyOnClient: false,
                import: import);
            if (import != null) {
              ctrl.addImport(import);
            }
            method.addDirective(dec);
          }
        }
      }
    }
  }

  String serializeController(GQController ctrl, String importPrefix) {
    var body = _serializeControllerBody(ctrl, importPrefix);
    return serializer.serializeWithImport(ctrl, importPrefix, body);
  }

  String _serializeControllerBody(GQController ctrl, String importPrefix) {
    final controllerName = ctrl.token;
    final sericeInstanceName = ctrl.serviceName.firstLow;

    ctrl.addImport(SpringImports.controller);
    if (ctrl.fields.isNotEmpty && injectDataFetching) {
      ctrl.addImport(SpringImports.gqlDataFetchingEnvironment);
    }

    var buffer = StringBuffer();
    buffer.writeln("@Controller");
    buffer.writeln(codeGenUtils.createClass(className: controllerName, statements: [
      'private final ${ctrl.serviceName} $sericeInstanceName;',
      '',
      serializer.generateContructor(
          controllerName,
          [
            GQField(
                name: sericeInstanceName.toToken(),
                type: GQType(ctrl.serviceName.toToken(), false),
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

  String serializehandlerMethod(
      GQQueryType type, GQField method, String sericeInstanceName, GQToken context,
      {String? qualifier}) {
    final decorators = serializer.serializeDecorators(method.getDirectives());
    var buffer = StringBuffer();
    buffer.writeln(getAnnotationByShcemaType(type, context));
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    var args = method.arguments
        .map((arg) => "@Argument ${serializer.serializeType(arg.type, false)} ${arg.token}")
        .toList();
    if (args.isNotEmpty) {
      context.addImport(SpringImports.gqlArgument);
    }
    if (injectDataFetching) {
      args.add("DataFetchingEnvironment dataFetchingEnvironment");
    }
    var serviceArgs = method.arguments.map((arg) => arg.tokenInfo.token).toList();
    if (injectDataFetching) {
      serviceArgs.add('dataFetchingEnvironment');
    }
    String returnType = serializer.serializeTypeReactive(
        context: context,
        gqType: createListTypeOnSubscription(_getServiceReturnType(method.type), type),
        reactive: type == GQQueryType.subscription);
    bool returnTypeIsVoid = returnType == "void";

    if (qualifier != null) {
      returnType = "${qualifier} ${returnType}";
    }
    buffer.writeln(codeGenUtils.createMethod(
        returnType: returnType,
        methodName: method.name.token,
        arguments: args,
        statements: [
          if (method.getDirectiveByName(gqValidate) != null)
            '$sericeInstanceName.${GQService.getValidationMethodName(method.name.token)}(${serviceArgs.join(", ")});',
          if (returnTypeIsVoid)
            '$sericeInstanceName.${method.name}(${serviceArgs.join(", ")});'
          else
            'return $sericeInstanceName.${method.name}(${serviceArgs.join(", ")});',
        ]));

    return buffer.toString();
  }

  GQType createListTypeOnSubscription(GQType type, GQQueryType queryType) {
    if (queryType == GQQueryType.subscription) {
      return GQListType(type, false);
    }
    return type;
  }

  String serializeRepository(GQInterfaceDefinition interface, String importPrefix) {
    var body = _serializeRepositoryBody(interface);
    return serializer.serializeWithImport(interface, importPrefix, body);
  }

  String _serializeRepositoryBody(GQInterfaceDefinition interface) {
    // find the _ field and ignore it
    interface.getSerializableFields(grammar.mode).where((f) => f.name.token == "_").forEach((f) {
      f.addDirective(GQDirectiveValue(gqSkipOnServer.toToken(), [], [], generated: true));
    });
    interface.addImport(SpringImports.repository);

    var gqRepo = interface.getDirectiveByName(gqRepository)!;
    var className = gqRepo.getArgValueAsString(gqClass);
    if (className == null) {
      className = "JpaRepository";
      interface.addImport(SpringImports.jpaRepository);
    }
    var id = gqRepo.getArgValueAsString(gqIdType);
    var ontType = gqRepo.getArgValueAsString(gqType)!;

    interface.addInterface(GQInterfaceDefinition(
        name: "$className<$ontType, ${id}>".toToken(),
        nameDeclared: false,
        fields: [],
        directives: [],
        interfaceNames: {}));

    return serializer.serializeInterface(interface, getters: false);
  }

  String serializeService(GQService service, String importPrefix) {
    var body = _serializeServiceBody(service);
    return serializer.serializeWithImport(service, importPrefix, body);
  }

  String _serializeServiceBody(GQService service) {
    var mappings = service.serviceMapping;

    var buffer = StringBuffer();
    buffer.writeln(codeGenUtils.createInterface(interfaceName: service.token, statements: [
      '',
      ...service.fields
          .map((n) =>
              serializeMethodDeclaration(n, service.getTypeByFieldName(n.name.token)!, service))
          .map((e) => "${e};"),
      '',
      ...mappings
          .map((m) => serializeMappingImplMethodHeader(m, service,
              skipAnnotation: true, skipQualifier: true))
          .map((e) => "${e};")
    ]));
    return buffer.toString();
  }

  String serializeMethodDeclaration(GQField method, GQQueryType type, GQToken context,
      {String? argPrefix}) {
    GQType returnType;
    if (method.getDirectiveByName(gqValidate)?.generated == true) {
      returnType = GQType('void'.toToken(), false);
    } else {
      returnType = _getServiceReturnType(method.type);
    }
    var result =
        "${serializer.serializeTypeReactive(context: context, gqType: createListTypeOnSubscription(returnType, type), reactive: type == GQQueryType.subscription)} ${method.name}(${serializeArgs(method.arguments, argPrefix)}";
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

  GQType _getServiceReturnType(GQType type) {
    var token = type.token;
    if (grammar.isNonProjectableType(token)) {
      return type;
    }

    var returnType = grammar.getType(type.tokenInfo);

    var skipOnserverDir = returnType.getDirectiveByName(gqSkipOnServer);
    if (skipOnserverDir != null) {
      var mapTo = getMapTo(type.tokenInfo);

      var rt = GQType(mapTo.toToken(), false);
      if (type.isList) {
        if (mapTo == "Object") {
          rt = GQType("?".toToken(), false);
        }
        return GQListType(rt, false);
      } else {
        return rt;
      }
    }
    return type;
  }

  String getMapTo(TokenInfo typeToken) {
    var type = grammar.getType(typeToken);
    var dir = type.getDirectiveByName(gqSkipOnServer);
    if (dir == null) {
      return type.token;
    }
    var mapTo = dir.getArgValueAsString(gqMapTo);
    if (mapTo == null) {
      return "Object";
    }
    var mappedTo = grammar.getType(dir.getArgumentByName(gqMapTo)!.tokenInfo.ofNewName(mapTo));
    if (mappedTo.getDirectiveByName(gqSkipOnServer) != null) {
      throw ParseException(
          "You cannot mapTo ${mappedTo.tokenInfo} because it is annotated with $gqSkipOnServer",
          info: mappedTo.tokenInfo);
    }
    return mappedTo.token;
  }

  String serializeArgs(List<GQArgumentDefinition> args, [String? prefix]) {
    return args.map((a) => serializeArg(a)).map((e) {
      if (prefix != null) {
        return "$prefix $e";
      }
      return e;
    }).join(", ");
  }

  String serializeArg(GQArgumentDefinition arg) {
    return "${serializer.serializeType(arg.type, false)} ${arg.tokenInfo}";
  }

  String serializeMappingMethod(
      GQSchemaMapping mapping, String serviceInstanceName, GQToken context) {
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
    return '${serializeMappingImplMethodHeader(mapping, context)} ${codeGenUtils.block([
          statement.toString()
        ])}';
  }

  String _getAnnotation(GQSchemaMapping mapping, GQToken context) {
    if (mapping.isBatch) {
      context.addImport(SpringImports.batchMapping);

      return '@BatchMapping(typeName="${mapping.type.tokenInfo}", field="${mapping.field.name}")';
    } else {
      context.addImport(SpringImports.schemaMapping);
      return '@SchemaMapping(typeName="${mapping.type.tokenInfo}", field="${mapping.field.name}")';
    }
  }

  String serializeIdentityMapping(GQSchemaMapping mapping, GQToken context) {
    var buffer = StringBuffer();
    var annotation = _getAnnotation(mapping, context);
    if (annotation.isNotEmpty) {
      buffer.writeln(annotation);
    }
    final type = serializer.serializeTypeReactive(
        context: context, gqType: mapping.field.type, reactive: false);
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

  String _getReturnType(GQSchemaMapping mapping, GQToken context) {
    if (mapping.isBatch) {
      var keyType = serializer.serializeType(
          _getServiceReturnType(GQType(mapping.type.tokenInfo, false)), false);
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
          context: context, gqType: mapping.field.type, reactive: false);
    }
  }

  String _getMappingArgument(GQSchemaMapping mapping, GQToken context) {
    var argType = serializer.serializeType(
        _getServiceReturnType(GQType(mapping.type.tokenInfo, false)), false);
    if (mapping.isBatch) {
      context.addImport(importList);
      return "List<${convertPrimitiveToBoxed(argType)}> value";
    } else {
      return "${argType} value";
    }
  }

  String serializeMappingImplMethodHeader(GQSchemaMapping mapping, GQToken context,
      {bool skipAnnotation = false, bool skipQualifier = false}) {
    var buffer = StringBuffer();
    if (!skipAnnotation) {
      buffer.writeln(_getAnnotation(mapping, context));
    }
    if (!skipQualifier) {
      buffer.write("public ");
    }
    buffer.write(
        "${_getReturnType(mapping, context)} ${mapping.key}(${_getMappingArgument(mapping, context)}");
    if (injectDataFetching) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      buffer.write(', DataFetchingEnvironment dataFetchingEnvironment)');
    } else {
      buffer.write(')');
    }
    return buffer.toString();
  }

  String getAnnotationByShcemaType(GQQueryType queryType, GQToken context) {
    String result;
    String import;
    switch (queryType) {
      case GQQueryType.query:
        result = "QueryMapping";
        import = SpringImports.queryMapping;
        break;
      case GQQueryType.mutation:
        result = "MutationMapping";
        import = SpringImports.mutationMapping;
        break;
      case GQQueryType.subscription:
        result = "SubscriptionMapping";
        import = SpringImports.subscriptionMapping;
        break;
    }
    context.addImport(import);
    return "@${result}";
  }
}
