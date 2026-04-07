import 'package:graphlink/src/main.dart' as graphlink;

/// Entry point for all glupload example code generation.
///
/// Usage (from this directory):
///   dart run main.dart --config dart_dio_app/config.json
///   dart run main.dart --config dart_http_app/config.json
///   dart run main.dart --config java_okhttp_app/config.json
///   dart run main.dart --config java_java11_client_app/config.json
///   dart run main.dart --config spring_app/config.json
///
/// Or use the Makefile targets:
///   make dart-dio
///   make dart-http
///   make java-okhttp
///   make java-java11
///   make spring
///   make all
Future<void> main(List<String> args) async {
  await graphlink.main(args);
}
