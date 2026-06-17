import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';

GLParser _parser(String schema, {bool validate = true}) {
  final g = GLParser(identityFields: ['id'], mode: CodeGenerationMode.client);
  g.parse(schema, validate: validate);
  return g;
}

void main() {
  group('validateDefaultValues', () {
    test('accepts null for nullable field in default object', () {
      expect(
        () => _parser('''
          input Address { city: String zip: String }
          input CreateUserInput { name: String! addr: Address = {city: null, zip: "75000"} }
        '''),
        returnsNormally,
      );
    });

    test('rejects null for non-null field in default object', () {
      expect(
        () => _parser('''
          input Address { city: String! zip: String! }
          input CreateUserInput { name: String! addr: Address = {city: null, zip: "75000"} }
        '''),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains("null is not valid for non-null type 'String'"),
        )),
      );
    });

    test('rejects null inside list of input objects', () {
      expect(
        () => _parser('''
          input Address { city: String! }
          input CreateUserInput { name: String! contacts: [Address] = [{city: null}] }
        '''),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains("null is not valid for non-null type 'String'"),
        )),
      );
    });

    test('rejects null inside nested list of input objects', () {
      expect(
        () => _parser('''
          input Address { city: String! }
          input CreateUserInput { name: String! matrix: [[Address]] = [[{city: null}]] }
        '''),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains("null is not valid for non-null type 'String'"),
        )),
      );
    });

    test('rejects unknown field in default object', () {
      expect(
        () => _parser('''
          input Address { city: String! }
          input CreateUserInput { name: String! addr: Address = {city: "Paris", unknown: "x"} }
        '''),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains("Unknown field 'unknown' in default value for input type 'Address'"),
        )),
      );
    });

    test('accepts valid nested default values', () {
      expect(
        () => _parser('''
          input Address { city: String! zip: String! }
          input CreateUserInput {
            name: String!
            addr: Address = {city: "Paris", zip: "75000"}
            contacts: [Address] = [{city: "Lyon", zip: "69000"}]
          }
        '''),
        returnsNormally,
      );
    });

    test('accepts valid default on type field argument', () {
      expect(
        () => _parser('''
          type Query { users(limit: Int! = 10): [String] }
        '''),
        returnsNormally,
      );
    });

    test('rejects null for non-null type field argument default', () {
      expect(
        () => _parser('''
          type Query { users(limit: Int! = null): [String] }
        '''),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains("null is not valid for non-null type 'Int'"),
        )),
      );
    });

    test('rejects null for non-null field inside type field argument default object', () {
      expect(
        () => _parser('''
          input UserFilter { name: String! role: String }
          type Query { users(filter: UserFilter = {name: null, role: "admin"}): [String] }
        '''),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains("null is not valid for non-null type 'String'"),
        )),
      );
    });

    test('rejects unknown field in type field argument default object', () {
      expect(
        () => _parser('''
          input UserFilter { name: String! }
          type Query { users(filter: UserFilter = {name: "ok", unknown: "bad"}): [String] }
        '''),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains("Unknown field 'unknown' in default value for input type 'UserFilter'"),
        )),
      );
    });

    test('accepts enum default on type field argument', () {
      expect(
        () => _parser('''
          enum Role { ADMIN USER }
          type Query { users(role: Role = ADMIN): [String] }
        '''),
        returnsNormally,
      );
    });
  });
}
