import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const schema = '''
interface Animal {
  id: ID!
  name: String!
}

type Dog implements Animal {
  id: ID!
  name: String!
  breed: String!
}

type Cat implements Animal {
  id: ID!
  name: String!
  livesLeft: Int!
}
''';

void main() {
  test("interface toJson __typename dispatch (server mode)", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);
    g.parse(schema);

    var serializer = DartSerializer(g, importPrefix: "");

    final animal =
        serializer.serializeInterface(g.interfaces["Animal"]!).trim();

    print(animal);

    final dog = serializer.serializeTypeDefinition(g.types["Dog"]!).trim();

    print(dog);

    expect(dog, contains("'__typename': 'Dog',"));
  });

  test("java toJson emits __typename (server mode)", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);
    g.parse(schema);

    var serializer = JavaSerializer(g, importPrefix: "");

    final dog = serializer.serializeTypeDefinition(g.types["Dog"]!).trim();

    print(dog);

    expect(dog, contains('map.put("__typename", "Dog");'));
  });

  test("kotlin toJson emits __typename (server mode)", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);
    g.parse(schema);

    var serializer = KotlinSerializer(g, importPrefix: "");

    final dog = serializer.serializeTypeDefinition(g.types["Dog"]!).trim();

    print(dog);

    expect(dog, contains('"__typename" to "Dog"'));
  });

  test("typescript toJson emits __typename (server mode)", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);
    g.parse(schema);

    var serializer = TypeScriptSerializer(g, importPrefix: "");

    final dog = serializer.serializeTypeDefinition(g.types["Dog"]!).trim();

    print(dog);

    expect(dog, contains('"__typename": "Dog"'));
  });
}
