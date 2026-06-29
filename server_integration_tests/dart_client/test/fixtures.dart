import 'dart:io';
import 'package:graphlink_server_integration_tests_dart_client/generated/graphlink.dart';

int get _port => int.tryParse(Platform.environment['SERVER_PORT'] ?? '') ?? 9997;

String get httpUrl => 'http://localhost:$_port/graphql';
String get wsUrl => 'ws://localhost:$_port/graphql';

DefaultGraphLinkWebSocketAdapter newWsAdapter() =>
    DefaultGraphLinkWebSocketAdapter(url: wsUrl, reconnect: true, protocols: ['graphql-transport-ws']);

GraphLinkClient newClient() => GraphLinkClient(
      adapter: GraphLinkDioAdapter(url: httpUrl).call,
      wsAdapter: newWsAdapter(),
    );
