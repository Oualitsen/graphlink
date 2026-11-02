import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _types = '''
type Owner { name: String }
interface Pet { id: ID! }
type Dog implements Pet { id: ID! barks: Boolean }
type Cat implements Pet { id: ID! lives: Int }
''';

GLParser _parse(String body) => GLParser()..parse('$_types$body');

void expectError(String body, Pattern message) {
  expect(() => _parse(body),
      throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));
}

void main() {
  group('interfaces', () {
    test('values default to the type names', () {
      final g = GLParser()
        ..parse('''
          type Owner { name: String }
          interface Pet @glRestDiscriminator(field: "kind") { id: ID! }
          type Dog implements Pet { id: ID! }
          type Cat implements Pet { id: ID! }
          type Query { pet: Pet @glRest(path: "/pet") }
        ''');
      final d = g.restDiscriminators['Pet']!;
      expect(d.field, 'kind');
      expect(d.valueByType, {'Dog': 'Dog', 'Cat': 'Cat'});
      expect(d.typeByValue, {'Dog': 'Dog', 'Cat': 'Cat'});
    });

    test('values override the defaults and keep the others', () {
      final g = GLParser()
        ..parse('''
          interface Pet @glRestDiscriminator(field: "kind", values: {Dog: "dog"}) { id: ID! }
          type Dog implements Pet { id: ID! }
          type Cat implements Pet { id: ID! }
          type Query { pet: Pet }
        ''');
      expect(g.restDiscriminators['Pet']!.valueByType, {'Dog': 'dog', 'Cat': 'Cat'});
      expect(g.restDiscriminators['Pet']!.typeByValue, {'dog': 'Dog', 'Cat': 'Cat'});
    });
  });

  group('unions', () {
    test('a union is resolved under its own name, converted interface included', () {
      final g = _parse('''
        union SearchHit @glRestDiscriminator(field: "type", values: {Dog: "dog", Cat: "cat"}) = Dog | Cat | Owner
        type Query { search: [SearchHit!]! }
      ''');
      final d = g.restDiscriminators['SearchHit']!;
      expect(d.field, 'type');
      expect(d.valueByType, {'Dog': 'dog', 'Cat': 'cat', 'Owner': 'Owner'});
      expect(g.interfaces.containsKey('SearchHit'), isTrue);
    });
  });

  group('no directive', () {
    test('nothing is registered', () {
      final g = _parse('type Query { pet: Pet }');
      expect(g.restDiscriminators, isEmpty);
    });
  });

  group('errors', () {
    test('missing field argument', () {
      expectError('union U @glRestDiscriminator = Dog | Cat\ntype Query { u: U }', 'field');
    });

    test('values naming a type that is not a member', () {
      expectError('union U @glRestDiscriminator(field: "t", values: {Owner: "o"}) = Dog | Cat\ntype Query { u: U }', 'Owner');
    });

    test('two members with the same value', () {
      expectError('union U @glRestDiscriminator(field: "t", values: {Dog: "x", Cat: "x"}) = Dog | Cat\ntype Query { u: U }', "'x'");
    });

    test('a value colliding with a default type name', () {
      expectError('union U @glRestDiscriminator(field: "t", values: {Dog: "Cat"}) = Dog | Cat\ntype Query { u: U }', "'Cat'");
    });

    test('only on interfaces and unions', () {
      expectError('type Plain @glRestDiscriminator(field: "t") { id: ID }\ntype Query { p: Plain }', 'cannot be used on OBJECT (allowed: INTERFACE, UNION)');
    });
  });
}
