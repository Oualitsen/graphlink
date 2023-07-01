// GENERATED CODE - DO NOT MODIFY BY HAND.

// ignore_for_file: camel_case_types, constant_identifier_names, unused_import, non_constant_identifier_names

import 'enums.gq.dart';
import 'inputs.gq.dart';
import 'types.gq.dart';
import 'dart:convert';
import 'package:retrofit_graphql/retrofit_graphql.dart';



    class Queries {
        final GQHttpClientAdapter _adapter;
        Queries(this._adapter);
        Future<GetDriversResponse> getDrivers({required String id}) {
        var operationName = "getDrivers";
        var query = """
query getDrivers (\$id: ID!)  {
  getDriverById (id: \$id)
  {
    ... DriverFragment
  }
} 
fragment DriverFragment on Driver  {
  firstName  lastName  id  cars {
    year
  }
}
        """;

        var variables = {
          'id': id
        };
        
        var payload = GQPayload(query: query, operationName: operationName, variables: variables);
            return _adapter(payload.toString()).asStream().map((response) {
          Map<String, dynamic> result = jsonDecode(response);
          if (result.containsKey("errors")) {
            throw result["errors"].map((error) => GraphQLError.fromJson(error)).toList();
          }
          var data = result["data"];
          return GetDriversResponse.fromJson(data);
      }).first;

      }

}
class Mutations {
        final GQHttpClientAdapter _adapter;
        Mutations(this._adapter);
        

}
class Subscriptions {
                final SubscriptionHandler _handler;
        
        Subscriptions(WebSocketAdapter adapter) : _handler = SubscriptionHandler(adapter);
        Stream<WatchDriverResponse> watchDriver({required String id}) {
        var operationName = "watchDriver";
        var query = """
subscription watchDriver (\$id: ID!)  {
  watchDriver (id: \$id)
  {
    ... myFrag
  }
} 
fragment myFrag on Driver  {
  id  firstName  cars {
    ... carFrag
  }
}
fragment carFrag on Car  {
  model  year
}
        """;

        var variables = {
          'id': id
        };
        
        var payload = GQPayload(query: query, operationName: operationName, variables: variables);
              return _handler.handle(payload)
        .map((e) => WatchDriverResponse.fromJson(e));
    
      }

}

class GQClient {
  final Queries queries;
  final Mutations mutations;
  final Subscriptions subscriptions;
  GQClient(GQHttpClientAdapter adapter, WebSocketAdapter wsAdapter)
      : queries = Queries(adapter),
        mutations = Mutations(adapter),
        subscriptions = Subscriptions(wsAdapter);
}
