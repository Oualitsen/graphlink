import 'dart:io';

import 'package:graphlink_server_integration_tests_dart_upload_client/generated/graphlink.dart';

final _port = Platform.environment['SERVER_PORT'] ?? '9996';

String get httpUrl => 'http://localhost:$_port/graphql';

GraphLinkClient newClient() => GraphLinkClient.withHttp(url: httpUrl);
