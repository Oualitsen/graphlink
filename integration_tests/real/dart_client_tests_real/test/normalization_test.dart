import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/event_type.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/normalized_input.dart';
import 'real_server_adapter.dart';

/// End-to-end coverage for identifier normalization.
///
/// The GraphQL schema intentionally uses non-canonical field casing:
///   - `FirstName`  (PascalCase)   → Dart codeName: `firstName`
///   - `last_name`  (snake_case)   → Dart codeName: `lastName`
///   - `USER_AGE`   (SCREAMING)    → Dart codeName: `userAge`
///   - `event_type` (snake_case)   → Dart codeName: `eventType`
///
/// Enum wire names are lowercase/snake: `pending`, `in_progress`, `completed_ok`.
/// Dart codenames follow lowerCamelCase: `pending`, `inProgress`, `completedOk`.
///
/// Wire names are always used in the GraphQL request and JSON; only the
/// generated Dart identifiers are normalized.
void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('enum round-trip (EventType)', () {
    test('pending wire name → Dart codeName pending', () {
      expect(EventType.pending.toJson(), equals('pending'));
      expect(EventType.fromJson('pending'), equals(EventType.pending));
    });

    test('in_progress wire name → Dart codeName inProgress', () {
      expect(EventType.inProgress.toJson(), equals('in_progress'));
      expect(EventType.fromJson('in_progress'), equals(EventType.inProgress));
    });

    test('completed_ok wire name → Dart codeName completedOk', () {
      expect(EventType.completedOk.toJson(), equals('completed_ok'));
      expect(EventType.fromJson('completed_ok'), equals(EventType.completedOk));
    });
  });

  group('getNormalizedRecord — field normalization', () {
    test('firstName is accessible and correct (wire: FirstName)', () async {
      final res = await client.queries.getNormalizedRecord(id: 'rec-1');
      expect(res.getNormalizedRecord.firstName, equals('Alice'));
    });

    test('lastName is accessible and correct (wire: last_name)', () async {
      final res = await client.queries.getNormalizedRecord(id: 'rec-1');
      expect(res.getNormalizedRecord.lastName, equals('Smith'));
    });

    test('userAge is accessible and correct (wire: USER_AGE)', () async {
      final res = await client.queries.getNormalizedRecord(id: 'rec-1');
      expect(res.getNormalizedRecord.userAge, equals(30));
    });

    test('eventType is deserialized as lowerCamelCase enum (wire: event_type → in_progress)',
        () async {
      final res = await client.queries.getNormalizedRecord(id: 'rec-1');
      expect(res.getNormalizedRecord.eventType, equals(EventType.inProgress));
    });
  });

  group('createNormalizedRecord — input normalization', () {
    test('normalized input fields round-trip through the server', () async {
      final res = await client.mutations.createNormalizedRecord(
        input: const NormalizedInput(
          firstName: 'Bob',
          lastName: 'Jones',
          eventType: EventType.completedOk,
        ),
      );
      expect(res.createNormalizedRecord.firstName, equals('Bob'));
      expect(res.createNormalizedRecord.lastName, equals('Jones'));
      expect(
          res.createNormalizedRecord.eventType, equals(EventType.completedOk));
    });
  });
}
