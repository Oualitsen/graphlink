import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------



const _directives = '''
  directive @glMapsTo(type: String!) on INPUT_OBJECT
  directive @glMapField(to: String!) on INPUT_FIELD_DEFINITION
''';

/// Serializes [inputName] from [schema] in class+builder mode.
String _class(String schema, String inputName) {
  final g = GLParser(mode: CodeGenerationMode.server)
    ..parse('$_directives $schema');
  return JavaSerializer(g, importPrefix: "", typeMapOverrides: {"Boolean": "boolean"})
      .serializeInputDefinition(g.inputs[inputName]!);
}

/// Serializes [inputName] from [schema] in record mode (inputs + types as records).
String _record(String schema, String inputName) {
  final g = GLParser(mode: CodeGenerationMode.server)
    ..parse('$_directives $schema');
  return JavaSerializer(g,
          importPrefix: '',
          inputsAsRecords: true,
          typesAsRecords: true)
      .serializeInputDefinition(g.inputs[inputName]!);
}

// ---------------------------------------------------------------------------
// Case 1 — All fields match by name, no extras, no nullability mismatch
// ---------------------------------------------------------------------------

const _case1 = '''
  type Address { street: String!  city: String!  country: String! }
  input CreateAddressInput @glMapsTo(type: "Address") {
    street: String!  city: String!  country: String!
  }
  type Query { noop: String }
''';

void _case1Tests() {
  group('Case 1 — all fields match', () {
    group('class mode', () {
      late String out;
      setUp(() => out = _class(_case1, 'CreateAddressInput'));

      test('toAddress() has no extra params', () {
        expect(out, contains('public Address toAddress()'));
      });
      test('toAddress() uses builder with getters', () {
        expect(out, contains('.street(getStreet())'));
        expect(out, contains('.city(getCity())'));
        expect(out, contains('.country(getCountry())'));
      });
    });

    group('record mode', () {
      late String out;
      setUp(() => out = _record(_case1, 'CreateAddressInput'));

      test('input is a record', () {
        expect(out, contains('public record CreateAddressInput('));
      });
      test('toAddress() uses new constructor with component accessors', () {
        expect(out, contains('return new Address('));
        expect(out, contains('street()'));
        expect(out, contains('city()'));
        expect(out, contains('country()'));
      });
      test('toAddress() does not call builder()', () {
        expect(out, isNot(contains('.builder()')));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 2 — @glMapField aliases
// ---------------------------------------------------------------------------

const _case2 = '''
  type Person { id: String!  firstName: String!  lastName: String!  email: String! }
  input CreatePersonInput @glMapsTo(type: "Person") {
    fname: String! @glMapField(to: "firstName")
    lname: String! @glMapField(to: "lastName")
    email: String!
  }
  type Query { noop: String }
''';

void _case2Tests() {
  group('Case 2 — @glMapField aliases', () {
    group('class mode', () {
      late String out;
      setUp(() => out = _class(_case2, 'CreatePersonInput'));

      test('toP uses required id param', () {
        expect(out, contains('public Person toPerson(String id)'));
      });
      test('toP maps alias fname → firstName via getter', () {
        expect(out, contains('.firstName(getFname())'));
      });
    });

    group('record mode', () {
      late String out;
      setUp(() => out = _record(_case2, 'CreatePersonInput'));

      test('toP maps alias fname → firstName via component accessor', () {
        expect(out, contains('fname()'));
        expect(out, isNot(contains('getFname()')));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 3 — Nullability mismatch: nullable source → non-null target
// ---------------------------------------------------------------------------

const _case3 = '''
  type User { id: String!  username: String!  role: String! }
  input CreateUserInput @glMapsTo(type: "User") {
    username: String!
    role: String
  }
  type Query { noop: String }
''';

void _case3Tests() {
  group('Case 3 — nullability mismatch (nullable source → non-null target)', () {
    group('class mode', () {
      late String out;
      setUp(() => out = _class(_case3, 'CreateUserInput'));

      test('toUser has required id and defaultRole params', () {
        expect(out, contains('public User toUser(String id, String defaultRole)'));
      });
      test('toUser uses ternary with getter for null check', () {
        expect(out, contains('getRole() != null ? getRole() : defaultRole'));
      });
    });

    group('record mode', () {
      late String out;
      setUp(() => out = _record(_case3, 'CreateUserInput'));

      test('toUser uses ternary with component accessor', () {
        expect(out, contains('role() != null ? role() : defaultRole'));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 4 — Input-only fields
// ---------------------------------------------------------------------------

const _case4 = '''
  type Account { id: String!  email: String!  displayName: String! }
  input RegisterAccountInput @glMapsTo(type: "Account") {
    email: String!
    displayName: String!
    password: String!
    confirmPassword: String!
  }
  type Query { noop: String }
''';

void _case4Tests() {
  group('Case 4 — input-only fields', () {
    group('class mode', () {
      late String out;
      setUp(() => out = _class(_case4, 'RegisterAccountInput'));

      test('toAccount maps email and displayName, not password', () {
        expect(out, contains('.email(getEmail())'));
        expect(out, contains('.displayName(getDisplayName())'));
        // builder must not forward password to the target type
        expect(out, isNot(contains('.password(')));
      });
      test('fromAccount takes input-only fields as params', () {
        expect(out, contains('String password, String confirmPassword'));
      });
    });

    group('record mode', () {
      late String out;
      setUp(() => out = _record(_case4, 'RegisterAccountInput'));

      test('toAccount uses component accessors, not password', () {
        expect(out, contains('email()'));
        expect(out, contains('displayName()'));
        // constructor must not forward password to the target type
        expect(out, isNot(contains('password()')));
      });
      test('fromAccount still takes input-only fields as params', () {
        expect(out, contains('String password, String confirmPassword'));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 5 — Mix: alias + nullability mismatch + missing field + input-only
// ---------------------------------------------------------------------------

const _case5 = '''
  type Product { id: String!  title: String!  priceInCents: Int!  stock: Int!  categoryId: String! }
  input CreateProductInput @glMapsTo(type: "Product") {
    name: String!   @glMapField(to: "title")
    price: Int!     @glMapField(to: "priceInCents")
    stock: Int
    catId: String!  @glMapField(to: "categoryId")
    internalNote: String
  }
  type Query { noop: String }
''';

void _case5Tests() {
  group('Case 5 — mix: alias + nullability mismatch + missing field + input-only', () {
    group('class mode', () {
      late String out;
      setUp(() => out = _class(_case5, 'CreateProductInput'));

      test('toProduct required params: id (missing) and defaultStock (mismatch)', () {
        expect(out, contains('public Product toProduct(String id, Integer defaultStock)'));
      });
      test('toProduct maps alias name → title via getter', () {
        expect(out, contains('.title(getName())'));
      });
      test('toProduct maps alias price → priceInCents via getter', () {
        expect(out, contains('.priceInCents(getPrice())'));
      });
      test('toProduct uses ternary for stock', () {
        expect(out, contains('getStock() != null ? getStock() : defaultStock'));
      });
      test('toProduct maps alias catId → categoryId', () {
        expect(out, contains('.categoryId(getCatId())'));
      });
      test('fromProduct takes internalNote as input-only param', () {
        expect(out, contains('String internalNote'));
      });
    });

    group('record mode', () {
      late String out;
      setUp(() => out = _record(_case5, 'CreateProductInput'));

      test('toProduct maps alias name → title via component accessor', () {
        expect(out, contains('name()'));
        expect(out, isNot(contains('getName()')));
      });
      test('toProduct uses ternary with component accessor for stock', () {
        expect(out, contains('stock() != null ? stock() : defaultStock'));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 6 — Lists (scalar copy, mapped stream, null-guarded, unmapped param)
// ---------------------------------------------------------------------------

const _case6 = '''
  type Tag { id: String!  label: String! }
  input TagInput @glMapsTo(type: "Tag") { id: String!  label: String! }

  type Phone { number: String!  countryCode: String! }
  input PhoneInput { number: String!  countryCode: String! }

  type Order {
    id: String!
    keywords: [String!]!
    notes: [String!]
    tags: [Tag!]!
    optionalTags: [Tag!]
    phones: [Phone!]!
    optionalPhones: [Phone!]
  }
  input CreateOrderInput @glMapsTo(type: "Order") {
    keywords: [String!]!
    notes: [String!]
    tags: [TagInput!]!
    optionalTags: [TagInput!]
    phones: [PhoneInput!]!
    optionalPhones: [PhoneInput!]
  }
  type Query { noop: String }
''';

void _case6Tests() {
  group('Case 6 — lists', () {
    group('class mode', () {
      late String out;
      setUp(() => out = _class(_case6, 'CreateOrderInput'));

      test('toOrder required params: id, phones, optionalPhones', () {
        expect(out, contains('public Order toOrder(String id, List<Phone> phones, List<Phone> optionalPhones)'));
      });
      test('toOrder maps non-null tag list via stream', () {
        expect(out, contains('getTags().stream().map(e0 -> e0.toTag()).collect(Collectors.toList())'));
      });
      test('toOrder null-guards optional tag list', () {
        expect(out, contains('getOptionalTags() == null ? null : getOptionalTags().stream().map(e0 -> e0.toTag()).collect(Collectors.toList())'));
      });
    });

    group('record mode', () {
      late String out;
      setUp(() => out = _record(_case6, 'CreateOrderInput'));

      test('toOrder maps tag list via component accessor stream', () {
        expect(out, contains('tags().stream().map(e0 -> e0.toTag()).collect(Collectors.toList())'));
        expect(out, isNot(contains('getTags()')));
      });
      test('toOrder null-guards optional tags via component accessor', () {
        expect(out, contains('optionalTags() == null ? null : optionalTags().stream()'));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 7 — Scalar list nullability combos
// ---------------------------------------------------------------------------

const _case7 = '''
  type ScalarListA { tags: [String!]! }
  input ScalarListInputA @glMapsTo(type: "ScalarListA") { tags: [String!]! }

  type ScalarListB { tags: [String!]! }
  input ScalarListInputB @glMapsTo(type: "ScalarListB") { tags: [String!] }

  type ScalarListC { tags: [String!] }
  input ScalarListInputC @glMapsTo(type: "ScalarListC") { tags: [String!]! }

  type ScalarListD { tags: [String!] }
  input ScalarListInputD @glMapsTo(type: "ScalarListD") { tags: [String!] }
  type Query { noop: String }
''';

void _case7Tests() {
  group('Case 7 — scalar list nullability combos', () {
    group('class mode', () {
      test('A: [String!]! → [String!]! — toScalarListA() no params, direct copy', () {
        final out = _class(_case7, 'ScalarListInputA');
        expect(out, contains('public ScalarListA toScalarListA()'));
        expect(out, contains('.tags(getTags())'));
      });
      test('B: [String!] → [String!]! — toScalarListB(defaultTags), ternary', () {
        final out = _class(_case7, 'ScalarListInputB');
        expect(out, contains('public ScalarListB toScalarListB(List<String> defaultTags)'));
        expect(out, contains('getTags() != null ? getTags() : defaultTags'));
      });
      test('D: [String!] → [String!] — both nullable, direct copy', () {
        final out = _class(_case7, 'ScalarListInputD');
        expect(out, contains('public ScalarListD toScalarListD()'));
        expect(out, isNot(contains('defaultTags')));
      });
    });

    group('record mode', () {
      test('A: toScalarListA uses component accessor directly', () {
        final out = _record(_case7, 'ScalarListInputA');
        expect(out, contains('tags()'));
        expect(out, isNot(contains('getTags()')));
      });
      test('B: ternary uses component accessor', () {
        final out = _record(_case7, 'ScalarListInputB');
        expect(out, contains('tags() != null ? tags() : defaultTags'));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 8 — Enum list nullability combos
// ---------------------------------------------------------------------------

const _case8 = '''
  enum Status { ACTIVE INACTIVE PENDING }
  type EnumListA { statuses: [Status!]! }
  input EnumListInputA @glMapsTo(type: "EnumListA") { statuses: [Status!]! }
  type EnumListB { statuses: [Status!]! }
  input EnumListInputB @glMapsTo(type: "EnumListB") { statuses: [Status!] }
  type EnumListC { statuses: [Status!] }
  input EnumListInputC @glMapsTo(type: "EnumListC") { statuses: [Status!]! }
  type Query { noop: String }
''';

void _case8Tests() {
  group('Case 8 — enum list nullability combos', () {
    group('class mode', () {
      test('A: [Status!]! → [Status!]! — no params, direct copy', () {
        final out = _class(_case8, 'EnumListInputA');
        expect(out, contains('public EnumListA toEnumListA()'));
        expect(out, contains('.statuses(getStatuses())'));
      });
      test('B: [Status!] → [Status!]! — defaultStatuses param, ternary', () {
        final out = _class(_case8, 'EnumListInputB');
        expect(out, contains('public EnumListB toEnumListB(List<Status> defaultStatuses)'));
        expect(out, contains('getStatuses() != null ? getStatuses() : defaultStatuses'));
      });
    });

    group('record mode', () {
      test('B: ternary uses component accessor', () {
        final out = _record(_case8, 'EnumListInputB');
        expect(out, contains('statuses() != null ? statuses() : defaultStatuses'));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 9 — Nested mapped input list where nested toXxx() requires params
// ---------------------------------------------------------------------------

const _case9 = '''
  type ItemTag { id: String!  labels: [String!]! }
  input ItemTagInput @glMapsTo(type: "ItemTag") {
    id: String!
    labels: [String!]
  }
  type CartItem { id: String!  tags: [ItemTag!]! }
  input CartItemInput @glMapsTo(type: "CartItem") {
    id: String!
    tags: [ItemTagInput!]!
  }
  type Query { noop: String }
''';

void _case9Tests() {
  group('Case 9 — nested mapped input list with required params', () {
    group('ItemTagInput', () {
      group('class mode', () {
        late String out;
        setUp(() => out = _class(_case9, 'ItemTagInput'));

        test('toItemTag has defaultLabels param', () {
          expect(out, contains('public ItemTag toItemTag(List<String> defaultLabels)'));
        });
        test('toItemTag uses ternary for labels', () {
          expect(out, contains('getLabels() != null ? getLabels() : defaultLabels'));
        });
      });

      group('record mode', () {
        late String out;
        setUp(() => out = _record(_case9, 'ItemTagInput'));

        test('toItemTag uses component accessor in ternary', () {
          expect(out, contains('labels() != null ? labels() : defaultLabels'));
        });
      });
    });

    group('CartItemInput', () {
      group('class mode', () {
        late String out;
        setUp(() => out = _class(_case9, 'CartItemInput'));

        test('toCartItem promotes tags to required param', () {
          expect(out, contains('public CartItem toCartItem(List<ItemTag> tags)'));
        });
        test('toCartItem does not auto-map tags via stream', () {
          final method = out.substring(out.indexOf('public CartItem toCartItem'));
          expect(method, isNot(contains('stream().map')));
        });
      });

      group('record mode', () {
        late String out;
        setUp(() => out = _record(_case9, 'CartItemInput'));

        test('toCartItem still promotes tags to required param', () {
          expect(out, contains('public CartItem toCartItem(List<ItemTag> tags)'));
        });
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 10 — List of list with element nullability mismatch
// ---------------------------------------------------------------------------

const _case10 = '''
  type Cell { value: String! }
  input CellInput @glMapsTo(type: "Cell") { value: String! }
  type Grid { cells: [[Cell]]! }
  input GridInput @glMapsTo(type: "Grid") { cells: [[CellInput!]]! }
  type Query { noop: String }
''';

void _case10Tests() {
  group('Case 10 — list of list with element nullability mismatch', () {
    group('CellInput', () {
      group('class mode', () {
        late String out;
        setUp(() => out = _class(_case10, 'CellInput'));

        test('toCell() has no params', () {
          expect(out, contains('public Cell toCell()'));
        });
        test('toCell uses builder with getter', () {
          expect(out, contains('.value(getValue())'));
        });
      });

      group('record mode', () {
        late String out;
        setUp(() => out = _record(_case10, 'CellInput'));

        test('toCell uses new constructor with component accessor', () {
          expect(out, contains('return new Cell('));
          expect(out, contains('value()'));
          expect(out, isNot(contains('getValue()')));
        });
      });
    });

    group('GridInput', () {
      group('class mode', () {
        late String out;
        setUp(() => out = _class(_case10, 'GridInput'));

        test('toGrid() has no params', () {
          expect(out, contains('public Grid toGrid()'));
        });
        test('toGrid maps nested list with null-guard on inner row', () {
          expect(out, contains('e0 == null ? null : e0.stream().map(e1 -> e1.toCell())'));
        });
        test('fromGrid is not generated — target instance would be unused', () {
          expect(out, isNot(contains('fromGrid')));
        });
      });

      group('record mode', () {
        late String out;
        setUp(() => out = _record(_case10, 'GridInput'));

        test('toGrid uses component accessor cells()', () {
          expect(out, contains('cells()'));
          expect(out, isNot(contains('getCells()')));
        });
        test('fromGrid is not generated — target instance would be unused', () {
          expect(out, isNot(contains('fromGrid')));
        });
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 11 — Boolean fields: primitive boolean uses isXxx(), boxed Boolean uses getXxx()
// ---------------------------------------------------------------------------

const _case11 = '''
  type Person {
    man: Boolean!
    woman: Boolean
  }
  input PersonInput @glMapsTo(type: "Person") {
    man: Boolean!
    woman: Boolean
  }
  type Query { noop: String }
''';

void _case11Tests() {
  group('Case 11 — boolean getter prefix: primitive boolean → isXxx(), boxed Boolean → getXxx()', () {
    group('class mode', () {
      late String out;
      setUp(() => out = _class(_case11, 'PersonInput'));

      test('toP uses isMan() for primitive boolean source field', () {
        expect(out, contains('.man(isMan())'));
        expect(out, isNot(contains('.man(getMan())')));
      });
      test('toP uses getWoman() for boxed Boolean source field', () {
        expect(out, contains('getWoman()'));
        expect(out, isNot(contains('isWoman()')));
      });
      
    });

    group('record mode', () {
      late String out;
      setUp(() => out = _record(_case11, 'PersonInput'));

      test('records always use component accessors (no is/get prefix)', () {
        expect(out, contains('man()'));
        expect(out, contains('woman()'));
        expect(out, isNot(contains('isMan()')));
        expect(out, isNot(contains('getMan()')));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

void main() {
  _case1Tests();
  _case2Tests();
  _case3Tests();
  _case4Tests();
  _case5Tests();
  _case6Tests();
  _case7Tests();
  _case8Tests();
  _case9Tests();
  _case10Tests();
  _case11Tests();
}
