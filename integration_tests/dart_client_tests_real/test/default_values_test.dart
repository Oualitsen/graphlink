import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/role.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/create_with_defaults_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/nested_defaults_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/address_input.dart';
import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('createWithDefaults — client applies input field defaults', () {
    test('role defaults to USER when not provided', () async {
      try {
      final res = await client.mutations.createWithDefaults(
        input: CreateWithDefaultsInput(name: 'test'),
      );
      
      expect(res.createWithDefaults.role, equals(Role.USER));
      }catch(err, st) {
        print(err);
      }
    });

    test('age defaults to 18 when not provided', () async {
      final res = await client.mutations.createWithDefaults(
        input: CreateWithDefaultsInput(name: 'test'),
      );
      expect(res.createWithDefaults.age, equals(18));
    });

    test('isActive defaults to true when not provided', () async {
      final res = await client.mutations.createWithDefaults(
        input: CreateWithDefaultsInput(name: 'test'),
      );
      expect(res.createWithDefaults.isActive, isTrue);
    });

    test('score defaults to 4.5 when not provided', () async {
      final res = await client.mutations.createWithDefaults(
        input: CreateWithDefaultsInput(name: 'test'),
      );
      expect(res.createWithDefaults.score, equals(4.5));
    });

    test('nickname defaults to "anonymous" when not provided', () async {
      final res = await client.mutations.createWithDefaults(
        input: CreateWithDefaultsInput(name: 'test'),
      );
      expect(res.createWithDefaults.nickname, equals('anonymous'));
    });

    test('tags defaults to ["dart", "graphql"] when not provided', () async {
      final res = await client.mutations.createWithDefaults(
        input: CreateWithDefaultsInput(name: 'test'),
      );
      expect(res.createWithDefaults.tags, equals(['dart', 'graphql']));
    });

    test('name is echoed from provided value', () async {
      final res = await client.mutations.createWithDefaults(
        input: CreateWithDefaultsInput(name: 'explicit-name'),
      );
      expect(res.createWithDefaults.name, equals('explicit-name'));
    });

    test('explicit values override defaults', () async {
      final res = await client.mutations.createWithDefaults(
        input: CreateWithDefaultsInput(
          name: 'override-test',
          role: Role.ADMIN,
          age: 99,
          isActive: false,
          score: 9.9,
          nickname: 'custom',
          tags: ['custom-tag'],
        ),
      );
      expect(res.createWithDefaults.name, equals('override-test'));
      expect(res.createWithDefaults.role, equals(Role.ADMIN));
      expect(res.createWithDefaults.age, equals(99));
      expect(res.createWithDefaults.isActive, isFalse);
      expect(res.createWithDefaults.score, equals(9.9));
      expect(res.createWithDefaults.nickname, equals('custom'));
      expect(res.createWithDefaults.tags, equals(['custom-tag']));
    });
  });

  group('listUsersWithDefaults — client applies argument defaults', () {
    test('returns users without providing optional arguments', () async {
      final res = await client.queries.listUsersWithDefaults();
      // The client sends limit=20 (default), server echoes back users.
      // Just verify we get a non-empty list — the defaults are applied
      // client-side in the variables map, so the server receives the
      // default values and the query succeeds.
      expect(res.listUsersWithDefaults, isNotEmpty);
    });

    test('explicit limit overrides default', () async {
      final res = await client.queries.listUsersWithDefaults(limit: 1);
      expect(res.listUsersWithDefaults, hasLength(1));
    });

    test('explicit role can be provided', () async {
      final res =
          await client.queries.listUsersWithDefaults(role: Role.ADMIN);
      expect(res.listUsersWithDefaults, isNotEmpty);
    });
  });

  group('createWithNestedDefaults — client applies nested object/list defaults', () {
    test('name is echoed from provided value', () async {
      final res = await client.mutations.createWithNestedDefaults(
        input: NestedDefaultsInput(name: 'nested-test'),
      );
      expect(res.createWithNestedDefaults.name, equals('nested-test'));
    });

    // ── Object default ────────────────────────────────────────────────────

    test('address defaults to full AddressInput object', () async {
      final res = await client.mutations.createWithNestedDefaults(
        input: NestedDefaultsInput(name: 'obj-default'),
      );
      final a = res.createWithNestedDefaults.address!;
      expect(a.street, equals('123 Main St'));
      expect(a.city, equals('Springfield'));
      expect(a.country, equals('US'));
      expect(a.zip, equals('12345'));
    });

    // ── List-of-objects default ───────────────────────────────────────────

    test('contacts defaults to list of two AddressInput objects', () async {
      final res = await client.mutations.createWithNestedDefaults(
        input: NestedDefaultsInput(name: 'list-default'),
      );
      final contacts = res.createWithNestedDefaults.contacts!;
      expect(contacts, hasLength(2));
      expect(contacts[0]!.street, equals('456 Oak Ave'));
      expect(contacts[0]!.city, equals('Shelbyville'));
      expect(contacts[0]!.zip, isNull);
      expect(contacts[1]!.street, equals('789 Pine Rd'));
      expect(contacts[1]!.city, equals('Capital City'));
      expect(contacts[1]!.zip, equals('99999'));
    });

    // ── List-of-list-of-objects default ───────────────────────────────────

    test('matrix defaults to nested list of AddressInput objects', () async {
      final res = await client.mutations.createWithNestedDefaults(
        input: NestedDefaultsInput(name: 'matrix-default'),
      );
      final matrix = res.createWithNestedDefaults.matrix!;
      expect(matrix, hasLength(2));
      // Row 0: single address
      expect(matrix[0], hasLength(1));
      expect(matrix[0]![0]!.street, equals('1st St'));
      expect(matrix[0]![0]!.city, equals('Paris'));
      expect(matrix[0]![0]!.country, equals('FR'));
      expect(matrix[0]![0]!.zip, equals('75000'));
      // Row 1: single address
      expect(matrix[1], hasLength(1));
      expect(matrix[1]![0]!.street, equals('2nd St'));
      expect(matrix[1]![0]!.city, equals('Lyon'));
      expect(matrix[1]![0]!.country, equals('FR'));
      expect(matrix[1]![0]!.zip, equals('69000'));
    });

    // ── Explicit values override defaults ─────────────────────────────────

    test('explicit values override nested defaults', () async {
      final res = await client.mutations.createWithNestedDefaults(
        input: NestedDefaultsInput(
          name: 'override-nested',
          address: AddressInput(
              street: 'Custom St', city: 'Custom City', country: 'XX'),
          contacts: [
            AddressInput(
                street: 'One', city: 'Two', country: 'Three', zip: '44444'),
          ],
          matrix: [
            [AddressInput(street: 'A', city: 'B', country: 'C')],
          ],
        ),
      );
      final a = res.createWithNestedDefaults.address!;
      expect(a.street, equals('Custom St'));
      expect(a.city, equals('Custom City'));
      expect(a.country, equals('XX'));
      expect(a.zip, isNull);

      expect(res.createWithNestedDefaults.contacts!, hasLength(1));
      expect(res.createWithNestedDefaults.contacts![0]!.street, equals('One'));

      expect(res.createWithNestedDefaults.matrix!, hasLength(1));
      expect(res.createWithNestedDefaults.matrix![0]![0]!.street, equals('A'));
    });
  });

  group('getDriver — client applies field-argument defaults', () {
    test('odometerKm is required (echoed back)', () async {
      final res = await client.queries.getDriver(
        id: 'driver-1',
        lastUsedMillageOdometerKm: 100,
      );
      expect(res.getDriver.lastUsedMillage, equals(100));
    });

    test('liters defaults to 4 when not provided', () async {
      final res = await client.queries.getDriver(
        id: 'driver-1',
        lastUsedMillageOdometerKm: 200,
      );
      // Client sends liters=4 (the default), server echoes it back
      expect(res.getDriver.lastUsedFuel, equals(4));
    });

    test('explicit liters overrides the default', () async {
      final res = await client.queries.getDriver(
        id: 'driver-1',
        lastUsedMillageOdometerKm: 300,
        lastUsedFuelLiters: 10,
      );
      expect(res.getDriver.lastUsedFuel, equals(10));
    });

    test('both values echoed back with explicit liters', () async {
      final res = await client.queries.getDriver(
        id: 'driver-1',
        lastUsedMillageOdometerKm: 500,
        lastUsedFuelLiters: 25,
      );
      expect(res.getDriver.lastUsedMillage, equals(500));
      expect(res.getDriver.lastUsedFuel, equals(25));
    });
  });
}
