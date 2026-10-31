import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/class_input.dart';
import 'real_server_adapter.dart';

/// End-to-end coverage for a target-language keyword (`class`) used in several
/// schema positions: a query operation name, a top-level query argument, a type
/// field, and an input field. The generated identifiers are sanitized
/// (`class_`) while the GraphQL wire name stays `class`, so the request must
/// still round-trip against the real Spring server.
void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  test('keyword query + keyword argument round-trips against the server',
      () async {
    final res = await client.queries.class_(class_: 'abc');
    expect(res.class_.id, equals('abc'));
    // server resolver returns `class-of-<arg>` in the keyword `class` field.
    expect(res.class_.class_, equals('class-of-abc'));
  });

  test('keyword input field round-trips through a mutation', () async {
    final res = await client.mutations.makeClass(
      input: const ClassInput(class_: 'hello'),
    );
    expect(res.makeClass.id, equals('made'));
    expect(res.makeClass.class_, equals('hello'));
  });
}
