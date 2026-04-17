import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

void main() {
  group('TypeScript enum serialization', () {
    test('generates a string enum with all values', () {
      final g = GLParser();
      g.parse('enum FuelType { GASOLINE DIESEL ELECTRIC HYBRID }');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeEnumDefinition(
          g.enums['FuelType']!, '');

      print(result);

      expect(result, contains('export enum FuelType'));
      expect(result, contains("GASOLINE = 'GASOLINE'"));
      expect(result, contains("DIESEL = 'DIESEL'"));
      expect(result, contains("ELECTRIC = 'ELECTRIC'"));
      expect(result, contains("HYBRID = 'HYBRID'"));
    });

    test('skips values marked @glSkipOnClient in client mode', () {
      final g = GLParser(mode: CodeGenerationMode.client);
      g.parse('''
        enum Role {
          ADMIN
          USER
          INTERNAL @glSkipOnClient
        }
      ''');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeEnumDefinition(
          g.enums['Role']!, '');

      print(result);

      expect(result, contains("ADMIN = 'ADMIN'"));
      expect(result, contains("USER = 'USER'"));
      expect(result, isNot(contains('INTERNAL')));
    });

    test('skips the whole enum marked @glSkipOnClient in client mode', () {
      final g = GLParser(mode: CodeGenerationMode.client);
      g.parse('enum InternalStatus @glSkipOnClient { PENDING DONE }');

      final serializer = TypeScriptSerializer(g);
      final result = serializer.serializeEnumDefinition(
          g.enums['InternalStatus']!, '');

      print('(empty: "$result")');

      expect(result, isEmpty);
    });

    test('file name is kebab-case .ts', () {
      final g = GLParser();
      g.parse('enum FuelType { GASOLINE }');

      final serializer = TypeScriptSerializer(g);
      final fileName = serializer.getFileNameFor(g.enums['FuelType']!);

      print(fileName);

      expect(fileName, 'fuel-type.ts');
    });
  });
}
