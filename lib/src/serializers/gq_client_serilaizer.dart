import 'package:retrofit_graphql/src/model/gq_queries.dart';

abstract class ClientSerilaizer {
  
  String generateClient();

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
}
