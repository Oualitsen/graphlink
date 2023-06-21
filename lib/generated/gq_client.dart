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
      ... ProductFragment 
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
      return CreateProductResponse.fromJson(data);
      
    }).first;
        
      }
Future<DeleteProductResponse> deleteProduct({required String id, required int? id2}) {
        var operationName = "deleteProduct";
        var fragments = """  """;
        var query = """
        mutation deleteProduct (\$id: ID!, \$id2: Int)  {
        deleteProduct (id: \$id) 
      {
      id  name 
    }

deleteProduct2 (id: \$id2) 
      
      }
     $fragments
        """;

        var variables = {
          'id': id, 'id2': id2
        };
        
        var payload = PayLoad(query: query, operationName: operationName, variables: variables);
        return adapter(payload.toString()).asStream().map((response) {
      Map<String, dynamic> result = jsonDecode(response);
      if (result.containsKey("errors")) {
        throw result["errors"];
      }
      var data = result["data"];
      return DeleteProductResponse.fromJson(data);
      
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
