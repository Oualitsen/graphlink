import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _schema = '''
interface Node { id: ID! }
interface Pet implements Node @glRestDiscriminator(field: "kind", values: {Dog: "dog"}) { id: ID! name: String! }
type Dog implements Pet & Node { id: ID! name: String! barks: Boolean! }
type Cat implements Pet & Node { id: ID! name: String! lives: Int! }
type Circle { radius: Float! }
type Square { side: Float! label: String! }
union Shape @glRestDiscriminator(field: "type", values: {Circle: "round"}) = Circle | Square
type Owner { name: String! pets: [Pet!]! favourite: Shape! }
type Query {
  pets: [Pet!]! @glRest(path: "/pets") @glRestNullable
  shape: Shape! @glRest(path: "/shape") @glRestNullable
  owner: Owner! @glRest(path: "/owner") @glRestNullable
  plainPets: [Pet!]! @glRest(path: "/plain")
}
''';

GLParser _parse([String schema = _schema]) => GLParser()..parse(schema);

Set<String> _implementations(GLInterfaceDefinition iface) => iface.implementations.map((t) => t.token).toSet();

String _shape(GLType type) {
  final inner = type is GLListType ? '[${_shape(type.type)}]' : type.tokenInfo.token;
  return type.nullable ? inner : '$inner!';
}

void main() {
  final g = _parse();

  group('interface', () {
    test('the copy is a projected interface implemented by the copied members', () {
      final copy = g.projectedInterfaces['PetRest']!;
      expect(_implementations(copy), {'DogRest', 'CatRest'});
      expect(g.projectedTypes.keys, containsAll(['DogRest', 'CatRest']));
    });

    test('members implement the copy and not the original', () {
      final dog = g.projectedTypes['DogRest']!;
      expect(dog.interfaceNames.map((n) => n.token), contains('PetRest'));
      expect(dog.interfaceNames.map((n) => n.token), isNot(contains('Pet')));
      expect(dog.implements('PetRest'), isTrue);
    });

    test('an interface no REST operation reaches is not carried over', () {
      expect(g.projectedInterfaces.containsKey('NodeRest'), isFalse);
      final names = g.projectedTypes['DogRest']!.interfaceNames.map((n) => n.token);
      expect(names, isNot(contains('Node')));
      expect(names, isNot(contains('NodeRest')));
    });

    test('the fields of the interface and its members are all nullable', () {
      expect(g.projectedInterfaces['PetRest']!.fields.every((f) => f.type.nullable), isTrue);
      expect(g.projectedTypes['DogRest']!.fields.every((f) => f.type.nullable), isTrue);
      expect(g.projectedTypes['CatRest']!.fields.every((f) => f.type.nullable), isTrue);
    });

    test('the original interface and its members are untouched', () {
      expect(_implementations(g.projectedInterfaces['Pet']!), {'Dog', 'Cat'});
      expect(g.projectedTypes['Dog']!.fields.firstWhere((f) => f.name.token == 'barks').type.nullable, isFalse);
    });
  });

  group('discriminator', () {
    test('is copied with the original wire values', () {
      final copy = g.restDiscriminators['PetRest']!;
      expect(copy.parent, 'PetRest');
      expect(copy.field, 'kind');
      expect(copy.valueByType, {'DogRest': 'dog', 'CatRest': 'Cat'});
      expect(copy.typeByValue, {'dog': 'DogRest', 'Cat': 'CatRest'});
    });

    test('the original discriminator is untouched', () {
      expect(g.restDiscriminators['Pet']!.valueByType, {'Dog': 'dog', 'Cat': 'Cat'});
    });
  });

  group('union', () {
    test('is copied as an interface implemented by the copied members', () {
      expect(_implementations(g.projectedInterfaces['ShapeRest']!), {'CircleRest', 'SquareRest'});
      expect(g.projectedTypes.keys, containsAll(['CircleRest', 'SquareRest']));
    });

    test('its discriminator keeps the original wire values', () {
      final copy = g.restDiscriminators['ShapeRest']!;
      expect(copy.field, 'type');
      expect(copy.valueByType, {'CircleRest': 'round', 'SquareRest': 'Square'});
    });
  });

  group('operations and references', () {
    GLRestOperation operation(String name) => g.restOperations.values.firstWhere((o) => o.name == name);

    test('operations return the copies', () {
      expect(_shape(operation('pets').field.type), '[PetRest!]!');
      expect(_shape(operation('shape').field.type), 'ShapeRest!');
    });

    test('a nested field that reaches an interface or union points at the copy', () {
      final owner = g.projectedTypes['OwnerRest']!;
      expect(_shape(owner.fields.firstWhere((f) => f.name.token == 'pets').type), '[PetRest!]');
      expect(_shape(owner.fields.firstWhere((f) => f.name.token == 'favourite').type), 'ShapeRest');
    });

    test('an operation that is not opted in keeps the original interface', () {
      expect(_shape(operation('plainPets').field.type), '[Pet!]!');
    });
  });

  group('a member implementing no other interface', () {
    test('works without any extra interface', () {
      final g = _parse('''
        interface Pet @glRestDiscriminator(field: "kind") { name: String! }
        type Dog implements Pet { name: String! }
        type Query { pets: [Pet!]! @glRest(path: "/pets") @glRestNullable }
      ''');
      expect(_implementations(g.projectedInterfaces['PetRest']!), {'DogRest'});
      expect(g.restDiscriminators['PetRest']!.valueByType, {'DogRest': 'Dog'});
    });
  });
}
