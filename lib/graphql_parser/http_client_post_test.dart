import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:parser/generated/gq_client.dart';
import 'package:parser/generated/inputs.dart';
import 'package:parser/graphql_parser/model/gq_graphql_service.dart';

void main() async {
  // PayLoad payLoad = PayLoad(
  //   operationName: "savePosition",
  //   query:
  //       "mutation savePosition(\$a: String, \$b:Long){\n  savePosition(position:{designation:\$a startTime:\$b endTime :45}){\n    startTime\n  }\n}",
  //   variables: {'a': 'pooo', 'b': '12'},
  // );
  // var url1 = Uri.http('localhost:8080', '/graphql');
  // print("url $url1");
  // http.post(url1,
  //     body: jsonEncode(payLoad.toJson()),
  //     headers: {"Content-Type": "application/json"}).then((response) {
  //   print("object ${response.request?.url}");
  //   if (response.statusCode == 200) {
  //     print("###### reponse.body = ${response.body}");
  //     // var jsonResponse =
  //     //     convert.jsonDecode(response.body) as Map<String, dynamic>;
  //     // var itemCount = jsonResponse['totalItems'];
  //     // print('Number of books about http: $itemCount.');
  //   } else {
  //     print('Request failed with status: ${response.statusCode}.');
  //   }
  // });

  var c = GQClient((text) => http
      .post(Uri.http('localhost:8080', '/graphql'),
          body: text, headers: {"Content-Type": "application/json"})
      .asStream()
      .map((event) => event.body)
      .first);

  var res = await c.mutations.savePosition(
      input: PositionInput(
        id: null,
        designation: "designation",
        startTime: 15,
        endTime: 30,
      ),
      ginput: HemodialysisGroupInput(
        id: null,
        creationDate: null,
        lastUpdate: null,
        code: "code",
        designation: "designation",
        daysOfWeek: [],
      ));

  print(
      "res mutation ======================================= ${jsonEncode(res.toJson())}");

  var resQuery = await c.queries
      .hemodialysisGroupList(pageInfo: PageInfo(page: 0, size: 10));
  print(
      "res mutation ======================================= ${jsonEncode(resQuery.toJson())}");
}
