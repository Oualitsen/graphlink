import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

/// Verifies that a query whose field name starts with `_` (e.g. `_count`)
/// produces sanitized Dart identifiers throughout:
///   - method name  : `count_`  (leading _ moved to trailing)
///   - response type: `CountResponse`  (trailing _ stripped before firstUp)
///   - full response: `CountFullResponse`
void main() {
  const schema = '''
    type Query { _count: Int! }
    query _count { _count }
  ''';

  late GLParser g;
  late String client;

  setUp(() {
    g = GLParser(autoGenerateQueries: false);
    g.parse(schema);

    final serializer = DartSerializer(g, importPrefix: '');
    final clientSerializer = DartClientSerializer(g, serializer);
    client = clientSerializer.generateClient().toFileContent();
  });

  test('method name is count_ (leading _ becomes trailing _)', () {
    expect(client, contains('count_('));
    expect(client, isNot(contains('_count(')));
  });

  test('return type is CountResponse (trailing _ stripped before PascalCase)', () {
    expect(client, contains('CountResponse'));
    expect(client, isNot(contains('_countResponse')));
    expect(client, isNot(contains('count_Response')));
  });

  test('full response type is CountFullResponse', () {
    // The generated type definition names are referenced inside the client file.
    expect(client, contains('CountFullResponse'));
    expect(client, isNot(contains('_countFullResponse')));
    expect(client, isNot(contains('count_FullResponse')));
  });

  test('wire name in query string stays _count', () {
    expect(client, contains('_count'));
  });
}
