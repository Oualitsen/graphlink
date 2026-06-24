import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test('parser parses @skip and @include directives without error', () {
    const schema = '''
type Product {
  name: String!
  description: String!
  price: Float!
}

type Query {
  getProduct: Product!
  getProductList: [Product!]!
}

query products(\$hide: Boolean!, \$show: Boolean!) {
  getProduct {
    name @skip(if: \$hide)
    description
    price @include(if: \$show)
  }

  getProductList {
    name
    description @include(if: true)
    price @skip(if: false)
  }
}
''';

    final g = GLParser();
    g.parse(schema);
  });
}
