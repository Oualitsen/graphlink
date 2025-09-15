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

  SpringServerSerializer(this.grammar,
      {this.defaultRepositoryBase, JavaSerializer? javaSerializer, this.generateSchema = false})
      : assert(grammar.mode == CodeGenerationMode.server,
            "Gramar must be in code generation mode = `CodeGenerationMode.server`"),
        serializer = javaSerializer ?? JavaSerializer(grammar) {
    _annotateRepositories();
  }

  List<String> serializeServices(String importPrefix) {
    return grammar.services.values.map((service) {
      return serializeService(service, importPrefix);
    }).toList();
  }

  void _annotateRepositories() {
    for (var repo in grammar.repositories.values) {
      var dec = GQDirectiveValue.createGqDecorators(
          decorators: ["@Repository"], applyOnClient: false, import: "org.springframework.stereotype.Repository");
      repo.addDirective(dec);
    }
  }

  String serializeController(GQController ctrl, String importPrefix, {bool injectDataFtechingEnv = false}) {
    var body = _serializeControllerBody(ctrl, importPrefix, injectDataFtechingEnv: injectDataFtechingEnv);
    return serializer.serializeWithImport(ctrl, importPrefix, body);
  }

  String _serializeControllerBody(GQController ctrl, String importPrefix, {bool injectDataFtechingEnv = false}) {
    final controllerName = ctrl.token;
    final sericeInstanceName = ctrl.serviceName.firstLow;

    ctrl.addImport(SpringImports.controller);

    var buffer = StringBuffer();
    buffer.writeln("@Controller");
    buffer.writeln("public class $controllerName {");
    buffer.writeln();
    buffer.writeln('private final ${ctrl.serviceName} $sericeInstanceName;'.ident());
    buffer.writeln();
    buffer.writeln(serializer
        .generateContructor(
            controllerName,
            [
              GQField(
                  name: sericeInstanceName.toToken(),
                  type: GQType(ctrl.serviceName.toToken(), false),
                  arguments: [],
                  directives: [])
            ],
            "public",
            ctrl)
        .ident());
    for (var field in ctrl.fields) {
      var type = ctrl.getTypeByFieldName(field.name.token)!;
      buffer.writeln(serializehandlerMethod(type, field, sericeInstanceName, ctrl,
              injectDataFtechingEnv: injectDataFtechingEnv, qualifier: "public")
          .ident());
      buffer.writeln();
    }
    // get schema mappings by service name

    var mappings = ctrl.mappings;
    for (var m in mappings) {
      buffer.writeln(serializeMappingMethod(m, sericeInstanceName, ctrl).ident());
    }
    buffer.writeln("}");
    return buffer.toString();
  }

  String serializehandlerMethod(GQQueryType type, GQField method, String sericeInstanceName, GQToken context,
      {bool injectDataFtechingEnv = false, String? qualifier}) {
    final decorators = serializer.serializeDecorators(method.getDirectives());

    String statement =
        "return $sericeInstanceName.${method.name}(${method.arguments.map((arg) => arg.tokenInfo).join(", ")}";
    if (injectDataFtechingEnv) {
      if (method.arguments.isNotEmpty) {
        statement = "$statement, dataFetchingEnvironment);";
      } else {
        statement = "${statement}dataFetchingEnvironment);";
      }
    } else {
      statement = "$statement);";
    }
    if (method.arguments.isNotEmpty) {
      context.addImport(SpringImports.gqlArgument);
    }
    var result = """
${getAnnotationByShcemaType(type, context)}
${qualifier == null ? '' : "${qualifier} "}${serializeMethodDeclaration(method, type, context, argPrefix: "@Argument", injectDataFtechingEnv: injectDataFtechingEnv)} {
${statement.ident()}
}"""
        .trim();
    if (decorators.isNotEmpty) {
      result = """
${decorators.trim()}
$result
""";
    }
    return result;
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

  String serializeService(GQService service, String importPrefix, {bool injectDataFtechingEnv = false}) {
    var body = _serializeServiceBody(service, injectDataFtechingEnv: injectDataFtechingEnv);
    return serializer.serializeWithImport(service, importPrefix, body);
  }

  String _serializeServiceBody(GQService service, {bool injectDataFtechingEnv = false}) {
    var mappings = service.serviceMapping;

    var buffer = StringBuffer();
    buffer.writeln('public interface ${service.token} {');
    buffer.writeln();
    for (var n in service.fields) {
      var type = service.getTypeByFieldName(n.name.token)!;
      buffer.write(serializeMethodDeclaration(n, type, service, injectDataFtechingEnv: injectDataFtechingEnv).ident());
      buffer.writeln(";");
      buffer.writeln();
    }
    if (mappings.isNotEmpty) {
      buffer.writeln('// schema mappings and batch mapping'.ident());
    }
    for (var m in mappings) {
      buffer.write(serializeMappingImplMethodHeader(m, service, skipAnnotation: true, skipQualifier: true).ident());
      buffer.writeln(";");
      buffer.writeln();
    }
    buffer.writeln("}");
    return buffer.toString();
  }

  String serializeMethodDeclaration(GQField method, GQQueryType type, GQToken context,
      {String? argPrefix, bool injectDataFtechingEnv = false}) {
    var result =
        "${serializer.serializeTypeReactive(context: context, gqType: createListTypeOnSubscription(_getServiceReturnType(method.type), type), reactive: type == GQQueryType.subscription)} ${method.name}(${serializeArgs(method.arguments, argPrefix)}";
    if (injectDataFtechingEnv) {
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
      throw ParseException("You cannot mapTo ${mappedTo.tokenInfo} because it is annotated with $gqSkipOnServer",
          info: mappedTo.tokenInfo);
    }
    return mappedTo.token;
  }

  String serializeArgs(List<GQArgumentDefinition> args, [String? prefix]) {
    return """
${args.map((a) => serializeArg(a)).map((e) {
      if (prefix != null) {
        return "$prefix $e";
      }
      return e;
    }).join(", ")}
"""
        .trim();
  }

  String serializeArg(GQArgumentDefinition arg) {
    return """
final ${serializer.serializeType(arg.type, false)} ${arg.tokenInfo}
"""
        .trim();
  }

  String serializeMappingMethod(GQSchemaMapping mapping, String serviceInstanceName, GQToken context) {
    if (mapping.forbid && generateSchema) {
      return "";
    }
    if (mapping.forbid) {
      context.addImport(SpringImports.gqlGraphQLException);
      final statement = """
throw new GraphQLException("Access denied to field '${mapping.type.tokenInfo}.${mapping.field.name}'");
"""
          .trim();
      return """
${serializeMappingImplMethodHeader(mapping, context)} {
${statement.ident()}
}
  """;
    }

    if (mapping.identity) {
      return serializeIdentityMapping(mapping, context);
    }

    final statement = """
return $serviceInstanceName.${mapping.key}(value);
"""
        .trim();
    return """
${serializeMappingImplMethodHeader(mapping, context)} {
${statement.ident()}
}""";
  }

  String _getAnnotation(GQSchemaMapping mapping, GQToken context) {
    if (mapping.batch) {
      context.addImport(SpringImports.batchMapping);

      return """
@BatchMapping(typeName="${mapping.type.tokenInfo}", field="${mapping.field.name}")
      """
          .trim();
    } else {
      context.addImport(SpringImports.schemaMapping);
      return """
@SchemaMapping(typeName="${mapping.type.tokenInfo}", field="${mapping.field.name}")
"""
          .trim();
    }
  }

  String serializeIdentityMapping(GQSchemaMapping mapping, GQToken context) {
    var annotation = _getAnnotation(mapping, context);
    final type = serializer.serializeTypeReactive(context: context, gqType: mapping.field.type, reactive: false);
    final String returnType;
    if (mapping.batch) {
      returnType = "List<${convertPrimitiveToBoxed(type)}>";
    } else {
      returnType = type;
    }

    var result = """public ${returnType} ${mapping.key}($returnType value) { return value; }""";
    return """
$annotation
$result
""";
  }

  String _getReturnType(GQSchemaMapping mapping, GQToken context) {
    if (mapping.batch) {
      var keyType = serializer.serializeType(_getServiceReturnType(GQType(mapping.type.tokenInfo, false)), false);
      if (keyType == "Object") {
        keyType = "?";
      }
      context.addImport(JavaImports.map);
      return """
Map<${convertPrimitiveToBoxed(keyType)}, ${convertPrimitiveToBoxed(serializer.serializeType(mapping.field.type, false))}>
      """
          .trim();
    } else {
      return serializer.serializeTypeReactive(context: context, gqType: mapping.field.type, reactive: false);
    }
  }

  String _getMappingArgument(GQSchemaMapping mapping) {
    var argType = serializer.serializeType(_getServiceReturnType(GQType(mapping.type.tokenInfo, false)), false);
    if (mapping.batch) {
      return "List<${convertPrimitiveToBoxed(argType)}> value";
    } else {
      return "${argType} value";
    }
  }

  String serializeMappingImplMethodHeader(GQSchemaMapping mapping, GQToken context,
      {bool skipAnnotation = false, bool skipQualifier = false}) {
    var result = "${_getReturnType(mapping, context)} ${mapping.key}(${_getMappingArgument(mapping)})";

    if (!skipQualifier) {
      result = "public $result";
    }
    if (skipAnnotation) {
      return result;
    }
    return """
${_getAnnotation(mapping, context)}
$result
"""
        .trim();
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
    return "@$result";
  }
}
