import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:test/test.dart';

SwiftSerializer _serializer(GLParser g, {bool immutableTypeFields = true}) =>
    SwiftSerializer(g, importPrefix: 'GraphLinkGenerated', immutableTypeFields: immutableTypeFields);

/// Trims every line so indentation never breaks containsAllInOrder checks.
Iterable<String> lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

void main() {
  group('input struct', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse('''
        enum Role { admin user }
        input AddressInput { city: String! }
        input CreateUserInput {
          id: ID
          name: String!
          age: Int!
          score: Float
          active: Boolean!
          role: Role
          role2: Role!
          address: AddressInput
          tags: [String!]!
          roles: [Role!]!
          optRoles: [Role]
        }
      ''');
      out = _serializer(g).doSerializeInputDefinition(g.inputs['CreateUserInput']!);
    });

    test('struct declaration conforms to Sendable', () {
      expect(lines(out), contains('public struct CreateUserInput: Sendable {'));
    });

    test('non-nullable fields use let without default', () {
      expect(lines(out), contains('public let name: String'));
      expect(lines(out), contains('public let age: Int'));
      expect(lines(out), contains('public let active: Bool'));
    });

    test('nullable fields are declared without an inline default', () {
      // Stored properties never carry `= nil` — Swift rejects a property
      // that's both defaulted inline and assigned in an explicit init. The
      // default lives only on the init parameter (see the next test).
      expect(lines(out), contains('public let id: String?'));
      expect(lines(out), contains('public let score: Double?'));
      expect(lines(out), contains('public let role: Role?'));
      expect(out, isNot(contains('let id: String? = nil')));
    });

    test('nested input field', () {
      expect(lines(out), contains('public let address: AddressInput?'));
    });

    test('list fields', () {
      expect(lines(out), contains('public let tags: [String]'));
      expect(lines(out), contains('public let roles: [Role]'));
      expect(lines(out), contains('public let optRoles: [Role?]?'));
    });

    test('explicit public init with matching parameter defaults, one per line', () {
      expect(lines(out), containsAllInOrder([
        'public init(',
        'id: String? = nil,',
        'name: String,',
        'role: Role? = nil,',
        ') {',
        'self.id = id',
      ]));
    });

    test('toJson emits map literal with all keys', () {
      expect(lines(out), containsAllInOrder([
        'public func toJson() -> [String: Any?] {',
        'return [',
        '"id": id,',
        '"name": name,',
        '"role": role?.toJson(),',
        '"role2": role2.toJson(),',
        '"address": address?.toJson(),',
        '"tags": tags.map { \$0 as Any? },',
        '"roles": roles.map { e0 in e0.toJson() },',
        '"optRoles": optRoles?.map { e0 in e0?.toJson() },',
      ]));
    });

    test('fromJson is a public static factory', () {
      expect(lines(out), containsAllInOrder([
        'public static func fromJson(_ map: [String: Any?]) throws -> CreateUserInput {',
        'return CreateUserInput(',
        'id: try glStringOrNil(map["id"], "CreateUserInput.id"),',
        'name: try glString(map["name"], "CreateUserInput.name"),',
        'age: try glInt(map["age"], "CreateUserInput.age"),',
        'score: try glDoubleOrNil(map["score"], "CreateUserInput.score"),',
        'active: try glBool(map["active"], "CreateUserInput.active"),',
        'role: try glStringOrNil(map["role"], "CreateUserInput.role").map { try Role.fromJson(\$0) },',
        'role2: try Role.fromJson(glString(map["role2"], "CreateUserInput.role2")),',
        'address: try glMapOrNil(map["address"], "CreateUserInput.address").map { try AddressInput.fromJson(\$0) },',
        'tags: try glList(map["tags"], "CreateUserInput.tags").map { e0 in try glString(e0, "CreateUserInput.tags") },',
        'roles: try glList(map["roles"], "CreateUserInput.roles").map { e0 in try Role.fromJson(glString(e0, "CreateUserInput.roles")) },',
      ]));
    });

    test('nullable list of nullable elements chains through the optional helper before mapping', () {
      expect(lines(out), contains('optRoles: try glListOrNil(map["optRoles"], "CreateUserInput.optRoles")?.map { e0 in try glStringOrNil(e0, "CreateUserInput.optRoles").map { try Role.fromJson(\$0) } }'));
    });
  });

  group('input struct — mutable fields', () {
    test('immutableTypeFields: false uses var', () {
      final g = GLParser()..parse('input CreateUserInput { name: String! }');
      final out = _serializer(g, immutableTypeFields: false).doSerializeInputDefinition(g.inputs['CreateUserInput']!);
      expect(lines(out), contains('public var name: String'));
    });
  });
}
