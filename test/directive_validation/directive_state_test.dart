import 'package:graphlink/src/model/gl_collection_imports.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  test('validating a schema does not reset the collection imports of the parser being validated', () {
    const java = GLCollectionImports(listImport: 'java.util.List', mapImport: 'java.util.Map');
    final parser = GLParser(collectionImports: java);
    parser.parse('type Product { tags: [String!]! } type Query { p: Product @glCache(ttl: 5) }');

    expect(GLType.collectionImportsConfig.listImport, 'java.util.List');
    expect(collectionImportsOf(parser.types['Product']!.fields.first.type), contains('java.util.List'));
  });
}
