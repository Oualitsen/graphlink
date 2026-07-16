import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/swift_serializer.dart';
import 'package:test/test.dart';

SwiftSerializer _serializer(GLParser g) => SwiftSerializer(g, importPrefix: 'GraphLinkGenerated');

void main() {
  group('serializeType', () {
    late GLParser g;
    late SwiftSerializer s;

    setUp(() {
      g = GLParser()..parse('''
        scalar Long
        enum Role { admin user }
        type Address { city: String! }
        type User {
          id: ID!
          name: String
          age: Int!
          score: Float
          active: Boolean
          bigNum: Long
          role: Role!
          address: Address
          tags: [String!]!
          optTags: [String]
          roles: [[Role!]]
        }
      ''');
      s = _serializer(g);
    });

    String typeOf(String field) => s.serializeType(g.types['User']!.fields.firstWhere((f) => f.name.token == field).type);

    test('non-nullable scalar has no `?`', () {
      expect(typeOf('id'), 'String');
      expect(typeOf('age'), 'Int');
    });

    test('nullable scalar gets `?`', () {
      expect(typeOf('name'), 'String?');
      expect(typeOf('score'), 'Double?');
      expect(typeOf('active'), 'Bool?');
    });

    test('custom scalar falls back to unknownScalarType / raw token', () {
      expect(typeOf('bigNum'), 'Long?');
    });

    test('non-nullable enum/type reference resolves to its codeName', () {
      expect(typeOf('role'), 'Role');
    });

    test('nullable object type reference', () {
      expect(typeOf('address'), 'Address?');
    });

    test('non-nullable list of non-nullable elements', () {
      expect(typeOf('tags'), '[String]');
    });

    test('nullable list of nullable elements', () {
      // `[String]` (no inner `!`) is a nullable list of nullable String.
      expect(typeOf('optTags'), '[String?]?');
    });

    test('nested list', () {
      // `[[Role!]]` — nullable outer list of nullable inner list of
      // non-nullable Role.
      expect(typeOf('roles'), '[[Role]?]?');
    });
  });
}
