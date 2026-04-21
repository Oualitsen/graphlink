import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _typeMapping = {
  "ID": "String",
  "String": "String",
  "Float": "double",
  "Int": "int",
  "Boolean": "bool",
};

const _directives = '''
  directive @glMapsTo(type: String!) on INPUT_OBJECT
  directive @glMapField(to: String!) on INPUT_FIELD_DEFINITION
  directive @glSkipOnClient on FIELD_DEFINITION | OBJECT
  directive @glSkipOnServer(mapTo: String, batch: Boolean) on FIELD_DEFINITION | OBJECT
''';

String _dart(String schema, String inputName, CodeGenerationMode mode) {
  final g = GLParser(typeMap: _typeMapping, mode: mode)
    ..parse('$_directives $schema');
  return DartSerializer(g, generateJsonMethods: false)
      .serializeInputDefinition(g.inputs[inputName]!, '');
}

String _java(String schema, String inputName, CodeGenerationMode mode) {
  final g = GLParser(typeMap: _typeMapping, mode: mode)
    ..parse('$_directives $schema');
  return JavaSerializer(g, generateJsonMethods: false)
      .serializeInputDefinition(g.inputs[inputName]!, '');
}

// ---------------------------------------------------------------------------
// Case 1 — Target type field is @glSkipOnClient; client mode
// The skipped field must NOT appear as a required parameter in toXxx() because
// the generated target class will not have that field at all.
// ---------------------------------------------------------------------------

const _case1 = '''
  type User {
    id: ID!
    name: String!
    internalToken: String! @glSkipOnClient
  }
  input UpdateUserInput @glMapsTo(type: "User") {
    id: ID!
    name: String!
  }
  type Query { noop: String }
''';

void _case1Tests() {
  group('Case 1 — target field @glSkipOnClient in client mode', () {
    group('Dart', () {
      late String out;
      setUp(() => out = _dart(_case1, 'UpdateUserInput', CodeGenerationMode.client));

      test('toUser() has no extra params (internalToken not a required param)', () {
        expect(out, contains('User toUser()'));
        expect(out, isNot(contains('internalToken')));
      });
      test('fromUser() does not reference internalToken', () {
        expect(out, isNot(contains('internalToken')));
      });
    });

    group('Java', () {
      late String out;
      setUp(() => out = _java(_case1, 'UpdateUserInput', CodeGenerationMode.client));

      test('toUser() has no extra params', () {
        expect(out, contains('public User toUser()'));
        expect(out, isNot(contains('internalToken')));
      });
      test('fromUser() does not reference internalToken', () {
        expect(out, isNot(contains('internalToken')));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 2 — Target type field is @glSkipOnServer; server mode
// ---------------------------------------------------------------------------

const _case2 = '''
  type Product {
    id: ID!
    price: Int!
    clientViewUrl: String! @glSkipOnServer
  }
  input CreateProductInput @glMapsTo(type: "Product") {
    id: ID!
    price: Int!
  }
  type Query { noop: String }
''';

void _case2Tests() {
  group('Case 2 — target field @glSkipOnServer in server mode', () {
    group('Dart', () {
      late String out;
      setUp(() => out = _dart(_case2, 'CreateProductInput', CodeGenerationMode.server));

      test('toProduct() has no extra params (clientViewUrl not a required param)', () {
        expect(out, contains('Product toProduct()'));
        expect(out, isNot(contains('clientViewUrl')));
      });
      test('fromProduct() does not reference clientViewUrl', () {
        expect(out, isNot(contains('clientViewUrl')));
      });
    });

    group('Java', () {
      late String out;
      setUp(() => out = _java(_case2, 'CreateProductInput', CodeGenerationMode.server));

      test('toProduct() has no extra params', () {
        expect(out, contains('public Product toProduct()'));
        expect(out, isNot(contains('clientViewUrl')));
      });
      test('fromProduct() does not reference clientViewUrl', () {
        expect(out, isNot(contains('clientViewUrl')));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 3 — Multiple skip fields mixed with normal fields
// Only the non-skipped fields should participate in the mapping.
// ---------------------------------------------------------------------------

const _case3 = '''
  type Order {
    id: ID!
    total: Int!
    internalRef: String! @glSkipOnClient
    auditLog: String!    @glSkipOnClient
  }
  input PlaceOrderInput @glMapsTo(type: "Order") {
    total: Int!
  }
  type Query { noop: String }
''';

void _case3Tests() {
  group('Case 3 — multiple @glSkipOnClient fields on target in client mode', () {
    group('Dart', () {
      late String out;
      setUp(() => out = _dart(_case3, 'PlaceOrderInput', CodeGenerationMode.client));

      test('toOrder() only requires id (internalRef and auditLog filtered out)', () {
        expect(out, contains('required String id'));
        expect(out, isNot(contains('internalRef')));
        expect(out, isNot(contains('auditLog')));
      });
      test('fromOrder() does not reference skipped fields', () {
        expect(out, isNot(contains('internalRef')));
        expect(out, isNot(contains('auditLog')));
      });
    });

    group('Java', () {
      late String out;
      setUp(() => out = _java(_case3, 'PlaceOrderInput', CodeGenerationMode.client));

      test('toOrder() only requires id', () {
        expect(out, contains('public Order toOrder(String id)'));
        expect(out, isNot(contains('internalRef')));
        expect(out, isNot(contains('auditLog')));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Case 4 — Skipped field would have been an auto-mapped field (name match)
// Without the fix, the field would be silently included in the mapping.
// ---------------------------------------------------------------------------

const _case4 = '''
  type Employee {
    id: ID!
    name: String!
    salary: Int! @glSkipOnClient
  }
  input CreateEmployeeInput @glMapsTo(type: "Employee") {
    id: ID!
    name: String!
    salary: Int!
  }
  type Query { noop: String }
''';

void _case4Tests() {
  group('Case 4 — skipped target field that would have been auto-mapped (name match)', () {
    group('Dart', () {
      late String out;
      setUp(() => out = _dart(_case4, 'CreateEmployeeInput', CodeGenerationMode.client));

      test('toEmployee() body maps only id and name, not salary', () {
        expect(out, contains('return Employee(id: id, name: name)'));
      });
      test('fromEmployee() still accepts salary as input-only param', () {
        expect(out, contains('required int salary'));
      });
    });

    group('Java', () {
      late String out;
      setUp(() => out = _java(_case4, 'CreateEmployeeInput', CodeGenerationMode.client));

      test('toEmployee() has no params and does not forward salary to target', () {
        expect(out, contains('public Employee toEmployee()'));
        expect(out, isNot(contains('.salary(')));
      });
      test('fromEmployee() still accepts salary as input-only param', () {
        expect(out, contains('int salary'));
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
}
