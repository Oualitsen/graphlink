import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/swift_serializer.dart';
import 'package:test/test.dart';

SwiftSerializer _serializer(GLParser g) => SwiftSerializer(g, importPrefix: 'GraphLinkGenerated');

/// Trims every line so indentation never breaks containsAllInOrder checks.
Iterable<String> lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

void main() {
  group('type struct', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse('''
        enum Role { admin user }
        type Address { city: String! }
        type User {
          id: ID!
          name: String!
          email: String
          role: Role!
          address: Address
          tags: [String!]!
        }
      ''');
      out = _serializer(g).doSerializeTypeDefinition(g.types['User']!);
    });

    test('conforms to Sendable and Identifiable (has id: ID!)', () {
      expect(lines(out), contains('public struct User: Sendable, Identifiable {'));
    });

    test('non-nullable fields have no inline default', () {
      expect(lines(out), contains('public let id: String'));
      expect(lines(out), contains('public let name: String'));
    });

    test('nullable fields have no inline default either', () {
      expect(lines(out), contains('public let email: String?'));
      expect(lines(out), contains('public let address: Address?'));
    });

    test('init defaults nullable params to nil', () {
      expect(lines(out), containsAllInOrder(['public init(', 'email: String? = nil,']));
    });

    test('toJson emits all fields', () {
      expect(lines(out), containsAllInOrder([
        'public func toJson() -> [String: Any?] {',
        'return [',
        '"id": id,',
        '"name": name,',
        '"email": email,',
        '"role": role.toJson(),',
        '"address": address?.toJson(),',
        '"tags": tags,',
      ]));
    });

    test('fromJson parses all fields', () {
      expect(lines(out), containsAllInOrder([
        'public static func fromJson(_ map: [String: Any?]) -> User {',
        'return User(',
        'id: map["id"] as! String,',
        'name: map["name"] as! String,',
        'email: map["email"] as? String,',
        'role: Role.fromJson(map["role"] as! String),',
        'address: (map["address"] as? [String: Any?]).map { Address.fromJson(\$0) },',
      ]));
    });
  });

  group('type without id:ID! is not Identifiable', () {
    test('conforms to Sendable only', () {
      final g = GLParser()..parse('type Address { city: String! }');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['Address']!);
      expect(lines(out), contains('public struct Address: Sendable {'));
    });
  });

  group('interface declaration', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse('''
        interface Node {
          id: ID!
        }
        type User implements Node {
          id: ID!
          name: String!
        }
      ''');
      out = _serializer(g).doSerializeTypeDefinition(g.interfaces['Node']!);
    });

    test('emits a Sendable protocol', () {
      expect(lines(out), contains('public protocol Node: Sendable {'));
    });

    test('fields are `{ get }` requirements', () {
      expect(lines(out), contains('var id: String { get }'));
    });

    test('toJson is a protocol requirement', () {
      expect(lines(out), contains('func toJson() -> [String: Any?]'));
    });

    test('paired NodeJson dispatch factory', () {
      expect(lines(out), containsAllInOrder([
        'public enum NodeJson {',
        'public static func fromJson(_ map: [String: Any?]) -> any Node {',
        'switch map["__typename"] as? String {',
        'case "User":',
        'return User.fromJson(map)',
        'default:',
      ]));
      expect(out, contains('fatalError("Unknown Node __typename:'));
    });
  });

  group('type implementing interface', () {
    late GLParser g;

    setUp(() {
      g = GLParser()..parse('''
        interface Node {
          id: ID!
        }
        interface Named {
          name: String!
        }
        type User implements Node & Named {
          id: ID!
          name: String!
          email: String
        }
      ''');
    });

    test('struct conforms to every implemented interface', () {
      final out = _serializer(g).doSerializeTypeDefinition(g.types['User']!);
      expect(out, contains('Node'));
      expect(out, contains('Named'));
    });

    test('interface-required fields are plain stored properties (no override keyword)', () {
      final out = _serializer(g).doSerializeTypeDefinition(g.types['User']!);
      expect(lines(out), contains('public let id: String'));
      expect(lines(out), contains('public let name: String'));
      expect(out, isNot(contains('override')));
    });
  });

  group('interface with multiple implementors', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse('''
        interface Animal {
          id: ID!
        }
        type Dog implements Animal {
          id: ID!
          breed: String!
        }
        type Cat implements Animal {
          id: ID!
          color: String!
        }
      ''');
      out = _serializer(g).doSerializeTypeDefinition(g.interfaces['Animal']!);
    });

    test('dispatch factory has a case for every implementor', () {
      expect(lines(out), contains('case "Dog":'));
      expect(lines(out), contains('return Dog.fromJson(map)'));
      expect(lines(out), contains('case "Cat":'));
      expect(lines(out), contains('return Cat.fromJson(map)'));
    });

    test('default branch calls fatalError', () {
      expect(out, contains('default:'));
      expect(out, contains('fatalError('));
    });
  });
}
