import 'enums.dart';
import 'inputs.dart';
import 'types.dart';
import 'dart:convert';
import 'package:parser/graphql_parser/model/gq_graphql_service.dart';

typedef GQHttpClientAdapter = Future<String> Function(String payload);

    class Queries {
        final GQHttpClientAdapter adapter;
        Queries(this.adapter);
        Future<HemodialysisGroupListResponse> hemodialysisGroupList({required PageInfo pageInfo}) {
        var operationName = "hemodialysisGroupList";
        var fragments = """  """;
        var query = """
        query hemodialysisGroupList (\$pageInfo: PageInfo!)  {
        hemodialysisGroupList (pageInfo: \$pageInfo) 
      {
      id  designation 
    }
      }
     $fragments
        """;

        var variables = {
          'pageInfo': pageInfo.toJson()
        };
        
        var payload = PayLoad(query: query, operationName: operationName, variables: variables);
        return adapter(payload.toString()).asStream().map((response) {
      Map<String, dynamic> result = jsonDecode(response);
      if (result.containsKey("errors")) {
        throw result["errors"];
      }
      var data = result["data"];
      return HemodialysisGroupListResponse.fromJson(data);
      
    }).first;
        
      }

}
class Mutations {
        final GQHttpClientAdapter adapter;
        Mutations(this.adapter);
        Future<SavePositionResponse> savePosition({required PositionInput input, required HemodialysisGroupInput ginput}) {
        var operationName = "savePosition";
        var fragments = """  """;
        var query = """
        mutation savePosition (\$input: PositionInput!, \$ginput: HemodialysisGroupInput!)  {
        savePosition (position: \$input) 
      {
      startTime 
    }
saveHemodialysisGroup (input: \$ginput) 
      {
      id 
    }
      }
     $fragments
        """;

        var variables = {
          'input': input.toJson(), 'ginput': ginput.toJson()
        };
        
        var payload = PayLoad(query: query, operationName: operationName, variables: variables);
        return adapter(payload.toString()).asStream().map((response) {
      Map<String, dynamic> result = jsonDecode(response);
      if (result.containsKey("errors")) {
        throw result["errors"];
      }
      var data = result["data"];
      return SavePositionResponse.fromJson(data);
      
    }).first;
        
      }

}
class Subscriptions {
        final GQHttpClientAdapter adapter;
        Subscriptions(this.adapter);
        

}

class GQClient {
  final GQHttpClientAdapter adapter;
  late final Queries queries;
  late final Mutations mutations;
  late final Subscriptions subscriptions;
  GQClient(this.adapter) {
    queries = Queries(adapter);
    mutations = Mutations(adapter);
    subscriptions = Subscriptions(adapter);
  }
}
