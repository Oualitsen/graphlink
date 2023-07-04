import 'package:retrofit_graphql/retrofit_graphql.dart';
import 'package:retrofit_graphql_example/generated/client.gq.dart';
import 'package:http/http.dart' as http;

void main(List<String> args) {
  const wsUrl = "ws://localhost:8080/graphql";
  const url = "http://localhost:8080/graphql";
  var wsAdapter = WebSocketChannelAdapter(wsUrl);

  fn(payload) => http
      .post(Uri.parse(url),
          body: payload, headers: {"Content-Type": "application/json"})
      .asStream()
      .map((response) => response.body)
      .first;

  var client = GQClient(fn, wsAdapter);

  client.subscriptions.watchDriver(id: "azul").listen((event) {
    print(
        "hello world ${event.watchDriver.id} ${event.watchDriver.firstName} ${event.watchDriver.cars.length}");
  });
}
