import 'dart:io';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  print("reading gitlab schema");
  final schema = File('test/gitlab_schema/schema.docs.graphql').readAsStringSync();
  try {
    final parser = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultAlias: 'data',
    );
    final now = DateTime.now();
    print("About to parse the schema");
    parser.parse(schema);
    print("DONE in ${DateTime.now().millisecondsSinceEpoch - now.millisecondsSinceEpoch} ms");
    print('OK — fragments: ${parser.fragments.length}, queries: ${parser.queries.length}');
  } catch (e) {
    print('ERROR: $e');
  }
}
