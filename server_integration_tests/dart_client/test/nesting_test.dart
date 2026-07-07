import 'package:test/test.dart';
import 'package:graphlink_server_integration_tests_dart_client/generated/graphlink.dart';
import 'fixtures.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  test('enum list depths 1 / 2 / 3', () async {
    expect((await client.queries.colors1()).colors1,
        [Color.red, Color.green, Color.blue]);
    expect((await client.queries.colors2()).colors2, [
      [Color.red],
      [Color.green, Color.blue],
    ]);
    expect((await client.queries.colors3()).colors3, [
      [
        [Color.red],
      ],
    ]);
  });

  test('type list depths 1 / 2 / 3', () async {
    final b1 = (await client.queries.boxes1()).boxes1;
    expect(b1, hasLength(2));

    final b2 = (await client.queries.boxes2()).boxes2;
    expect(b2, hasLength(2));

    final b3 = (await client.queries.boxes3()).boxes3;
    expect(b3!.first!.first!.first!.id, 'b1');
  });

  test('interface list depths 1 / 2 / 3', () async {
    final s1 = (await client.queries.shapes1()).shapes1;
    expect(s1.map((s) => s.kind), containsAll(['circle', 'square']));

    final s3 = (await client.queries.shapes3()).shapes3;
    expect(s3.first.first.first.kind, isNotNull);
  });
}
