import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  GLParser parser() =>
      GLParser(autoGenerateQueries: false, generateAllFieldsFragments: false);

  group('$glSkipOnClient / $glSkipOnServer on input fields — invalid', () {
    test('$glSkipOnClient on an input field throws', () {
      const schema = '''
        input CreateUserInput {
          name: String!
          internalNote: String $glSkipOnClient
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains(glSkipOnClient),
        )),
      );
    });

    test('$glSkipOnServer on an input field throws', () {
      const schema = '''
        input CreateUserInput {
          name: String!
          serverOnlyNote: String $glSkipOnServer
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains(glSkipOnServer),
        )),
      );
    });
  });

  group('$glSkipOnServer with mapTo on input — invalid', () {
    test('$glSkipOnServer(mapTo: ...) on an input throws', () {
      const schema = '''
        input CreateUserInput @glSkipOnServer(mapTo: "ServerUserInput") {
          name: String!
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          allOf(contains(glSkipOnServer), contains(glMapTo)),
        )),
      );
    });
  });

  group('$glSkipOnServer input referenced elsewhere — invalid', () {
    test('referenced as a field of another input throws', () {
      const schema = '''
        input SkippedInput $glSkipOnServer {
          name: String!
        }

        input WrapperInput {
          nested: SkippedInput!
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains('SkippedInput'),
        )),
      );
    });

    test('referenced as a type field argument throws', () {
      const schema = '''
        scalar ID

        input SkippedInput $glSkipOnServer {
          name: String!
        }

        type User { id: ID! }

        type Mutation {
          createUser(input: SkippedInput!): User!
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains('SkippedInput'),
        )),
      );
    });
  });

  group('$glSkipOnServer(mapTo:) pointing to a skipped type — invalid', () {
    test('mapTo target also marked $glSkipOnServer throws', () {
      const schema = '''
        type Foo $glSkipOnServer {
          name: String!
        }

        type Bar @glSkipOnServer(mapTo: "Foo") {
          name: String!
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Foo'), contains(glSkipOnServer)),
        )),
      );
    });

    test('mapTo target not skipped is allowed', () {
      const schema = '''
        type Foo {
          name: String!
        }

        type Bar @glSkipOnServer(mapTo: "Foo") {
          name: String!
        }
      ''';

      expect(() => parser().parse(schema), returnsNormally);
    });
  });

  group('$glSkipOnServer(mapTo:) on a type field — invalid', () {
    test('$glSkipOnServer with mapTo on a type field throws', () {
      const schema = '''
        type Company { id: String! }

        type User {
          company: Company! @glSkipOnServer(mapTo: "something")
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          allOf(contains(glSkipOnServer), contains(glMapTo)),
        )),
      );
    });

    test('$glSkipOnServer without mapTo on a type field is allowed', () {
      const schema = '''
        type Company { id: String! }

        type User {
          company: Company! $glSkipOnServer
        }
      ''';

      expect(() => parser().parse(schema), returnsNormally);
    });

    test('field $glSkipOnServer + type $glSkipOnServer without mapTo throws', () {
      const schema = '''
        type Company $glSkipOnServer { id: String! }

        type User {
          company: Company! $glSkipOnServer
        }
      ''';

      expect(
        () => parser().parse(schema),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Company'), contains(glMapTo)),
        )),
      );
    });

    test('field $glSkipOnServer + type @glSkipOnServer(mapTo:) is allowed', () {
      const schema = '''
        type ServerCompany { id: String! }
        type Company @glSkipOnServer(mapTo: "ServerCompany") { id: String! }

        type User {
          company: Company! $glSkipOnServer
        }
      ''';

      expect(() => parser().parse(schema), returnsNormally);
    });
  });

  group('$glSkipOnClient / $glSkipOnServer on input type — valid', () {
    test('$glSkipOnClient on an input type is allowed', () {
      const schema = '''
        input ServerOnlyInput $glSkipOnClient {
          name: String!
        }
      ''';

      expect(() => parser().parse(schema), returnsNormally);
    });

    test('$glSkipOnServer on an input type is allowed', () {
      const schema = '''
        input ClientOnlyInput $glSkipOnServer {
          name: String!
        }
      ''';

      expect(() => parser().parse(schema), returnsNormally);
    });
  });
}
