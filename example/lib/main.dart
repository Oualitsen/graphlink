import 'package:retrofit_graphql_example/generated/client.gq.dart';
import 'package:http/http.dart' as http;

void main(List<String> args) {
  const wsUrl = "ws://localhost:8080/graphql";
  const url = "http://localhost:8080/graphql";
  var wsAdapter = WebSocketChannelAdapter(wsUrl);

  fn(payload, opName) => http
      .post(Uri.parse(url),
          body: payload, headers: {"Content-Type": "application/json"})
      .asStream()
      .map((response) => response.body)
      .first;

   GQClient(fn, wsAdapter);
  
  // client.queries.getDriver3().then((value) => value.data);
/*

  client.queries
      .getUser(id: "test", client: true)
      .asStream()
      .map((event) => event.getUser)
      .first
      .then((value) {
    // print("isDriver => ${value is Client}");
    // print("go response = ${value.runtimeType}");
  });
  client.queries
      .getUser(id: "test", client: false)
      .asStream()
      .map((event) => event.getUser)
      .first
      .then((value) {
    //  print("isDriver => ${value is Driver}");
    //  print("go response = ${value.runtimeType}");
  });
  */
}
