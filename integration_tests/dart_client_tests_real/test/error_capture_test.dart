import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/types/graph_link_error.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/create_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/address_input.dart';
import 'real_server_adapter.dart';

// Errors are triggered by using IDs / names the server rejects:
//   getUser("error-id")   → throws (unknown user)
//   findUser("error-id")  → throws (server special-cases this ID)
//   createUserOrErrors(name: "error-user") → server throws

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  // ── getUserOrErrors — error response ──────────────────────────────────────

  group('getUserOrErrors — error response (unknown id)', () {
    test('errors is non-null', () async {
      final res =
          await client.queries.getUserOrErrors(id: 'error-id');
      expect(res.errors, isNotNull);
    });

    test('data is null', () async {
      final res =
          await client.queries.getUserOrErrors(id: 'error-id');
      expect(res.data, isNull);
    });

    test('first error has a non-empty message', () async {
      final res =
          await client.queries.getUserOrErrors(id: 'error-id');
      expect(res.errors!.first.message, isNotEmpty);
    });
  });

  // ── getUserOrErrors — success response ────────────────────────────────────

  group('getUserOrErrors — success response', () {
    test('errors is null', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.errors, isNull);
    });

    test('data is non-null', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.data, isNotNull);
    });

    test('data.getUserOrErrors.name is Alice Smith', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.data!.getUserOrErrors.name, equals('Alice Smith'));
    });

    test('data.getUserOrErrors.id is user-1', () async {
      final res = await client.queries.getUserOrErrors(id: 'user-1');
      expect(res.data!.getUserOrErrors.id, equals('user-1'));
    });
  });

  // ── findUserOrErrors — error response ─────────────────────────────────────
  // Spring returns partial data {findUserOrErrors: null} for nullable fields —
  // so data is NOT null, but errors is populated.

  group('findUserOrErrors — error response (error-id)', () {
    test('errors is non-null', () async {
      final res =
          await client.queries.findUserOrErrors(id: 'error-id');
      expect(res.errors, isNotNull);
    });

    test('data.findUserOrErrors is null when error occurs', () async {
      final res =
          await client.queries.findUserOrErrors(id: 'error-id');
      expect(res.data!.findUserOrErrors, isNull);
    });
  });

  // ── findUserOrErrors — success (null return) ──────────────────────────────

  group('findUserOrErrors — null return (unknown non-error id)', () {
    test('errors is null and data.findUserOrErrors is null', () async {
      final res =
          await client.queries.findUserOrErrors(id: 'missing');
      expect(res.errors, isNull);
      expect(res.data!.findUserOrErrors, isNull);
    });
  });

  // ── createUserOrErrors — error response ───────────────────────────────────

  group('createUserOrErrors — error response', () {
    final errorInput = CreateUserInput(
      name: 'error-user',
      email: 'a@b.com',
      status: UserStatus.ACTIVE,
      address: AddressInput(street: '1', city: 'C', country: 'US'),
    );

    test('errors is non-null', () async {
      final res = await client.mutations
          .createUserOrErrors(input: errorInput);
      expect(res.errors, isNotNull);
    });

    test('data is null', () async {
      final res = await client.mutations
          .createUserOrErrors(input: errorInput);
      expect(res.data, isNull);
    });
  });

  // ── createUserOrErrors — success response ─────────────────────────────────

  group('createUserOrErrors — success response', () {
    final goodInput = CreateUserInput(
      name: 'Alice Smith',
      email: 'alice@test.com',
      status: UserStatus.ACTIVE,
      address: AddressInput(
          street: '123 Main St', city: 'Springfield', country: 'US'),
    );

    test('errors is null', () async {
      final res = await client.mutations
          .createUserOrErrors(input: goodInput);
      expect(res.errors, isNull);
    });

    test('data is non-null', () async {
      final res = await client.mutations
          .createUserOrErrors(input: goodInput);
      expect(res.data, isNotNull);
    });

    test('data.createUserOrErrors.name is correct', () async {
      final res = await client.mutations
          .createUserOrErrors(input: goodInput);
      expect(res.data!.createUserOrErrors.name, equals('Alice Smith'));
    });
  });

  // ── getUser — no @glCaptureErrors: throws on error ────────────────────────

  group('getUser — throws on error response', () {
    test('throws a List<GraphLinkError> when server returns errors', () {
      expect(
        client.queries.getUser(id: 'error-id'),
        throwsA(isA<List<GraphLinkError>>()),
      );
    });

    test('thrown error list has a non-empty message', () async {
      List<GraphLinkError>? thrown;
      try {
        await client.queries.getUser(id: 'error-id');
      } catch (e) {
        thrown = e as List<GraphLinkError>;
      }
      expect(thrown, isNotNull);
      expect(thrown!.first.message, isNotEmpty);
    });
  });
}
