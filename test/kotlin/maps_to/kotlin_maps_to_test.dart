import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';

GLParser _parser() => GLParser(mode: CodeGenerationMode.server);

List<String> _lines(String schema, String inputName,
    {bool inputsAsDataClass = true}) {
  final g = _parser()..parse(schema);
  final input = g.inputs[inputName]!;
  final result = KotlinSerializer(
    g,
    inputsAsDataClass: inputsAsDataClass,
    importPrefix: '',
  ).serializeInputDefinition(input);
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
    test('toAddress() has no parameters', () {
      final lines = _lines(_case1, 'CreateAddressInput');
      expect(lines, contains('fun toAddress(): Address = Address('));
    });

    test('toAddress() assigns all fields as named args', () {
      final lines = _lines(_case1, 'CreateAddressInput');
      expect(lines, containsAll(['street = street,', 'city = city,', 'country = country,']));
    });

    test('fromAddress() takes address: Address as first param', () {
      final lines = _lines(_case1, 'CreateAddressInput');
      expect(lines, contains('fun fromAddress(address: Address): CreateAddressInput = CreateAddressInput('));
    });

    test('fromAddress() reads all fields from the Address instance', () {
      final lines = _lines(_case1, 'CreateAddressInput');
      expect(lines, containsAll([
        'street = address.street,',
        'city = address.city,',
        'country = address.country,',
      ]));
    });
  });

  group('Case 2 — @glMapField aliases', () {
    test('toPerson() requires only the missing id param', () {
      final lines = _lines(_case2, 'CreatePersonInput');
      expect(lines, contains('fun toPerson(id: String): Person = Person('));
    });

    test('toPerson() uses alias mapping fname→firstName, lname→lastName', () {
      final lines = _lines(_case2, 'CreatePersonInput');
      expect(lines, containsAll(['firstName = fname,', 'lastName = lname,', 'email = email,', 'id = id,']));
    });

    test('fromPerson() takes person: Person as first param', () {
      final lines = _lines(_case2, 'CreatePersonInput');
      expect(lines, contains('fun fromPerson(person: Person): CreatePersonInput = CreatePersonInput('));
    });

    test('fromPerson() reverses aliases: firstName→fname, lastName→lname', () {
      final lines = _lines(_case2, 'CreatePersonInput');
      expect(lines, containsAll([
        'fname = person.firstName,',
        'lname = person.lastName,',
        'email = person.email,',
      ]));
    });
  });

  group('Case 3 — nullability mismatch (nullable input → non-null type)', () {
    test('toUser() includes required id param and defaultRole param', () {
      final lines = _lines(_case3, 'CreateUserInput');
      expect(lines, contains('fun toUser(id: String, defaultRole: String): User = User('));
    });

    test('toUser() uses if/else for nullable role field', () {
      final lines = _lines(_case3, 'CreateUserInput');
      expect(lines, contains('role = if (role != null) role else defaultRole,'));
    });

    test('fromUser() takes user: User — no extra params needed', () {
      final lines = _lines(_case3, 'CreateUserInput');
      expect(lines, contains('fun fromUser(user: User): CreateUserInput = CreateUserInput('));
    });

    test('fromUser() maps username and role directly', () {
      final lines = _lines(_case3, 'CreateUserInput');
      expect(lines, containsAll(['username = user.username,', 'role = user.role,']));
    });
  });

  group('Case 4 — input-only fields', () {
    test('toAccount() requires only the missing id param', () {
      final lines = _lines(_case4, 'RegisterAccountInput');
      expect(lines, contains('fun toAccount(id: String): Account = Account('));
    });

    test('toAccount() does not include password or confirmPassword in its assignments', () {
      final lines = _lines(_case4, 'RegisterAccountInput');
      // Collect lines inside the toAccount() body (between signature and closing paren)
      final start = lines.indexWhere((l) => l.startsWith('fun toAccount('));
      final end = lines.indexWhere((l) => l == ')', start);
      final toAccountBlock = lines.sublist(start, end + 1).join('\n');
      expect(toAccountBlock, isNot(contains('password')));
    });

    test('fromAccount() includes account: Account and both input-only params', () {
      final lines = _lines(_case4, 'RegisterAccountInput');
      expect(lines, contains('fun fromAccount(account: Account, password: String, confirmPassword: String): RegisterAccountInput = RegisterAccountInput('));
    });

    test('fromAccount() assigns email/displayName from account and passes through input-only fields', () {
      final lines = _lines(_case4, 'RegisterAccountInput');
      expect(lines, containsAll([
        'email = account.email,',
        'displayName = account.displayName,',
        'password = password,',
        'confirmPassword = confirmPassword,',
      ]));
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

    test('fromEquipment() reverses via PeriodInput.fromPeriod()', () {
      final body = _lines(_nestedMapped, 'EquipmentInput').join('\n');
      expect(body, contains('PeriodInput.fromPeriod('));
    });
  });

  group('Nested unmapped input — becomes required param', () {
    test('toEquipment() signature includes Period maintenancePeriod param', () {
      final lines = _lines(_nestedUnmapped, 'EquipmentInput');
      expect(lines, contains('fun toEquipment(id: String, maintenancePeriod: Period): Equipment = Equipment('));
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

    test('fromEquipment() uses ?.let for nullable reverse mapping', () {
      final body = _lines(_nestedNullable, 'EquipmentInput').join('\n');
      expect(body, contains('?.let {'));
    });
  });

  group('String and ID fields sharing serialized type are auto-mapped', () {
    test('toEnsurer() requires only the missing id param', () {
      final lines = _lines(_tokenAlias, 'EnsurerInput');
      expect(lines, contains('fun toEnsurer(id: String): Ensurer = Ensurer('));
    });

    test('toEnsurer() passes payerCenterId directly without conversion', () {
      final body = _lines(_tokenAlias, 'EnsurerInput').join('\n');
      expect(body, contains('payerCenterId = payerCenterId'));
    });
  });
}
