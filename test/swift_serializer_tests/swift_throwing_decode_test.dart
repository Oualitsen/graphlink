import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
interface Pet { id: ID! }
type Dog implements Pet { id: ID! barks: Boolean! }
type Cat implements Pet { id: ID! }

type Owner { id: ID! pet: Pet }
type Shelter { owners: [Owner!]! }
type Kennel { pets: [Pet!]! maybe: [Pet] }
type Plain { id: ID! name: String }

type Query { owner: Owner shelter: Shelter plain: Plain pets: [Pet!]! kennel: Kennel }
''';

void main() {
  late GLParser g;
  late SwiftSerializer s;

  setUp(() {
    g = GLParser()..parse(_schema);
    s = SwiftSerializer(g, importPrefix: 'GraphLinkGenerated');
  });

  String type(String name) => s.serializeTypeDefinition(g.types[name]!);

  group('interface dispatch', () {
    late String pet;
    setUp(() => pet = s.serializeTypeDefinition(g.interfaces['Pet']!));

    test('fromJson throws instead of crashing on an unknown __typename', () {
      expect(pet, contains('public static func fromJson(_ map: [String: Any?]) throws -> any Pet'));
      expect(pet, contains('throw GraphLinkDecodeError'));
      expect(pet, isNot(contains('fatalError')));
    });

    test('the unknown typename is named in the error', () {
      expect(pet, contains('Pet'));
      expect(pet, contains('__typename'));
    });

    test('members are decoded without try when they cannot fail', () {
      expect(pet, contains('return Dog.fromJson(map)'));
      expect(pet, isNot(contains('try Dog.fromJson')));
    });
  });

  group('types holding a polymorphic value', () {
    test('a direct interface field makes fromJson throw and calls the dispatch with try', () {
      final owner = type('Owner');
      expect(owner, contains('public static func fromJson(_ map: [String: Any?]) throws -> Owner'));
      expect(owner, contains('try PetJson.fromJson'));
    });

    test('a nullable interface field keeps the optional map and tries inside the closure', () {
      final owner = type('Owner');
      expect(owner, matches(RegExp(r'try \(map\["pet"\][^\n]*as\? \[String: Any\?\]\)\.map \{ try PetJson\.fromJson')));
    });

    test('a list of interfaces tries the map and the element decode', () {
      final kennel = type('Kennel');
      expect(kennel, contains('throws -> Kennel'));
      expect(kennel, contains('try (map["pets"] as! [Any?]).map { e0 in try PetJson.fromJson'));
    });

    test('throwing propagates through an object that holds such an object', () {
      final shelter = type('Shelter');
      expect(shelter, contains('throws -> Shelter'));
      expect(shelter, contains('try'));
      expect(shelter, contains('Owner.fromJson'));
    });
  });

  group('types that cannot fail', () {
    test('a plain type is unchanged', () {
      final plain = type('Plain');
      expect(plain, contains('public static func fromJson(_ map: [String: Any?]) -> Plain'));
      expect(plain, isNot(contains('throws')));
      expect(plain, isNot(contains('try')));
    });

    test('a member of a dispatch is unchanged', () {
      final dog = type('Dog');
      expect(dog, isNot(contains('throws')));
    });
  });
}
