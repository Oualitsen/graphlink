import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/dart_serializable.dart';
import 'package:retrofit_graphql/src/model/gq_fragment.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';

class GQGraphqlService implements DartSerializable {
  final List<GQQueryDefinition> queries;

  GQGraphqlService(this.queries);

  @override
  String toDart(GQGrammar grammar) {
    return """
import 'dart:convert';
import 'package:retrofit_graphql/retrofit_graphql.dart';


final _fragmMap = <String, String>{};

String _getFragment(String fragName) {
  return _fragmMap[fragName]!;
}

    ${GQQueryType.values.map((e) => generateQueriesClassByType(e, grammar)).join("\n")}

class GQClient {
  
  ${grammar.hasQueries ? 'final Queries queries;' : ''}
  ${grammar.hasMutations ? 'final Mutations mutations;' : ''}
  ${grammar.hasSubscriptions ? 'final Subscriptions subscriptions;' : ''}
  GQClient(Future<String> Function(String payload) adapter${grammar.hasSubscriptions ? ', WebSocketAdapter wsAdapter' : ''})
      :${[
      grammar.hasQueries ? 'queries = Queries(adapter)' : '',
      grammar.hasMutations ? ' mutations = Mutations(adapter)' : '',
      grammar.hasSubscriptions ? 'subscriptions = Subscriptions(wsAdapter)' : '',
    ].where((element) => element.isNotEmpty).join(", ")} {
      
${grammar.fragments.values.map((value) => "_fragmMap['${value.token}'] = '${value.serialize()}';").toList().join("\n")}
${grammar.allFieldsFragments.values.map((e) => e.fragment).map((value) => "_fragmMap['${value.token}'] = '${value.serialize()}';").toList().join("\n")}
       
      
    }
        
}
    """
        .trim();
  }

  String generateQueriesClassByType(GQQueryType type, GQGrammar g) {
    var queryList = queries.where((element) => element.type == type && g.hasQueryType(type)).toList();
    if (queryList.isEmpty) {
      return "";
    }
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
        return "final Future<String> Function(String payload) _adapter;";
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
        const operationName = "${def.token}";
        final fragsValues = ${def.fragments(g).isEmpty ? '"";' : '[${def.fragments(g).map((e) => '"${e.token}"').toList().join(", ")}].map((fragName) => _getFragment(fragName)).join(" ");'}
        final query = \"\"\"${def.serialize()}\$fragsValues\"\"\";

        final variables = <String, dynamic>{
          ${def.arguments.map((e) => "'${e.dartArgumentName}': ${serializeArgumentValue(g, def, e.token)}").toList().join(", ")}
        };
        
        final payload = GQPayload(query: query, operationName: operationName, variables: variables);
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

  String serializeArgumentValue(GQGrammar g, GQQueryDefinition def, String argName) {
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
