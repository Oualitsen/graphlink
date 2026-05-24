import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/enums/priority.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/create_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/update_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/address_input.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

final _minimalInput = CreateUserInput(
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: UserStatus.ACTIVE,
  address: AddressInput(street: '123 Main St', city: 'Springfield', country: 'US'),
);

void main() {
  late MockAdapter adapter;
  late GraphLinkClient client;

  setUp(() {
    adapter = MockAdapter();
    client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
  });

  // ── createUser — response deserialization ─────────────────────────────────

  group('createUser — scalar fields', () {
    setUp(() => adapter.registerData('createUser', {'createUser': kUserAliceJson}));

    test('id is deserialized correctly', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.id, equals('user-1'));
    });

    test('name is deserialized correctly', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.name, equals('Alice Smith'));
    });

    test('email is deserialized correctly', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.email, equals('alice@test.com'));
    });

    test('status is deserialized as enum', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.status, equals(UserStatus.ACTIVE));
    });

    test('priority is deserialized as enum when present', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.priority, equals(Priority.HIGH));
    });
  });

  group('createUser — nested address', () {
    setUp(() => adapter.registerData('createUser', {'createUser': kUserAliceJson}));

    test('address.street is deserialized', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.address.street, equals('123 Main St'));
    });

    test('address.city is deserialized', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.address.city, equals('Springfield'));
    });

    test('address.country is deserialized', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.address.country, equals('US'));
    });

    test('address.zip is deserialized', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.address.zip, equals('12345'));
    });

    test('nullable billingAddress is null', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.billingAddress, isNull);
    });
  });

  group('createUser — list fields', () {
    setUp(() => adapter.registerData('createUser', {'createUser': kUserAliceJson}));

    test('tags list is deserialized', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.tags, equals(['admin', 'beta']));
    });

    test('scores list is deserialized', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.scores, equals([10, 20, 30]));
    });
  });

  group('createUser — response with Bob (nullable fields populated)', () {
    setUp(() => adapter.registerData('createUser', {'createUser': kUserBobJson}));

    test('status INACTIVE is deserialized', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.status, equals(UserStatus.INACTIVE));
    });

    test('nullable priority is null', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.priority, isNull);
    });

    test('billingAddress is deserialized when present', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.billingAddress, isNotNull);
      expect(res.createUser.billingAddress!.city, equals('Capital City'));
    });

    test('empty tags list is deserialized as empty list', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.tags, isEmpty);
    });

    test('nullable scores is null', () async {
      final res = await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.scores, isNull);
    });
  });

  group('createUser — outgoing request shape', () {
    setUp(() => adapter.registerData('createUser', {'createUser': kUserAliceJson}));

    test('operation name is createUser', () async {
      await client.mutations.createUser(input: _minimalInput);
      expect(adapter.lastCall!.operationName, equals('createUser'));
    });

    test('input variable is present', () async {
      await client.mutations.createUser(input: _minimalInput);
      expect(adapter.lastCall!.variables['input'], isNotNull);
    });
  });

  // ── deleteUser — scalar return + variable shape ───────────────────────────

  group('deleteUser — returns bool', () {
    test('returns true when server responds true', () async {
      adapter.registerData('deleteUser', {'deleteUser': true});
      final res = await client.mutations.deleteUser(id: 'user-1');
      expect(res.deleteUser, isTrue);
    });

    test('returns false when server responds false', () async {
      adapter.registerData('deleteUser', {'deleteUser': false});
      final res = await client.mutations.deleteUser(id: 'user-1');
      expect(res.deleteUser, isFalse);
    });
  });

  group('deleteUser — outgoing request shape', () {
    setUp(() => adapter.registerData('deleteUser', {'deleteUser': true}));

    test('id variable is sent correctly', () async {
      await client.mutations.deleteUser(id: 'user-99');
      expect(adapter.lastCall!.variables['id'], equals('user-99'));
    });

    test('operation name is deleteUser', () async {
      await client.mutations.deleteUser(id: 'user-1');
      expect(adapter.lastCall!.operationName, equals('deleteUser'));
    });
  });

  // ── updateUser — response deserialization + variable shape ────────────────

  group('updateUser — response deserialization', () {
    setUp(() => adapter.registerData('updateUser', {'updateUser': kUserAliceJson}));

    test('returns a User with correct id', () async {
      final res = await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(name: 'Alice Smith'),
      );
      expect(res.updateUser.id, equals('user-1'));
    });

    test('returns a User with correct name', () async {
      final res = await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(name: 'Alice Smith'),
      );
      expect(res.updateUser.name, equals('Alice Smith'));
    });

    test('status is deserialized as enum', () async {
      final res = await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(status: UserStatus.ACTIVE),
      );
      expect(res.updateUser.status, equals(UserStatus.ACTIVE));
    });

    test('nested address is deserialized', () async {
      final res = await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(name: 'Alice Smith'),
      );
      expect(res.updateUser.address.street, equals('123 Main St'));
    });
  });

  group('updateUser — outgoing request shape', () {
    setUp(() => adapter.registerData('updateUser', {'updateUser': kUserAliceJson}));

    test('id is passed as top-level variable', () async {
      await client.mutations.updateUser(
        id: 'user-42',
        input: UpdateUserInput(name: 'Updated'),
      );
      expect(adapter.lastCall!.variables['id'], equals('user-42'));
    });

    test('input variable is present alongside id', () async {
      await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(name: 'Updated'),
      );
      expect(adapter.lastCall!.variables['input'], isNotNull);
    });

    test('operation name is updateUser', () async {
      await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(name: 'Updated'),
      );
      expect(adapter.lastCall!.operationName, equals('updateUser'));
    });
  });
}
