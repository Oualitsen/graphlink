import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Owner { name: String! }
type Product { id: ID! name: String! note: String owner: Owner! tags: [String!]! }
type Other { id: ID! }
type Query {
  product: Product @glRest(path: "/p")
  other: Other
}
''';

String _type(String name) {
  final g = GLParser()..parse(_schema);
  return DartSerializer(g, importPrefix: '').serializeTypeDefinition(g.types[name]!);
}

void main() {
  test('a REST-reachable type names the missing field when a non-null one is absent', () {
    final out = _type('Product');
    expect(out, contains("if (json['id'] == null)"));
    expect(out, contains("FormatException('Product.id is missing or null in the response')"));
    expect(out, contains("Product.name is missing or null"));
    expect(out, contains("Product.owner is missing or null"));
    expect(out, contains("Product.tags is missing or null"));
  });

  test('nullable fields are not checked', () {
    expect(_type('Product'), isNot(contains("json['note'] == null")));
  });

  test('nested reachable types are checked too', () {
    expect(_type('Owner'), contains('Owner.name is missing or null'));
  });

  test('types not reachable from a REST operation are unchanged', () {
    expect(_type('Other'), isNot(contains('missing or null')));
  });
}
