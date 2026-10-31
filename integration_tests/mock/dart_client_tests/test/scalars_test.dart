import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late GraphLinkClient client;

  setUp(() {
    adapter = MockAdapter();
    client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
  });

  group('non-nullable scalar fields', () {
    setUp(() => adapter.registerData(
          'getAllScalars',
          {'getAllScalars': kAllScalarsNullJson},
        ));

    test('id deserializes to String', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-1');
      expect(res.getAllScalars.id, isA<String>());
      expect(res.getAllScalars.id, equals('scalar-1'));
    });

    test('strVal deserializes to String', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-1');
      expect(res.getAllScalars.strVal, isA<String>());
      expect(res.getAllScalars.strVal, equals('hello world'));
    });

    test('intVal deserializes to int', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-1');
      expect(res.getAllScalars.intVal, isA<int>());
      expect(res.getAllScalars.intVal, equals(42));
    });

    test('floatVal deserializes to double', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-1');
      expect(res.getAllScalars.floatVal, isA<double>());
      expect(res.getAllScalars.floatVal, closeTo(3.14, 0.001));
    });

    test('boolVal deserializes to bool', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-1');
      expect(res.getAllScalars.boolVal, isA<bool>());
      expect(res.getAllScalars.boolVal, isTrue);
    });
  });

  group('nullable scalar fields — null in response', () {
    setUp(() => adapter.registerData(
          'getAllScalars',
          {'getAllScalars': kAllScalarsNullJson},
        ));

    test('nullableStr is null', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-1');
      expect(res.getAllScalars.nullableStr, isNull);
    });

    test('nullableInt is null', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-1');
      expect(res.getAllScalars.nullableInt, isNull);
    });

    test('nullableFloat is null', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-1');
      expect(res.getAllScalars.nullableFloat, isNull);
    });

    test('nullableBool is null', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-1');
      expect(res.getAllScalars.nullableBool, isNull);
    });

    test('nullableId is null', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-1');
      expect(res.getAllScalars.nullableId, isNull);
    });
  });

  group('nullable scalar fields — values present', () {
    setUp(() => adapter.registerData(
          'getAllScalars',
          {'getAllScalars': kAllScalarsPresentJson},
        ));

    test('nullableStr has value', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-2');
      expect(res.getAllScalars.nullableStr, equals('present'));
    });

    test('nullableInt has value', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-2');
      expect(res.getAllScalars.nullableInt, equals(99));
    });

    test('nullableFloat has value', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-2');
      expect(res.getAllScalars.nullableFloat, closeTo(2.718, 0.001));
    });

    test('nullableBool is false (not null)', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-2');
      expect(res.getAllScalars.nullableBool, isFalse);
    });

    test('negative int deserializes correctly', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-2');
      expect(res.getAllScalars.intVal, equals(-1));
    });

    test('negative float deserializes correctly', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-2');
      expect(res.getAllScalars.floatVal, closeTo(-0.5, 0.001));
    });

    test('bool false is not treated as null', () async {
      final res = await client.queries.getAllScalars(id: 'scalar-2');
      expect(res.getAllScalars.boolVal, isFalse);
      expect(res.getAllScalars.boolVal, isNotNull);
    });
  });

  group('outgoing request shape', () {
    setUp(() => adapter.registerData(
          'getAllScalars',
          {'getAllScalars': kAllScalarsNullJson},
        ));

    test('id argument is sent as string in variables', () async {
      await client.queries.getAllScalars(id: 'scalar-1');
      expect(adapter.lastCall!.variables['id'], equals('scalar-1'));
    });

    test('operation name is getAllScalars', () async {
      await client.queries.getAllScalars(id: 'scalar-1');
      expect(adapter.lastCall!.operationName, equals('getAllScalars'));
    });
  });
}
