import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/enums/priority.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/create_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/update_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/address_input.dart';
import 'real_server_adapter.dart';

// These tests verify that inputs are correctly serialized to the server
// by asserting the server echoes back the expected values in the response.

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('CreateUserInput — required scalar fields', () {
    test('name is sent and echoed back', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice Smith',
          email: 'alice@test.com',
          status: UserStatus.active,
          address: AddressInput(street: '1 St', city: 'City', country: 'US'),
        ),
      );
      expect(res.createUser.name, equals('Alice Smith'));
    });

    test('email is sent and echoed back', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'test@example.com',
          status: UserStatus.active,
          address: AddressInput(street: '1 St', city: 'City', country: 'US'),
        ),
      );
      expect(res.createUser.email, equals('test@example.com'));
    });

    test('enum field status is sent and deserialized', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.suspended,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
        ),
      );
      expect(res.createUser.status, equals(UserStatus.suspended));
    });
  });

  group('CreateUserInput — nested AddressInput', () {
    test('address fields are sent and echoed back', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.active,
          address: AddressInput(
            street: '123 Main St',
            city: 'Springfield',
            country: 'US',
            zip: '12345',
          ),
        ),
      );
      expect(res.createUser.address.street, equals('123 Main St'));
      expect(res.createUser.address.city, equals('Springfield'));
      expect(res.createUser.address.zip, equals('12345'));
    });

    test('nullable zip is null when not provided', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.active,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
        ),
      );
      expect(res.createUser.address.zip, isNull);
    });
  });

  group('CreateUserInput — optional fields', () {
    test('priority is null when not provided', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.active,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
        ),
      );
      expect(res.createUser.priority, isNull);
    });

    test('priority is deserialized when provided', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.active,
          priority: Priority.critical,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
        ),
      );
      expect(res.createUser.priority, equals(Priority.critical));
    });

    test('tags list is serialized correctly', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.active,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
          tags: ['admin', 'beta'],
        ),
      );
      expect(res.createUser.tags, equals(['admin', 'beta']));
    });

    test('empty tags list is serialized as empty list', () async {
      final res = await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.active,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
          tags: [],
        ),
      );
      expect(res.createUser.tags, isEmpty);
    });
  });

  group('UpdateUserInput — partial updates applied server-side', () {
    test('only name is updated; other fields preserved', () async {
      final res = await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(name: 'New Name'),
      );
      expect(res.updateUser.name, equals('New Name'));
      expect(res.updateUser.email, equals('alice@test.com'));
      expect(res.updateUser.status, isNotNull);
    });

    test('updateUser with different id returns that user updated', () async {
      final res = await client.mutations.updateUser(
        id: 'user-2',
        input: UpdateUserInput(status: UserStatus.active),
      );
      expect(res.updateUser.id, equals('user-2'));
      expect(res.updateUser.status, equals(UserStatus.active));
    });
  });
}
