import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/types/graph_link_error.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/create_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/address_input.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late GraphLinkClient client;

  setUp(() {
    adapter = MockAdapter();
    client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
  });

  // ── getUserOrErrors — error response ──────────────────────────────────────

  group('getUserOrErrors — error response', () {
    setUp(() => adapter.registerErrors('getUserOrErrors', [kGraphQLError]));

    test('errors is non-null', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.errors, isNotNull);
    });

    test('data is null', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.data, isNull);
    });

    test('first error has correct message', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.errors!.first.message, equals('Not found'));
    });
  });

  // ── getUserOrErrors — success response ────────────────────────────────────

  group('getUserOrErrors — success response', () {
    setUp(() => adapter.registerData('getUserOrErrors', {'getUserOrErrors': kUserAliceJson}));

    test('errors is null', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.errors, isNull);
    });

    test('data is non-null', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.data, isNotNull);
    });

    test('data.getUserOrErrors.name is correct', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.data!.getUserOrErrors.name, equals('Alice Smith'));
    });

    test('data.getUserOrErrors.id is correct', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.data!.getUserOrErrors.id, equals('user-1'));
    });
  });

  // ── findUserOrErrors — error response ─────────────────────────────────────

  group('findUserOrErrors — error response', () {
    setUp(() => adapter.registerErrors('findUserOrErrors', [kGraphQLError]));

    test('errors is non-null', () async {
      final res = await client.queries.findUserOrErrors(id: 'user-1');
      expect(res.errors, isNotNull);
    });

    test('data is null', () async {
      final res = await client.queries.findUserOrErrors(id: 'user-1');
      expect(res.data, isNull);
    });

    test('first error has correct message', () async {
      final res = await client.queries.findUserOrErrors(id: 'user-1');
      expect(res.errors!.first.message, equals('Not found'));
    });
  });

  // ── createUserOrErrors — error response ──────────────────────────────────

  group('createUserOrErrors — error response', () {
    setUp(() => adapter.registerErrors('createUserOrErrors', [kGraphQLError]));

    test('errors is non-null', () async {
      final res = await client.mutations.createUserOrErrors(
        input: CreateUserInput(
          name: 'Alice Smith',
          email: 'alice@test.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '123 Main St', city: 'Springfield', country: 'US'),
        ),
      );
      expect(res.errors, isNotNull);
    });

    test('data is null', () async {
      final res = await client.mutations.createUserOrErrors(
        input: CreateUserInput(
          name: 'Alice Smith',
          email: 'alice@test.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '123 Main St', city: 'Springfield', country: 'US'),
        ),
      );
      expect(res.data, isNull);
    });

    test('first error has correct message', () async {
      final res = await client.mutations.createUserOrErrors(
        input: CreateUserInput(
          name: 'Alice Smith',
          email: 'alice@test.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '123 Main St', city: 'Springfield', country: 'US'),
        ),
      );
      expect(res.errors!.first.message, equals('Not found'));
    });
  });

  // ── createUserOrErrors — success response ─────────────────────────────────

  group('createUserOrErrors — success response', () {
    setUp(() => adapter.registerData('createUserOrErrors', {'createUserOrErrors': kUserAliceJson}));

    test('errors is null', () async {
      final res = await client.mutations.createUserOrErrors(
        input: CreateUserInput(
          name: 'Alice Smith',
          email: 'alice@test.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '123 Main St', city: 'Springfield', country: 'US'),
        ),
      );
      expect(res.errors, isNull);
    });

    test('data is non-null', () async {
      final res = await client.mutations.createUserOrErrors(
        input: CreateUserInput(
          name: 'Alice Smith',
          email: 'alice@test.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '123 Main St', city: 'Springfield', country: 'US'),
        ),
      );
      expect(res.data, isNotNull);
    });

    test('data.createUserOrErrors.name is correct', () async {
      final res = await client.mutations.createUserOrErrors(
        input: CreateUserInput(
          name: 'Alice Smith',
          email: 'alice@test.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '123 Main St', city: 'Springfield', country: 'US'),
        ),
      );
      expect(res.data!.createUserOrErrors.name, equals('Alice Smith'));
    });
  });

  // ── getUser — no @glCaptureErrors: throws on error ────────────────────────

  group('getUser — throws on error response', () {
    setUp(() => adapter.registerErrors('getUser', [kGraphQLError]));

    test('throws a List<GraphLinkError> when server returns errors', () {
      expect(
        client.queries.getUser(id: 'user-1'),
        throwsA(isA<List<GraphLinkError>>()),
      );
    });

    test('thrown error list has the correct message', () async {
      List<GraphLinkError>? thrown;
      try {
        await client.queries.getUser(id: 'user-1');
      } catch (e) {
        thrown = e as List<GraphLinkError>;
      }
      expect(thrown, isNotNull);
      expect(thrown!.first.message, equals('Not found'));
    });
  });
}
