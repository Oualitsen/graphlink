import 'dart:io';

import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GitLab schema — large real-world schema parsing', () {
    test('parses without throwing', () {
      final schema = File('test/gitlab_schema/schema.docs.graphql').readAsStringSync();
      final parser = GLParser();
      expect(() => parser.parse(schema, validate: false), returnsNormally);
    });

    test('parses expected number of types and inputs', () {
      final schema = File('test/gitlab_schema/schema.docs.graphql').readAsStringSync();
      final parser = GLParser();
      parser.parse(schema, validate: false);
      expect(parser.types.isNotEmpty, true);
      expect(parser.inputs.isNotEmpty, true);
      expect(parser.enums.isNotEmpty, true);
    });
  });
}
