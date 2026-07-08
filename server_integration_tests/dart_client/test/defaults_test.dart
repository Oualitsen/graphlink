import 'package:test/test.dart';
import 'package:graphlink_server_integration_tests_dart_client/generated/graphlink.dart';
import 'fixtures.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  test('input-field defaults applied when omitted', () async {
    final c = (await client.queries.resolveConfig(input: const ConfigInput()))
        .resolveConfig;
    expect(c.pageSize, 25);
    expect(c.ratio, 1.5);
    expect(c.sort, 'asc');
    expect(c.verbose, false);
    expect(c.priority, Priority.medium);
    expect(c.tags, ['default', 'seed']);
    expect(c.empties, isEmpty);
    expect(c.note, isNull);
  });

  test('explicit values override defaults', () async {
    final c = (await client.queries.resolveConfig(
      input: const ConfigInput(
          pageSize: 5, sort: 'desc', priority: Priority.high, note: 'x'),
    ))
        .resolveConfig;
    expect(c.pageSize, 5);
    expect(c.sort, 'desc');
    expect(c.priority, Priority.high);
    expect(c.note, 'x');
  });

  test('nested object arg default merges with field defaults', () async {
    final range = (await client.queries.resolveRange()).resolveRange;
    expect(range.min, 5); // arg default { min: 5 }
    expect(range.max, 100); // RangeInput field default
  });

  test('argument-level scalar defaults', () async {
    expect((await client.queries.greet()).greet, 'Hi world!');
    expect((await client.queries.greet(name: 'Bob', times: 2)).greet,
        'Hi Bob!Hi Bob!');
  });

  test('enum argument: passed value round-trips; omitted uses default HIGH',
      () async {
    expect((await client.queries.echoPriority(level: Priority.low)).echoPriority,
        Priority.low);
    expect((await client.queries.echoPriority()).echoPriority, Priority.high);
  });
}
