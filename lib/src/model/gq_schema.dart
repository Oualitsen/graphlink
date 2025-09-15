import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQSchema extends GQToken {
  final String query;
  final String mutation;
  final String subscription;

   final Set<String> queryNamesSet;

  GQSchema(super.tokenInfo, {
    this.query = "Query",
    this.mutation = "Mutation",
    this.subscription = "Subscription",
  }): queryNamesSet = {query, mutation, subscription};

  factory GQSchema.fromList(TokenInfo tokenInfo, List<String> list) {
    String query = find("query", list) ?? "Query";
    String mutation = find("mutation", list) ?? "Mutation";
    String subscription = find("subscription", list) ?? "Subscription";
    return GQSchema(tokenInfo, query: query, mutation: mutation, subscription: subscription);
  }

   String getByQueryType(GQQueryType type) {
    switch (type) {
      case GQQueryType.query:
        return query;
      case GQQueryType.mutation:
        return mutation;
      case GQQueryType.subscription:
        return subscription;
    }
  }

  static String? find(String prefix, List<String> list) {
    var elem = list.where((element) => element.startsWith(prefix)).toList();
    return elem.isEmpty ? null : elem.first.split("-")[1].trim();
  }
  
}
