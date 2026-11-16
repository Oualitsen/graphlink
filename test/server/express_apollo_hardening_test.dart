import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _withSubscription = '''
  type Query { ping: Boolean! }
  type Subscription { pinged: Boolean! }
''';

const _withoutSubscription = 'type Query { ping: Boolean! }';

String _entryPoint(String schema) {
  final parser = GLParser(mode: CodeGenerationMode.server)..parse(schema);
  return ExpressApolloServerSerializer(
    parser,
    TypeScriptSerializer(parser, importPrefix: ''),
    ExpressApolloServerConfig(),
  ).serializeEntryPoint();
}

void main() {
  for (final entry in {'with subscriptions': _withSubscription, 'without subscriptions': _withoutSubscription}.entries) {
    group('entry point ${entry.key}', () {
      late String out;
      setUpAll(() => out = _entryPoint(entry.value));

      test('hides stack traces', () => expect(out, contains('includeStacktraceInErrorResponses: false')));
      test('limits query depth over HTTP', () => expect(out, contains('queryDepthGuard(maxQueryDepth)')));
      test('answers body-parser failures as GraphQL errors', () => expect(out, contains('app.use(graphLinkErrorHandler)')));
      test('exposes maxQueryDepth', () => expect(out, contains('maxQueryDepth?: number;')));
    });
  }

  test('subscriptions are depth-limited and syntax errors become error messages', () {
    expect(_entryPoint(_withSubscription), contains('onSubscribe: (_ctx, message) => subscribeErrors('));
  });

  test('no WebSocket guard without subscriptions', () {
    expect(_entryPoint(_withoutSubscription), isNot(contains('subscribeErrors')));
  });
}
