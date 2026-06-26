import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
interface Item {
    id: ID!
    name: String!
}

interface Container {
    id: ID!
    items: [Item!]!
}

type Box implements Container {
    id: ID!
    items: [Item!]!
}
''';

void main() {
  test("Java interface with list of interface field", () {
    final g = GLParser(identityFields: ["id"]);
    g.parse(_schema);

    final container = g.interfaces["Container"]!;
    final javaSerializer = JavaSerializer(g, importPrefix: "");
    final out = javaSerializer.serializeInterface(container, getters: true);
    print(out);

    expect(out, contains("List<Item> getItems()"));
  });


  test("Java interface as records with list of interface field", () {
    final g = GLParser(identityFields: ["id"]);
    g.parse(_schema);

    final container = g.interfaces["Container"]!;
    final javaSerializer = JavaSerializer(g, importPrefix: "", typesAsRecords: true);
    final out = javaSerializer.serializeInterface(container, getters: true);
    print(out);

    expect(out, contains("List<Item> items()"));
  });

  test("Kotlin interface with list of interface field", () {
    final g = GLParser(identityFields: ["id"]);
    g.parse(_schema);

    final container = g.interfaces["Container"]!;
    final kotlinSerializer = KotlinSerializer(g, importPrefix: "com.example");
    final out = kotlinSerializer.serializeInterface(container);
    print(out);

    expect(out, contains("val items: List<Item>"));
  });
}
