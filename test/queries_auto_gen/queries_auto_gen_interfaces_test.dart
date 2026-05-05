import 'dart:io';

import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() async {
  test("query definition auto generation inline projection on interfaces2", () {
    final text =
        File("test/queries_auto_gen/queries_auto_gen_interfaces.graphql")
            .readAsStringSync();
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);

    g.parse(text);

    expect(g.queries.keys, contains("getProduct"));
    var getProduct = g.queries["getProduct"]!;

    expect(getProduct.tokenInfo.token, equals("getProduct"));

    expect(getProduct.elements.length, equals(1));

  });

  test("query definition auto generation on interface Animal with glSkipOnClient type", () {
    const schema = '''
      directive @glSkipOnClient on FIELD_DEFINITION | OBJECT

      interface Animal {
        id: String
        name: String!
      }

      type Dog implements Animal {
        id: String
        name: String!
        breed: String
      }

      type Cat implements Animal {
        id: String
        name: String!
        indoor: Boolean
      }

      type Tiger implements Animal @glSkipOnClient {
        id: String
        name: String!
        stripes: Int
      }

      type Query {
        getAnimal: Animal
      }
    ''';

    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);

    g.parse(schema);

    var dartSerializer = DartSerializer(g);
    var animal = g.interfaces['Animal']!;
    expect(animal.getSerializableImplementations(g.mode).map((e) => e.token), containsAll(['Cat', 'Dog']));
    expect(animal.getSerializableImplementations(g.mode).map((e) => e.token), isNot(contains('Tiger')));
    final serializedInterface = dartSerializer.serializeTypeDefinition(animal, '');
    //print(serializedInterface);
    expect(serializedInterface, isNot(contains('Tiger')));

    // Java
    var javaSerializer = JavaSerializer(g, generateJsonMethods: true);
    final javaInterface = javaSerializer.serializeTypeDefinition(animal, 'org.example');
    expect(javaInterface, isNot(contains('Tiger')));
    // typescript

    var tsSerializer = TypeScriptSerializer(g);
    final tsInterface = tsSerializer.serializeTypeDefinition(animal, '');
    expect(tsInterface, isNot(contains('Tiger')));

  });
}
