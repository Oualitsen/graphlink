import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:test/test.dart';

GLParser _parser() => GLParser(mode: CodeGenerationMode.server);

List<String> _lines(String schema, String inputName) {
  final g = _parser()..parse(schema);
  final input = g.inputs[inputName]!;
  final result = SwiftSerializer(g, importPrefix: 'GraphLinkGenerated').serializeInputDefinition(input);
  return result.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
}

// ── Schemas ──────────────────────────────────────────────────────────────────

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

const _nestedMapped = '''
  input PeriodInput @glMapsTo(type: "Period") {
    value: Int!
    unit: String!
  }

  type Period {
    value: Int!
    unit: String!
  }

  type Equipment {
    id: ID!
    name: String!
    maintenancePeriod: Period!
  }

  input EquipmentInput @glMapsTo(type: "Equipment") {
    name: String!
    maintenancePeriod: PeriodInput!
  }

  type Query { noop: String }
''';

const _nestedUnmapped = '''
  input PeriodInput {
    value: Int!
    unit: String!
  }

  type Period {
    value: Int!
    unit: String!
  }

  type Equipment {
    id: ID!
    name: String!
    maintenancePeriod: Period!
  }

  input EquipmentInput @glMapsTo(type: "Equipment") {
    name: String!
    maintenancePeriod: PeriodInput!
  }

  type Query { noop: String }
''';

const _nestedNullable = '''
  input PeriodInput @glMapsTo(type: "Period") {
    value: Int!
    unit: String!
  }

  type Period {
    value: Int!
    unit: String!
  }

  type Equipment {
    id: ID!
    name: String!
    maintenancePeriod: Period
  }

  input EquipmentInput @glMapsTo(type: "Equipment") {
    name: String!
    maintenancePeriod: PeriodInput
  }

  type Query { noop: String }
''';

const _tokenAlias = '''
  type Ensurer {
    id: ID!
    payerCenterId: ID!
    name: String!
  }

  input EnsurerInput @glMapsTo(type: "Ensurer") {
    payerCenterId: String!
    name: String!
  }

  type Query { noop: String }
''';

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Case 1 — all fields match by name', () {
    test('toAddress() is an instance method with no parameters', () {
      final lines = _lines(_case1, 'CreateAddressInput');
      expect(lines, contains('public func toAddress() -> Address {'));
    });

    test('toAddress() assigns all fields as labeled args', () {
      final lines = _lines(_case1, 'CreateAddressInput');
      expect(lines, containsAll(['street: street,', 'city: city,', 'country: country']));
    });


  });

  group('Case 2 — @glMapField aliases', () {
    test('toPerson() requires only the missing id param', () {
      final lines = _lines(_case2, 'CreatePersonInput');
      expect(lines, contains('public func toPerson(id: String) -> Person {'));
    });

    test('toPerson() uses alias mapping fname→firstName, lname→lastName', () {
      final lines = _lines(_case2, 'CreatePersonInput');
      expect(lines, containsAll(['firstName: fname,', 'lastName: lname,', 'email: email', 'id: id,']));
    });


  });

  group('Case 3 — nullability mismatch (nullable input → non-null type)', () {
    test('toUser() includes required id param and defaultRole param', () {
      final lines = _lines(_case3, 'CreateUserInput');
      expect(lines, contains('public func toUser(id: String, defaultRole: String) -> User {'));
    });

    test('toUser() uses ?? for nullable role field', () {
      final lines = _lines(_case3, 'CreateUserInput');
      expect(lines, contains('role: role ?? defaultRole'));
    });


  });

  group('Case 4 — input-only fields', () {
    test('toAccount() requires only the missing id param', () {
      final lines = _lines(_case4, 'RegisterAccountInput');
      expect(lines, contains('public func toAccount(id: String) -> Account {'));
    });

    test('toAccount() does not include password or confirmPassword in its assignments', () {
      final lines = _lines(_case4, 'RegisterAccountInput');
      final start = lines.indexWhere((l) => l.startsWith('public func toAccount('));
      final end = lines.indexWhere((l) => l == '}', start);
      final toAccountBlock = lines.sublist(start, end + 1).join('\n');
      expect(toAccountBlock, isNot(contains('password')));
    });


  });

  group('Nested mapped input — auto-mapped via .toPeriod()', () {
    test('toEquipment() signature has no Period param — maintenancePeriod is auto-mapped', () {
      final lines = _lines(_nestedMapped, 'EquipmentInput');
      final sig = lines.firstWhere((l) => l.contains('toEquipment('), orElse: () => '');
      expect(sig, isNot(contains('Period')));
    });

    test('toEquipment() calls maintenancePeriod.toPeriod()', () {
      final body = _lines(_nestedMapped, 'EquipmentInput').join('\n');
      expect(body, contains('maintenancePeriod.toPeriod()'));
    });

  });

  group('Nested unmapped input — becomes required param', () {
    test('toEquipment() signature includes Period maintenancePeriod param', () {
      final lines = _lines(_nestedUnmapped, 'EquipmentInput');
      expect(lines, contains('public func toEquipment(id: String, maintenancePeriod: Period) -> Equipment {'));
    });

    test('toEquipment() passes maintenancePeriod directly (no conversion call)', () {
      final body = _lines(_nestedUnmapped, 'EquipmentInput').join('\n');
      expect(body, isNot(contains('toPeriod()')));
    });
  });

  group('Nullable nested mapped input', () {
    test('toEquipment() uses safe-call ?.toPeriod() for nullable field', () {
      final body = _lines(_nestedNullable, 'EquipmentInput').join('\n');
      expect(body, contains('maintenancePeriod?.toPeriod()'));
    });

  });

  group('String and ID fields sharing serialized type are auto-mapped', () {
    test('toEnsurer() requires only the missing id param', () {
      final lines = _lines(_tokenAlias, 'EnsurerInput');
      expect(lines, contains('public func toEnsurer(id: String) -> Ensurer {'));
    });

    test('toEnsurer() passes payerCenterId directly without conversion', () {
      final body = _lines(_tokenAlias, 'EnsurerInput').join('\n');
      expect(body, contains('payerCenterId: payerCenterId'));
    });
  });
}
