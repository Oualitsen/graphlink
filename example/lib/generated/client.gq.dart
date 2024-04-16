// GENERATED CODE - DO NOT MODIFY BY HAND.

// ignore_for_file: camel_case_types, constant_identifier_names, unused_import, non_constant_identifier_names

import 'enums.gq.dart';
import 'inputs.gq.dart';
import 'types.gq.dart';
import 'dart:convert';
import 'package:retrofit_graphql/retrofit_graphql.dart';



    class Queries {
        final Future<String> Function(String payload) _adapter;
        Queries(this._adapter);
        Future<GetUserResponse> getUser({required String id, required bool? client}) {
        const operationName = "getUser";
        const query = """query getUser(\$id:ID!,\$client:Boolean){getUser(id:\$id,client:\$client){... on Driver  {firstName lastName __typename}  ... on Client  {lastUpdate firstName __typename}}}""";

        final variables = <String, dynamic>{
          'id': id, 'client': client
        };
        
        final payload = GQPayload(query: query, operationName: operationName, variables: variables);
            return _adapter(payload.toString()).asStream().map((response) {
          Map<String, dynamic> result = jsonDecode(response);
          if (result.containsKey("errors")) {
            throw result["errors"].map((error) => GraphQLError.fromJson(error)).toList();
          }
          var data = result["data"];
          return GetUserResponse.fromJson(data);
      }).first;

      }

}

class Subscriptions {
                final SubscriptionHandler _handler;
        
        Subscriptions(WebSocketAdapter adapter) : _handler = SubscriptionHandler(adapter);
        Stream<WatchDriverResponse> watchDriver({required String id}) {
        const operationName = "watchDriver";
        const query = """subscription watchDriver(\$id:ID!){watchDriver(id:\$id){...myFrag}}fragment myFrag on Driver{id firstName cars{...carFrag}}
fragment carFrag on Car{model year}""";

        final variables = <String, dynamic>{
          'id': id
        };
        
        final payload = GQPayload(query: query, operationName: operationName, variables: variables);
              return _handler.handle(payload)
        .map((e) => WatchDriverResponse.fromJson(e));
    
      }

}

class GQClient {
  
  final Queries queries;
  
  final Subscriptions subscriptions;
  GQClient(Future<String> Function(String payload) adapter, WebSocketAdapter wsAdapter)
      :queries = Queries(adapter), subscriptions = Subscriptions(wsAdapter);
        
}
