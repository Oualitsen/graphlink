import 'dart:io';

import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';

void main() {
  group('gitlab schema — large real-world schema parsing', () {
    test('GitLab parses without throwing', () {
      final schema = File('test/gitlab_schema/schema.graphql').readAsStringSync();
      final parser = GLParser();
      expect(() => parser.parse(schema, validate: false), returnsNormally);
    });

    test('GitLab parses expected number of types and inputs', () {
      final schema = File('test/gitlab_schema/schema.graphql').readAsStringSync();
      final parser = GLParser();
      parser.parse(schema, validate: false);
      expect(parser.types.isNotEmpty, true);
      expect(parser.inputs.isNotEmpty, true);
      expect(parser.enums.isNotEmpty, true);
    });
  });

  group('gitlab schema — client generation with fragments + auto queries', skip: true, () {
    late GLParser parser;
    late DartClientSerializer serializer;

    setUpAll(() {
      final schema = File('test/gitlab_schema/schema.graphql').readAsStringSync();
      parser = GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueries: true,
        defaultAlias: 'data',
      );
      final sw = Stopwatch()..start();
      parser.parse(schema);
      sw.stop();
      print('Parse took: ${sw.elapsedMilliseconds}ms');
      serializer = DartClientSerializer(
        parser,
        DartSerializer(parser, importPrefix: ''),
        generateAdapters: true,
      );
    });

    test('GitLab auto-generates queries from Query type', () {
      expect(parser.queries.isNotEmpty, true);
      print('Auto-generated query count: ${parser.queries.length}');
    });

    test('GitLab generates all-fields fragments for types', () {
      expect(parser.fragments.isNotEmpty, true);
      print('Fragment count: ${parser.fragments.length}');
    });

    test('GitLab generates client file without throwing', () {
      expect(() => serializer.generateClient().toFileContent(), returnsNormally);
    });

    test('GitLab generated client is non-empty', () {
      final out = serializer.generateClient().toFileContent();
      expect(out.length, greaterThan(0));
      print('Generated client size: ${out.length} chars');
    });
  });
}
