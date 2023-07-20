import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/dart_serializable.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/utils.dart';

class GQGraphqlService implements DartSerializable {
  final List<GQQueryDefinition> queries;

  GQGraphqlService(this.queries);

  @override
  String toDart(GQGrammar grammar) {
    return """
import 'dart:convert';
import 'package:retrofit_graphql/retrofit_graphql.dart';



    ${GQQueryType.values.map((e) => generateQueriesClassByType(e, grammar)).join("\n")}

class GQClient {
  final Queries queries;
  final Mutations mutations;
  final Subscriptions subscriptions;
  GQClient(GQHttpClientAdapter adapter, WebSocketAdapter wsAdapter)
      : queries = Queries(adapter),
        mutations = Mutations(adapter),
        subscriptions = Subscriptions(wsAdapter);
}
    """
        .trim();
  }

  String generateQueriesClassByType(GQQueryType type, GQGrammar g) {
    var queryList = queries.where((element) => element.type == type).toList();

    return """
      class ${classNameFromType(type)} {
        ${declareAdapter(type)}
        ${classNameFromType(type)}${declareConstructorArgs(type)}
        ${queryList.map((e) => queryToMethod(e, g)).join("\n")}

}

    """
        .trim();
  }

  String declareConstructorArgs(GQQueryType type) {
    if (type == GQQueryType.subscription) {
      return "(WebSocketAdapter adapter) : _handler = SubscriptionHandler(adapter);";
    }
    return "(this._adapter);";
  }

  String declareAdapter(GQQueryType type) {
    switch (type) {
      case GQQueryType.query:
      case GQQueryType.mutation:
        return "final GQHttpClientAdapter _adapter;";
      case GQQueryType.subscription:
        return """
        final SubscriptionHandler _handler;
        """;
    }
  }

  String classNameFromType(GQQueryType type) {
    switch (type) {
      case GQQueryType.query:
        return "Queries";
      case GQQueryType.mutation:
        return "Mutations";
      case GQQueryType.subscription:
        return "Subscriptions";
    }
  }

  String queryToMethod(GQQueryDefinition def, GQGrammar g) {
    return """
      ${returnTypeByQueryType(def, g)} ${def.token}(${generateArgs(def, g)}) {
        var operationName = "${def.token}";
        var query = \"\"\"
${formatUnformattedGraphQL(def.serialize())} 
${def.fragments(g).map((e) => e.serialize()).toList().join("\n")}
        \"\"\";

        var variables = <String, dynamic>{
          ${def.arguments.map((e) => "'${e.dartArgumentName}': ${serializeArgumentValue(g, def, e.token)}").toList().join(", ")}
        };
        
        var payload = GQPayload(query: query, operationName: operationName, variables: variables);
        ${generateAdapterCall(def)}
      }
    """
        .trim();
  }

  String generateAdapterCall(GQQueryDefinition def) {
    if (def.type == GQQueryType.subscription) {
      return """
      return _handler.handle(payload)
        .map((e) => ${def.getGeneratedTypeDefinition().token}.fromJson(e));
    """;
    }
    return """
    return _adapter(payload.toString()).asStream().map((response) {
          Map<String, dynamic> result = jsonDecode(response);
          if (result.containsKey("errors")) {
            throw result["errors"].map((error) => GraphQLError.fromJson(error)).toList();
          }
          var data = result["data"];
          return ${def.getGeneratedTypeDefinition().token}.fromJson(data);
      }).first;
""";
  }

  String serializeArgumentValue(
      GQGrammar g, GQQueryDefinition def, String argName) {
    var arg = def.findByName(argName);
    return callToJson(arg.dartArgumentName, arg.type, g);
  }

  String callToJson(String argName, GQType type, GQGrammar g) {
    if (g.inputTypeRequiresProjection(type)) {
      if (type is GQListType) {
        return "$argName${type.nullableTextDart}.map((e) => ${callToJson("e", type.type, g)}).toList()";
      } else {
        return "$argName${type.nullableTextDart}.toJson()";
      }
    }
    if (g.enums.containsKey(type.token)) {
      if (type is GQListType) {
        return "$argName${type.nullableTextDart}.map((e) => ${callToJson("e", type.type, g)}).toList()";
      } else {
        return "$argName${type.nullableTextDart}.name";
      }
    } else {
      return argName;
    }
  }

  String generateArgs(GQQueryDefinition def, GQGrammar g) {
    if (def.arguments.isEmpty) {
      return "";
    }
    var result = def.arguments
        .map((e) => "${e.type.toDartType(g, false)} ${e.dartArgumentName}")
        .map((e) => "required $e")
        .toList()
        .join(", ");
    return "{$result}";
  }

  String returnTypeByQueryType(GQQueryDefinition def, GQGrammar g) {
    var gen = def.getGeneratedTypeDefinition();

    if (def.type == GQQueryType.subscription) {
      return "Stream<${gen.token}>";
    }
    return "Future<${gen.token}>";
  }
}
