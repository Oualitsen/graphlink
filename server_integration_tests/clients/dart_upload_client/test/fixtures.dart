import 'package:graphlink_server_integration_tests_dart_upload_client/generated/graphlink.dart';

const _port = 9996;

String get httpUrl => 'http://localhost:$_port/graphql';

GraphLinkClient newClient() => GraphLinkClient.withHttp(url: httpUrl);
