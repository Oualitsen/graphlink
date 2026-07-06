import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test("Java getterName for boolean field", () {
    final GLParser g = GLParser();

    g.parse('''
type Product {
  id: ID!
  active: Boolean!
}
''');

    var product = g.types["Product"]!;
    var serializer = JavaSerializer(g, importPrefix: "", typeMapOverrides: {
      "Boolean": "boolean"
    });
    var result = serializer.getterName(product, "active");
    expect(result, "isActive");
  });

  test("Java getterName for nullable boolean field via interface", () {
    final GLParser g = GLParser();

    g.parse('''
interface Base {
  active: Boolean
}

type Product implements Base {
  id: ID!
  active: Boolean!
}
''');

    var product = g.types["Product"]!;
    var serializer = JavaSerializer(g, importPrefix: "", typeMapOverrides: {
      "Boolean": "boolean"
    });
    var result = serializer.getterName(product, "active");
    expect(result, "getActive");
  });
}
