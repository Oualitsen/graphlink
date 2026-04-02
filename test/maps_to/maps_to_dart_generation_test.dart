import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

// Helpers --------------------------------------------------------------------

GLParser _parser() =>
    GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true);

/// Parses [schema], serializes the input named [inputName], and returns the
/// trimmed lines — ready for containsAllInOrder / contains assertions.
List<String> _lines(String schema, String inputName) {
  final g = _parser()..parse(schema);
  final input = g.inputs[inputName]!;
  final result = DartSerializer(g).serializeInputDefinition(input, '');
  return result.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
}

// ---------------------------------------------------------------------------
// Shared helper — trailing comma is only added when there are multiple args
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Case 1 — All fields match by name, no extras
// ---------------------------------------------------------------------------

const _case1 = '''
  type Address {
    street: String!
    city: String!
    country: String!
  }

  input CreateAddressInput @glMapsTo(type: "Address") {
    street: String!
    city: String!
    country: String!
  }

  type Query { noop: String }
''';

// ---------------------------------------------------------------------------
// Case 2 — @glMapField aliases
// ---------------------------------------------------------------------------

const _case2 = '''
  type Person {
    id: ID!
    firstName: String!
    lastName: String!
    email: String!
  }

  input CreatePersonInput @glMapsTo(type: "Person") {
    fname: String! @glMapField(to: "firstName")
    lname: String! @glMapField(to: "lastName")
    email: String!
  }

  type Query { noop: String }
''';

// ---------------------------------------------------------------------------
// Case 3 — Nullability mismatch
// ---------------------------------------------------------------------------

const _case3 = '''
  type User {
    id: ID!
    username: String!
    role: String!
  }

  input CreateUserInput @glMapsTo(type: "User") {
    username: String!
    role: String
  }

  type Query { noop: String }
''';

// ---------------------------------------------------------------------------
// Case 4 — Input-only fields
// ---------------------------------------------------------------------------

const _case4 = '''
  type Account {
    id: ID!
    email: String!
    displayName: String!
  }

  input RegisterAccountInput @glMapsTo(type: "Account") {
    email: String!
    displayName: String!
    password: String!
    confirmPassword: String!
  }

  type Query { noop: String }
''';

void main() {
  group('Case 1 — all fields match by name', () {
    test('toAddress() has no parameters', () {
      expect(
        _lines(_case1, 'CreateAddressInput'),
        contains('Address toAddress() {'),
      );
    });

    test('toAddress() assigns all three fields directly on one line', () {
      final lines = _lines(_case1, 'CreateAddressInput');
      expect(
        lines,
        contains('return Address(street: street, city: city, country: country);'),
      );
    });

    test('fromAddress() takes only the required Address param', () {
      expect(
        _lines(_case1, 'CreateAddressInput'),
        containsAllInOrder([
          'static CreateAddressInput fromAddress({',
          'required Address address',
          '}) {',
        ]),
      );
    });

    test('fromAddress() maps all fields from the Address instance', () {
      final lines = _lines(_case1, 'CreateAddressInput');
      expect(
        lines,
        contains(
          'return CreateAddressInput(street: address.street, city: address.city, country: address.country);',
        ),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Case 2 — @glMapField aliases
  // -------------------------------------------------------------------------

  group('Case 2 — @glMapField aliases', () {
    test('toPerson() requires only the missing id param', () {
      expect(
        _lines(_case2, 'CreatePersonInput'),
        containsAllInOrder([
          'Person toPerson({',
          'required String id',  // single param — no trailing comma
          '}) {',
        ]),
      );
    });

    test('toPerson() uses alias mapping for fname→firstName, lname→lastName', () {
      final lines = _lines(_case2, 'CreatePersonInput');
      expect(lines, contains('return Person(firstName: fname, lastName: lname, email: email, id: id);'));
    });

    test('fromPerson() reverses aliases: reads firstName→fname, lastName→lname', () {
      final lines = _lines(_case2, 'CreatePersonInput');
      expect(
        lines,
        contains('return CreatePersonInput(fname: person.firstName, lname: person.lastName, email: person.email);'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Case 3 — Nullability mismatch (nullable source → non-null target)
  // -------------------------------------------------------------------------

  group('Case 3 — nullability mismatch', () {
    test('toUser() has required id param and required defaultRole param', () {
      expect(
        _lines(_case3, 'CreateUserInput'),
        containsAllInOrder([
          'User toUser({',
          'required String id,',
          'required String defaultRole',  // last param — no trailing comma
          '}) {',
        ]),
      );
    });

    test('toUser() uses ?? for role assignment', () {
      final lines = _lines(_case3, 'CreateUserInput');
      expect(lines, contains('return User(username: username, role: role ?? defaultRole, id: id);'));
    });

    test('fromUser() has no extra params beyond the required User instance', () {
      expect(
        _lines(_case3, 'CreateUserInput'),
        containsAllInOrder([
          'static CreateUserInput fromUser({',
          'required User user',
          '}) {',
        ]),
      );
    });

    test('fromUser() maps username and role directly', () {
      final lines = _lines(_case3, 'CreateUserInput');
      expect(
        lines,
        contains('return CreateUserInput(username: user.username, role: user.role);'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Case 4 — Input-only fields (password, confirmPassword not on Account)
  // -------------------------------------------------------------------------

  group('Case 4 — input-only fields', () {
    test('toAccount() requires only the missing id param', () {
      expect(
        _lines(_case4, 'RegisterAccountInput'),
        containsAllInOrder([
          'Account toAccount({',
          'required String id',  // single param — no trailing comma
          '}) {',
        ]),
      );
    });

    test('toAccount() does not mention password or confirmPassword in assignments', () {
      final lines = _lines(_case4, 'RegisterAccountInput');
      final returnLine = lines.firstWhere((l) => l.startsWith('return Account('));
      expect(returnLine, isNot(contains('password')));
    });

    test('fromAccount() requires the Account instance plus input-only fields', () {
      expect(
        _lines(_case4, 'RegisterAccountInput'),
        containsAllInOrder([
          'static RegisterAccountInput fromAccount({',
          'required Account account,',
          'required String password,',
          'required String confirmPassword',
          '}) {',
        ]),
      );
    });

    test('fromAccount() assigns email and displayName from account and passes through input-only fields', () {
      final lines = _lines(_case4, 'RegisterAccountInput');
      expect(
        lines,
        contains('return RegisterAccountInput(email: account.email, displayName: account.displayName, password: password, confirmPassword: confirmPassword);'),
      );
    });
  });
}
