import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  GLParser parser() =>
      GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true);

  // ---------------------------------------------------------------------------
  // Happy path
  // ---------------------------------------------------------------------------

  test("@glMapsTo with exact name match passes", () {
    const text = '''
      type User {
        id: ID!
        email: String!
      }

      input CreateUserInput $glMapsTo(type: "User") {
        id: ID!
        email: String!
      }

      type Query { noop: String }
    ''';

    expect(() => parser().parse(text), returnsNormally);
  });

  test("@glMapsTo with @glMapField alias passes when alias exists on target",
      () {
    const text = '''
      type User {
        id: ID!
        firstName: String!
      }

      input CreateUserInput $glMapsTo(type: "User") {
        id: ID!
        fname: String! $glMapField(to: "firstName")
      }

      type Query { noop: String }
    ''';

    expect(() => parser().parse(text), returnsNormally);
  });

  test("@glMapsTo targeting another input throws ParseException", () {
    const text = '''
      input AddressInput {
        street: String!
        city: String!
      }

      input CreateOrderInput $glMapsTo(type: "AddressInput") {
        street: String!
        city: String!
      }

      type Query { noop: String }
    ''';

    expect(
      () => parser().parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains("$glMapsTo target 'AddressInput' does not exist or is not a type"),
      )),
    );
  });

  test("input without @glMapsTo is unaffected", () {
    const text = '''
      type User {
        id: ID!
      }

      input CreateUserInput {
        email: String!
      }

      type Query { noop: String }
    ''';

    expect(() => parser().parse(text), returnsNormally);
  });

  // ---------------------------------------------------------------------------
  // Error: unknown target
  // ---------------------------------------------------------------------------

  test("@glMapsTo with non-existent target throws ParseException", () {
    const text = '''
      input CreateUserInput $glMapsTo(type: "NonExistent") {
        email: String!
      }

      type Query { noop: String }
    ''';

    expect(
      () => parser().parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains("$glMapsTo target 'NonExistent' does not exist"),
      )),
    );
  });

  // ---------------------------------------------------------------------------
  // Error: @glMapField alias not found on target
  // ---------------------------------------------------------------------------

  test(
      "@glMapField(to: X) where X does not exist on target throws ParseException",
      () {
    const text = '''
      type User {
        id: ID!
        firstName: String!
      }

      input CreateUserInput $glMapsTo(type: "User") {
        id: ID!
        fname: String! $glMapField(to: "fullName")
      }

      type Query { noop: String }
    ''';

    expect(
      () => parser().parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains(
            "$glMapField(to: 'fullName') on field 'fname' does not match any field on target type 'User'"),
      )),
    );
  });

  test("multiple @glMapField errors — first bad alias is caught", () {
    const text = '''
      type User {
        id: ID!
      }

      input CreateUserInput $glMapsTo(type: "User") {
        x: String! $glMapField(to: "doesNotExist")
      }

      type Query { noop: String }
    ''';

    expect(
      () => parser().parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains("$glMapField(to: 'doesNotExist')"),
      )),
    );
  });
}
