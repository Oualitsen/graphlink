import 'dart:io';

import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';

void main() {
  group('github schema — large real-world schema parsing', skip: true, () {
    test('parses without throwing', () {
      final schema = File('test/github_schema/schema.docs.graphql').readAsStringSync();
      final parser = GLParser();
      expect(() => parser.parse(schema, validate: false), returnsNormally);
    });

    test('parses expected number of types and inputs', () {
      final schema = File('test/github_schema/schema.docs.graphql').readAsStringSync();
      final parser = GLParser();
      parser.parse(schema, validate: false);
      expect(parser.types.isNotEmpty, true);
      expect(parser.inputs.isNotEmpty, true);
      expect(parser.enums.isNotEmpty, true);
    });
  });

  group('github schema — client generation with fragments + auto queries', skip: true, () {
    late GLParser parser;
    late DartClientSerializer serializer;

    setUpAll(() {
      final schema = File('test/github_schema/schema.docs.graphql').readAsStringSync();
      parser = GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueries: true,
        defaultAlias: 'data',
      );
      parser.parse(schema);
      serializer = DartClientSerializer(
        parser,
        DartSerializer(parser, importPrefix: ''),
        generateAdapters: true,
      );
    });

    test('auto-generates queries from Query type', () {
      expect(parser.queries.isNotEmpty, true);
      print('Auto-generated query count: ${parser.queries.length}');
    });

    test('generates all-fields fragments for types', () {
      expect(parser.fragments.isNotEmpty, true);
      print('Fragment count: ${parser.fragments.length}');
    });

    test('generates client file without throwing', () {
      expect(() => serializer.generateClient().toFileContent(), returnsNormally);
    });

    test('generated client is non-empty', () {
      final out = serializer.generateClient().toFileContent();
      expect(out.length, greaterThan(0));
      print('Generated client size: ${out.length} chars');
    });

  });
}
