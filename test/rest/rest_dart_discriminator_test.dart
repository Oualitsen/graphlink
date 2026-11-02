import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
interface Pet @glRestDiscriminator(field: "kind") { id: ID! }
interface Animal @glRestDiscriminator(field: "k", values: {Ant: "ant"}) { id: ID! }
type Ant implements Animal { id: ID! }
type Dog implements Pet { id: ID! barks: Boolean }
type Cat implements Pet { id: ID! }
type Owner { id: ID! }
union Hit @glRestDiscriminator(field: "type", values: {Dog: "d", Owner: "o"}) = Dog | Owner
interface Plain { id: ID! }
type Fish implements Plain { id: ID! }
type Query {
  animals: [Animal!]! @glRest(path: "/animals")
  pets: [Pet!]! @glRest(path: "/pets")
  hits: [Hit!]! @glRest(path: "/hits")
}
''';

String _interface(String name) {
  final g = GLParser()..parse(_schema);
  final serializer = DartSerializer(g, importPrefix: '');
  return serializer.serializeInterface(g.interfaces[name]!);
}

void main() {
  test('an interface with a discriminator decodes __typename first, then the discriminator value', () {
    final out = _interface('Pet');
    expect(out, contains("json['__typename']"));
    expect(out, contains("json['kind']"));
    expect(out, contains("case 'Dog':"));
    expect(out, contains("case 'Dog':"));
    expect(out, contains("case 'Cat':"));
    expect(out.indexOf("json['__typename']"), lessThan(out.indexOf("json['kind']")));
  });

  test('an unknown discriminator value is an error naming the parent', () {
    expect(_interface('Pet'), contains('Pet'));
    expect(_interface('Pet'), contains('throw ArgumentError'));
  });

  test('a union uses the values map and falls back to the type name', () {
    final out = _interface('Hit');
    expect(out, contains("json['type']"));
    expect(out, contains("case 'd':"));
    expect(out, contains("case 'o':"));
  });

  test('an interface without a discriminator is unchanged', () {
    final out = _interface('Plain');
    expect(out, contains("json['__typename']"));
    expect(out, isNot(contains('kind')));
  });

  test('values declared on an interface rename its members', () {
    expect(_interface('Animal'), contains("case 'ant':"));
  });
}
