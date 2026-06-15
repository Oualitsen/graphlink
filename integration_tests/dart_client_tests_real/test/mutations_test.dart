import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/enums/priority.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/create_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/update_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/address_input.dart';
import 'real_server_adapter.dart';

// The server echoes input fields back — priority is null when not in input.
final _minimalInput = CreateUserInput(
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: UserStatus.ACTIVE,
  address:
      AddressInput(street: '123 Main St', city: 'Springfield', country: 'US'),
);

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  // ── createUser ────────────────────────────────────────────────────────────

  group('createUser — scalar fields echoed from input', () {
    test('name is returned from server', () async {
      final res =
          await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.name, equals('Alice Smith'));
    });

    test('email is returned from server', () async {
      final res =
          await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.email, equals('alice@test.com'));
    });

    test('status is returned as enum', () async {
      final res =
          await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.status, equals(UserStatus.ACTIVE));
    });

    test('priority is null when not provided in input', () async {
      final res =
          await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.priority, isNull);
    });

    test('priority is deserialized as enum when provided', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice Smith',
          email: 'alice@test.com',
          status: UserStatus.ACTIVE,
          priority: Priority.HIGH,
          address: AddressInput(
              street: '123 Main St', city: 'Springfield', country: 'US'),
        ),
        limit: 10,
      );
      expect(res.createUser.priority, equals(Priority.HIGH));
    });
  });

  group('createUser — nested address from input', () {
    test('address.street is returned', () async {
      final res =
          await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.address.street, equals('123 Main St'));
    });

    test('address.city is returned', () async {
      final res =
          await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.address.city, equals('Springfield'));
    });

    test('address.zip is null when not provided', () async {
      final res =
          await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.address.zip, isNull);
    });

    test('nullable billingAddress is null when not provided', () async {
      final res =
          await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.billingAddress, isNull);
    });
  });

  group('createUser — list fields from input', () {
    test('tags list is echoed back from input', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice Smith',
          email: 'alice@test.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(
              street: '123 Main St', city: 'Springfield', country: 'US'),
          tags: ['admin', 'beta'],
        ),
        limit: 10,
      );
      expect(res.createUser.tags, equals(['admin', 'beta']));
    });

    test('tags defaults to empty list when not provided', () async {
      final res =
          await client.mutations.createUser(input: _minimalInput);
      expect(res.createUser.tags, isEmpty);
    });
  });

  // ── deleteUser ────────────────────────────────────────────────────────────

  group('deleteUser', () {
    test('returns true', () async {
      final res = await client.mutations.deleteUser(id: 'user-1');
      expect(res.deleteUser, isTrue);
    });
  });

  // ── updateUser ────────────────────────────────────────────────────────────

  group('updateUser', () {
    test('updated name is reflected in response', () async {
      final res = await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(name: 'Updated Alice'),
        limit: 10,
      );
      expect(res.updateUser.id, equals('user-1'));
      expect(res.updateUser.name, equals('Updated Alice'));
    });

    test('unchanged fields are preserved from base user', () async {
      final res = await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(name: 'New Name'),
        limit: 10,
      );
      expect(res.updateUser.email, equals('alice@test.com'));
      expect(res.updateUser.status, equals(UserStatus.ACTIVE));
    });

    test('status update is applied', () async {
      final res = await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(status: UserStatus.SUSPENDED),
        limit: 10,
      );
      expect(res.updateUser.status, equals(UserStatus.SUSPENDED));
    });

    test('nested address is preserved', () async {
      final res = await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(name: 'New Name'),
        limit: 10,
      );
      expect(res.updateUser.address.street, equals('123 Main St'));
    });
  });
}
