import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_interface.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_service.dart';
import 'package:retrofit_graphql/src/model/gq_shcema_mapping.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
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
  

  SpringServerSerializer(this.grammar, {this.defaultRepositoryBase, JavaSerializer? javaSerializer, this.generateSchema = false})
      : assert(grammar.mode == CodeGenerationMode.server,
            "Gramar must be in code generation mode = `CodeGenerationMode.server`"),
        serializer = javaSerializer ?? JavaSerializer(grammar);

  List<String> serializeServices() {
    return grammar.services.values.map((service) {
      return serializeService(service);
    }).toList();
  }

  String serializeController(GQService service, {bool injectDataFtechingEnv = false}) {
    // get schema mappings by service name
    final controllerName = "${service.name}Controller";
    final sericeInstanceName = service.name.firstLow;
    var mappings = grammar.schemaMappings.values.where((sm) => sm.serviceName == service.name).toList();
    var mappingSerial = mappings
        .map((m) {
          return serializeMappingMethod(m, sericeInstanceName);
        })
        .toList()
        .join("\n");
        
    var result = """
@org.springframework.stereotype.Controller
public class $controllerName {
${'private final ${service.name} $sericeInstanceName;'.ident()}
${serializer.generateContructor(controllerName, [
              GQField(
                  name: sericeInstanceName.toToken(), type: GQType(service.name.toToken(), false), arguments: [], directives: [])
            ], "public").ident()}

${service.getMethodNames().map((n) {
              var method = service.getMethod(n)!;
              var type = service.getMethodType(n)!;
              return serializehandlerMethod(type, method, sericeInstanceName,
                  injectDataFtechingEnv: injectDataFtechingEnv, qualifier: "public");
            }).toList().join("\n").ident()}
"""
        .trim();
    if (mappings.isNotEmpty) {
      return """
$result
${mappingSerial.ident()}
}
"""
          .trim();
    } else {
      return """
$result
}
"""
          .trim();
    }
  }

  String serializehandlerMethod(GQQueryType type, GQField method, String sericeInstanceName,
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
    var result = """
${getAnnotationByShcemaType(type)}
${qualifier == null ? '' : "${qualifier} "}${serializeMethodDeclaration(method, type, argPrefix: "@org.springframework.graphql.data.method.annotation.Argument", injectDataFtechingEnv: injectDataFtechingEnv)} {
${statement.ident()}
}"""
        .trim();
        if(decorators.isNotEmpty) {
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

  String serializeRepository(GQInterfaceDefinition interface) {
    // find the _ field and ignore it
    interface.getSerializableFields(grammar.mode).where((f) => f.name.token == "_").forEach((f) {
      f.addDirective(GQDirectiveValue(gqSkipOnServer.toToken(), [], [], generated: true));
    });

    var dec = GQDirectiveValue.createGqDecorators(
        decorators: ["@org.springframework.stereotype.Repository"], applyOnClient: false);
    interface.addDirective(dec);
    var gqRepo = interface.getDirectiveByName(gqRepository)!;
    var fqcn = gqRepo.getArgValueAsString(gqFQCN) ?? "org.springframework.data.jpa.repository.JpaRepository";
    var id = gqRepo.getArgValueAsString(gqIdType);
    var ontType = gqRepo.getArgValueAsString(gqType)!;

    interface.parents.add(GQInterfaceDefinition(
        name: "$fqcn<$ontType, ${id}>".toToken(),
        nameDeclared: false,
        fields: [],
        parentNames: {},
        directives: [],
        interfaceNames: {}));

    return serializer.serializeInterface(interface, getters: false);
  }

  String serializeService(GQService service, {bool injectDataFtechingEnv = false}) {
    // get schema mappings by service name

    var mappings = grammar.schemaMappings.values
        .where((sm) => !sm.forbid)
        .where((sm) => !sm.identity)
        .where((sm) => sm.serviceName == service.name)
        .toList();
    var mappingSerial = """
${mappings.map((m) {
              return "${serializeMappingImplMethodHeader(m, skipAnnotation: true, skipQualifier: true)};";
            }).toList().join("\n")}
 """
        .trim();
    var result = """
public interface ${service.name} {

${service.getMethodNames().map((n) {
              var method = service.getMethod(n)!;
              var type = service.getMethodType(n)!;
              return "${serializeMethodDeclaration(method, type, injectDataFtechingEnv: injectDataFtechingEnv)};";
            }).toList().join("\n").ident()}
"""
        .trim();
    if (mappings.isNotEmpty) {
      return """
$result
${'// schema mappings and batch mapping'.ident()}
${mappingSerial.ident()}
}
"""
          .trim();
    } else {
      return """
$result
}
""";
    }
  }

  String serializeMethodDeclaration(GQField method, GQQueryType type,
      {String? argPrefix, bool injectDataFtechingEnv = false}) {
    var result =
        "${serializer.serializeTypeReactive(gqType: createListTypeOnSubscription(_getServiceReturnType(method.type), type), reactive: type == GQQueryType.subscription)} ${method.name}(${serializeArgs(method.arguments, argPrefix)}";
    if (injectDataFtechingEnv) {
      var inject = "graphql.schema.DataFetchingEnvironment dataFetchingEnvironment";
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

    var returnType = grammar.getType(token);

    var skipOnserverDir = returnType.getDirectiveByName(gqSkipOnServer);
    if (skipOnserverDir != null) {
      var mapTo = getMapTo(token);

      var rt = GQType(mapTo.toToken(), false);
      if (type is GQListType) {
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

  String getMapTo(String typeName) {
    var type = grammar.getType(typeName);
    var dir = type.getDirectiveByName(gqSkipOnServer);
    if (dir == null) {
      return type.token;
    }
    var mapTo = dir.getArgValueAsString(gqMapTo);
    if (mapTo == null) {
      return "Object";
    }
    var mappedTo = grammar.getType(mapTo);
    if (mappedTo.getDirectiveByName(gqSkipOnServer) != null) {
      throw ParseException("You cannot mapTo ${mappedTo.tokenInfo} because it is annotated with $gqSkipOnServer");
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

  String serializeMappingMethod(GQSchemaMapping mapping, String serviceInstanceName) {
    if(mapping.forbid && generateSchema) {
      return "";
    }
    if (mapping.forbid) {
      final statement = """
throw new graphql.GraphQLException("Access denied to field '${mapping.type.tokenInfo}.${mapping.field.name}'");
"""
          .trim();
      return """
${serializeMappingImplMethodHeader(mapping)} {
${statement.ident()}
}
  """;
    }

    if (mapping.identity) {
      return serializeIdentityMapping(mapping);
    }

    final statement = """
return $serviceInstanceName.${mapping.key}(value);
"""
        .trim();
    return """
${serializeMappingImplMethodHeader(mapping)} {
${statement.ident()}
}""";
  }

  String _getAnnotation(GQSchemaMapping mapping) {
    if (mapping.batch) {
      return """
@org.springframework.graphql.data.method.annotation.BatchMapping(typeName="${mapping.type.tokenInfo}", field="${mapping.field.name}")
      """
          .trim();
    } else {
      return """
@org.springframework.graphql.data.method.annotation.SchemaMapping(typeName="${mapping.type.tokenInfo}", field="${mapping.field.name}")
"""
          .trim();
    }
  }

  String serializeIdentityMapping(GQSchemaMapping mapping) {
    var annotation = _getAnnotation(mapping);
    final type = serializer.serializeTypeReactive(gqType: mapping.field.type, reactive: false);
    final String returnType;
    if (mapping.batch) {
      returnType = "java.util.List<${convertPrimitiveToBoxed(type)}>";
    } else {
      returnType = type;
    }

    var result = """public ${returnType} ${mapping.key}($returnType value) { return value; }""";
    return """
$annotation
$result
""";
  }

  String _getReturnType(GQSchemaMapping mapping) {
    if (mapping.batch) {
      var keyType = serializer.serializeType(_getServiceReturnType(GQType(mapping.type.tokenInfo, false)), false);
      if (keyType == "Object") {
        keyType = "?";
      }
      return """
java.util.Map<${convertPrimitiveToBoxed(keyType)}, ${convertPrimitiveToBoxed(serializer.serializeType(mapping.field.type, false))}>
      """
          .trim();
    } else {
      return serializer.serializeTypeReactive(gqType: mapping.field.type, reactive: false);
    }
  }

  String _getMappingArgument(GQSchemaMapping mapping) {
    var argType = serializer.serializeType(_getServiceReturnType(GQType(mapping.type.tokenInfo, false)), false);
    if (mapping.batch) {
      return "java.util.List<${convertPrimitiveToBoxed(argType)}> value";
    } else {
      return "${argType} value";
    }
  }

  String serializeMappingImplMethodHeader(GQSchemaMapping mapping,
      {bool skipAnnotation = false, bool skipQualifier = false}) {
    var result = "${_getReturnType(mapping)} ${mapping.key}(${_getMappingArgument(mapping)})";

    if (!skipQualifier) {
      result = "public $result";
    }
    if (skipAnnotation) {
      return result;
    }
    return """
${_getAnnotation(mapping)}
$result
"""
        .trim();
  }

  String getAnnotationByShcemaType(GQQueryType queryType) {
    String result;
    switch (queryType) {
      case GQQueryType.query:
        result = "QueryMapping";
        break;
      case GQQueryType.mutation:
        result = "MutationMapping";
        break;
      case GQQueryType.subscription:
        result = "SubscriptionMapping";
        break;
    }
    return "@org.springframework.graphql.data.method.annotation.$result";
  }
}
