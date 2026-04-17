import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

void main() {
  group('TypeScript type serialization', () {
    test('generates a readonly interface for a plain type', () {
      final g = GLParser();
      g.parse('''
        type Vehicle {
          id: ID!
          brand: String!
          year: Int!
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result =
          serializer.serializeTypeDefinition(g.getTypeByName('Vehicle')!, '');
      print(result);
      expect(result, contains('export interface Vehicle'));
      expect(result, contains('readonly id: string;'));
      expect(result, contains('readonly brand: string;'));
      expect(result, contains('readonly year: number;'));
    });

    test('nullable field serializes as Type | null', () {
      final g = GLParser();
      g.parse('''
        type Vehicle {
          id: ID!
          owner: String
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result =
          serializer.serializeTypeDefinition(g.getTypeByName('Vehicle')!, '');
      expect(result, contains('readonly owner: string | null;'));
    });

    test('immutableTypeFields false omits readonly', () {
      final g = GLParser();
      g.parse('''
        type Vehicle {
          id: ID!
          brand: String!
        }
      ''');

      final serializer = TypeScriptSerializer(g, immutableTypeFields: false);
      final result =
          serializer.serializeTypeDefinition(g.getTypeByName('Vehicle')!, '');

      expect(result, contains('id: string;'));
      expect(result, isNot(contains('readonly')));
    });

    test('non-null list field', () {
      final g = GLParser();
      g.parse('''
        type Fleet {
          ids: [ID!]!
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result =
          serializer.serializeTypeDefinition(g.getTypeByName('Fleet')!, '');

      expect(result, contains('readonly ids: string[];'));
    });

    test('nullable list field', () {
      final g = GLParser();
      g.parse('''
        type Fleet {
          ids: [ID!]
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result =
          serializer.serializeTypeDefinition(g.getTypeByName('Fleet')!, '');

      expect(result, contains('readonly ids: string[] | null;'));
    });

    test('list with nullable elements', () {
      final g = GLParser();
      g.parse('''
        type Fleet {
          ids: [ID]!
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result =
          serializer.serializeTypeDefinition(g.getTypeByName('Fleet')!, '');

      expect(result, contains('readonly ids: (string | null)[];'));
    });

    test('GraphQL interface generates a discriminated union type alias', () {
      final g = GLParser();
      g.parse('''
        interface Animal {
          id: ID!
          name: String!
        }
        type Dog implements Animal {
          id: ID!
          name: String!
          breed: String!
        }
        type Cat implements Animal {
          id: ID!
          name: String!
          indoor: Boolean!
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeTypeDefinition(
          g.interfaces['Animal']!, '');

      expect(result, contains('export type Animal ='));
      expect(result, contains('Dog'));
      expect(result, contains('Cat'));
      expect(result, isNot(contains('__typename')));
    });

    test('implementing type does not include __typename', () {
      final g = GLParser();
      g.parse('''
        interface Animal {
          id: ID!
          name: String!
        }
        type Dog implements Animal {
          id: ID!
          name: String!
          breed: String!
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result =
          serializer.serializeTypeDefinition(g.getTypeByName('Dog')!, '');
      print(result);
      expect(result, contains('export interface Dog'));
      expect(result, contains('readonly breed: string;'));
      expect(result, isNot(contains('__typename')));
    });

    test('skips type marked @glSkipOnClient in client mode', () {
      final g = GLParser(mode: CodeGenerationMode.client);
      g.parse('type InternalType @glSkipOnClient { id: ID! }');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeTypeDefinition(
          g.getTypeByName('InternalType')!, '');
      print(result);
      expect(result, isEmpty);
    });

    test('type referencing an enum imports it', () {
      final g = GLParser();
      g.parse('''
        enum FuelType { GASOLINE DIESEL }
        type Vehicle {
          id: ID!
          fuelType: FuelType!
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result =
          serializer.serializeTypeDefinition(g.getTypeByName('Vehicle')!, '');

      expect(result, contains("import { FuelType } from"));
      expect(result, contains('readonly fuelType: FuelType;'));
    });
  });
}
