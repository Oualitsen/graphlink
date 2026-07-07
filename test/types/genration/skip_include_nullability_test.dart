
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("skip_include_nullability_test", () {
    final GLParser g = GLParser();

    g.parse('''

type Product {
    name: String!
    
    description: String!
}

type Query {
    getProduct: Product!
    getProductList: [Product!]!
}

query products {
    getProduct @glTypeName(name: "ProductNullName") {
        name @skip(if: true) description
    }

    getProductList @glTypeName(name: "ProductNullDesc") {
        name description @include(if: true)
    }
}

''');

    final nullName = g.projectedTypes['ProductNullName']!;
    final nullDesc = g.projectedTypes['ProductNullDesc']!;

    expect(nullName.getFieldByName('name')!.type.nullable, true);
    expect(nullName.getFieldByName('description')!.type.nullable, false);

    expect(nullDesc.getFieldByName('name')!.type.nullable, false);
    expect(nullDesc.getFieldByName('description')!.type.nullable, true);

    
  });
}
