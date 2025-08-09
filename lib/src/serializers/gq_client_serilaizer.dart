import 'package:retrofit_graphql/src/model/gq_queries.dart';

abstract class ClientSerilaizer {
  
  String generateClient();

   String classNameFromType(GQQueryType type) {
    switch (type) {
      case GQQueryType.query:
        return "GQQueries";
      case GQQueryType.mutation:
        return "GQMutations";
      case GQQueryType.subscription:
        return "GQSubscriptions";
    }
  }
}
