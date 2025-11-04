import 'package:retrofit_graphql/src/config.dart';
import 'package:retrofit_graphql/src/constants.dart';
import 'package:retrofit_graphql/src/main.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

const outputDir = "../gql-test-projects/gqlJavaClient/src/main/java/org/gqlclient/generated";

getConfig(GQGrammar g) {
  return GeneratorConfig(
      schemaPaths: [],
      mode: g.mode.name,
      identityFields: [],
      typeMappings: g.typeMap,
      outputDir: outputDir,
      clientConfig: ClientConfig(
          targetLanguage: "java",
          generateAllFieldsFragments: g.generateAllFieldsFragments,
          nullableFieldsRequired: false,
          autoGenerateQueries: g.autoGenerateQueries,
          operationNameAsParameter: false,
          packageName: "org.gqlclient.generated"));
}

void main() async {
  test("generate java client", () async {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
    var parsed = g.parse('''
  ${getClientObjects("Java")}
  ${javaJsonEncoderDecorder}
  ${javaClientAdapterNoParamSync}
  ${javaWebSocketAdapter}
 

 directive @gqServiceName(name: String) on FIELD_DEFINITION
directive @gqSkipOnServer(mapTo: String, batch: Boolean) on FIELD_DEFINITION|OBJECT
directive @gqSkipOnClient on FIELD_DEFINITION|OBJECT

type Car {
    make: String
    model: String
}

type User {
    id: ID!
    name: String
}



input UserInput {
    name: String!
    gender: Gender!
}

enum Gender {
    male, female
}

type Query {
    getCarsByUserId(userId: String!): [Car!]! @gqServiceName(name: "CarService")
    getUser: User! @gqServiceName(name: "CarService")
}

type Mutation {
    createUser(input: UserInput!): User!
}

type Subscription {
  watchUser: User!
}

 
''');
    expect(parsed is Success, true);
    await generateClientClassesJava(g, getConfig(g), DateTime.now(),
        pack: 'org.gqlclient.generated');
  });

  test("GQJsonEncoder serialization", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
    var parsed = g.parse('''
  ${javaJsonEncoderDecorder}
''');
    expect(parsed is Success, true);
    var serializer = JavaSerializer(g);

    var serial = serializer.serializeTypeDefinition(g.interfaces['GQJsonEncoder']!, 'com.myorg');
    expect(
        serial.split("\n").map((e) => e.trim()).where((e) => e.isNotEmpty),
        containsAllInOrder([
          '@FunctionalInterface',
          'public interface GQJsonEncoder {',
          'String encode(Object json);',
          '}',
        ]));
  });

  test("GQJsonDecoder serialization", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
    var parsed = g.parse('''
  ${javaJsonEncoderDecorder}
''');
    expect(parsed is Success, true);
    var serializer = JavaSerializer(g);

    var serial = serializer.serializeTypeDefinition(g.interfaces['GQJsonDecoder']!, 'com.myorg');
    expect(
        serial.split("\n").map((e) => e.trim()).where((e) => e.isNotEmpty),
        containsAllInOrder([
          'import java.util.Map;',
          '@FunctionalInterface',
          'public interface GQJsonDecoder {',
          'Map<String, Object> decode(String json);',
          '}',
        ]));
  });

  test("GQClientAdapter serialization async", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
    var parsed = g.parse('''
  ${javaClientAdapterNoParamSync}
''');
    expect(parsed is Success, true);
    var serializer = JavaSerializer(g);

    var serial = serializer.serializeTypeDefinition(g.interfaces['GQClientAdapter']!, 'com.myorg');
    expect(
        serial.split("\n").map((e) => e.trim()).where((e) => e.isNotEmpty),
        containsAllInOrder([
          '@FunctionalInterface',
          'public interface GQClientAdapter {',
          'String execute(String payload);',
          '}',
        ]));
  });
}
