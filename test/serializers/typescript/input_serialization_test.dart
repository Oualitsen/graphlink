import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

void main() {
  group('TypeScript input serialization', () {
    test('generates an interface with non-nullable fields', () {
      final g = GLParser();
      g.parse('''
        enum FuelType { GASOLINE DIESEL }
        input AddVehicleInput {
          brand: String!
          year: Int!
          fuelType: FuelType!
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeInputDefinition(
          g.inputs['AddVehicleInput']!, '');

      expect(result, contains('export interface AddVehicleInput'));
      expect(result, contains('brand: string;'));
      expect(result, contains('year: number;'));
      expect(result, contains('fuelType: FuelType;'));
    });

    test('nullable fields use optional syntax by default', () {
      final g = GLParser();
      g.parse('''
        input UpdateVehicleInput {
          brand: String!
          note: String
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeInputDefinition(
          g.inputs['UpdateVehicleInput']!, '');

      expect(result, contains('brand: string;'));
      expect(result, contains('note?: string | null;'));
    });

    test('nullable fields use non-optional syntax when optionalNullableInputFields is false', () {
      final g = GLParser();
      g.parse('''
        input UpdateVehicleInput {
          brand: String!
          note: String
        }
      ''');

      final serializer =
          TypeScriptSerializer(g, optionalNullableInputFields: false);
      final result = serializer.serializeInputDefinition(
          g.inputs['UpdateVehicleInput']!, '');

      expect(result, contains('brand: string;'));
      expect(result, contains('note: string | null;'));
    });

    test('non-null list field', () {
      final g = GLParser();
      g.parse('''
        input TagsInput {
          tags: [String!]!
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeInputDefinition(
          g.inputs['TagsInput']!, '');

      expect(result, contains('tags: string[];'));
    });

    test('nullable list field uses optional syntax', () {
      final g = GLParser();
      g.parse('''
        input TagsInput {
          tags: [String!]
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeInputDefinition(
          g.inputs['TagsInput']!, '');

      expect(result, contains('tags?: string[] | null;'));
    });

    test('list with nullable elements', () {
      final g = GLParser();
      g.parse('''
        input TagsInput {
          tags: [String]!
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeInputDefinition(
          g.inputs['TagsInput']!, '');

      expect(result, contains('tags: (string | null)[];'));
    });

    test('skips the whole input marked @glSkipOnClient in client mode', () {
      final g = GLParser(mode: CodeGenerationMode.client);
      g.parse('input InternalInput @glSkipOnClient { id: ID! }');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeInputDefinition(
          g.inputs['InternalInput']!, '');

      expect(result, isEmpty);
    });
  });
}
