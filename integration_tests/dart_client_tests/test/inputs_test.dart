import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/enums/priority.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/create_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/update_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/address_input.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late GraphLinkClient client;

  setUp(() {
    adapter = MockAdapter();
    client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
    // createUser / updateUser always respond with Alice
    adapter.registerData('createUser', {'createUser': kUserAliceJson});
    adapter.registerData('updateUser', {'updateUser': kUserAliceJson});
  });

  group('CreateUserInput — required scalar fields', () {
    test('name is serialized correctly', () async {
      await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice Smith',
          email: 'alice@test.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(
            street: '123 Main St',
            city: 'Springfield',
            country: 'US',
          ),
        ),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      expect(input['name'], equals('Alice Smith'));
    });

    test('email is serialized correctly', () async {
      await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'alice@test.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(
            street: '1 St',
            city: 'City',
            country: 'US',
          ),
        ),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      expect(input['email'], equals('alice@test.com'));
    });

    test('enum field status is serialized as a string', () async {
      await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.SUSPENDED,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
        ),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      expect(input['status'], equals('SUSPENDED'));
    });
  });

  group('CreateUserInput — nested AddressInput', () {
    test('address fields are serialized correctly', () async {
      await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(
            street: '123 Main St',
            city: 'Springfield',
            country: 'US',
            zip: '12345',
          ),
        ),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      final address = input['address'] as Map<String, dynamic>;
      expect(address['street'], equals('123 Main St'));
      expect(address['city'], equals('Springfield'));
      expect(address['country'], equals('US'));
      expect(address['zip'], equals('12345'));
    });

    test('nullable zip is null when not provided', () async {
      await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
        ),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      final address = input['address'] as Map<String, dynamic>;
      expect(address['zip'], isNull);
    });
  });

  group('CreateUserInput — optional fields', () {
    test('nullable priority is absent or null when not provided', () async {
      await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
        ),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      expect(input['priority'], isNull);
    });

    test('priority is serialized as string when provided', () async {
      await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.ACTIVE,
          priority: Priority.CRITICAL,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
        ),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      expect(input['priority'], equals('CRITICAL'));
    });

    test('billingAddress is null when not provided', () async {
      await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
        ),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      expect(input['billingAddress'], isNull);
    });

    test('tags list is serialized correctly', () async {
      await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
          tags: ['admin', 'beta'],
        ),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      expect(input['tags'], equals(['admin', 'beta']));
    });

    test('empty tags list is serialized as empty list', () async {
      await client.mutations.createUser(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@b.com',
          status: UserStatus.ACTIVE,
          address: AddressInput(street: '1', city: 'C', country: 'US'),
          tags: [],
        ),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      expect(input['tags'], isEmpty);
    });
  });

  group('UpdateUserInput — all nullable fields', () {
    test('only provided fields are non-null in variables', () async {
      await client.mutations.updateUser(
        id: 'user-1',
        input: UpdateUserInput(name: 'New Name'),
      );
      final input = adapter.lastCall!.variables['input'] as Map<String, dynamic>;
      expect(input['name'], equals('New Name'));
      expect(input['email'], isNull);
      expect(input['status'], isNull);
    });

    test('id is passed correctly as a top-level variable', () async {
      await client.mutations.updateUser(
        id: 'user-42',
        input: UpdateUserInput(status: UserStatus.INACTIVE),
      );
      expect(adapter.lastCall!.variables['id'], equals('user-42'));
    });
  });
}
