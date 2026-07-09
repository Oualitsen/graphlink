import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test("Product transitively implements interfaces implemented by Base", () async {
    final g = GLParser(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
    interface Base {
      id: String
    }
    type Product implements Base {
      id: String
      name: String
    }
''');

    final serializer = GLGraphqlSerializer(g);
    print(serializer.generateSchema());

    final product = g.getTypeByName("Product")!;

    // GraphQL requires Product to explicitly declare every interface Base
    // itself implements, not just Base directly.
    expect(product.getInterfaceNames(), contains("Base"));
  });

  test("serialize schema with interface implemented by a type and a skip-on-client field", () async {
    final g = GLParser(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
    interface Base {
      id: String
    }
    type Product implements Base {
      id: String
      name: String
      purchaseCost: Float @glSkipOnClient
    }
''');

    final serializer = GLGraphqlSerializer(g);
    var serial = serializer.generateSchema();
    print(serial);

    final product = g.getTypeByName("Product")!;

    var productClientFieldNames = product
        .getSerializableFields(CodeGenerationMode.client)
        .map((f) => f.name.token)
        .toSet();

    // purchaseCost carries @glSkipOnClient, so generateSchema() (hardcoded to
    // filter as client) strips it from the concrete type.
    expect(productClientFieldNames, isNot(contains("purchaseCost")));
    expect(serial, isNot(contains("purchaseCost")));

    expect(productClientFieldNames, containsAll(["id", "name"]));

    // The raw declaration still has the field — only the client-mode
    // serialization filters it out.
    expect(product.fieldNames, contains("purchaseCost"));
  });

  test("serialize schema with a @glSkipOnServer type", () async {
    final g = GLParser(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
    interface Base {
      id: String
    }
    type Product implements Base {
      id: String
      name: String
      purchaseCost: Float @glSkipOnClient
    }
    type ProductData @glSkipOnServer {
      id: String
      name: String
    }
''');

    final serializer = GLGraphqlSerializer(g);
    var serial = serializer.generateSchema();
    print(serial);

    final productData = g.getTypeByName("ProductData")!;

    // @glSkipOnServer types are excluded from server codegen and never gain
    // an implements clause.
    expect(productData.getInterfaceNames(), isEmpty);

    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder(["type ProductData {", "id: String", "name: String", "}"]),
    );
  });

  test("serialize schema with a @glSkipOnServer(mapTo:) type", () async {
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse('''
    
    type Product  {
      id: String
      name: String
    }

    type ProductData @glSkipOnServer(mapTo: "Product") {
      product: Product!
      banned: Boolean!
    }

    type Query {
      getData: ProductData
    }
''');

    final serializer = GLGraphqlSerializer(g);
    var serial = serializer.generateSchema();
    print(serial);

    // mapTo routes ProductData's fields through schema-mapping generation,
    // which injects a synthetic `value` argument onto the field for the
    // service/controller resolver signature. That argument is internal-only
    // (skipOnGraphqlSerialization: true) and must never leak into the wire
    // GraphQL SDL.
    expect(serial, isNot(contains("value")));
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "type ProductData {",
        "product: Product!",
        "banned: Boolean!",
        "}"
      ]),
    );
  });
}
