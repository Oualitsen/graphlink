import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/main.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

const outputDir = "../gql-test-projects/gqlJavaClient/src/main/java/org/gqlclient/generated";

getConfig(GLGrammar g) {
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
    var parsed = g.parse('''
  ${getClientObjects("Java")}
  ${javaJsonEncoderDecorder}
  ${javaClientAdapterNoParamSync}
  ${javaGraphLinkWebSocketAdapter}
 

 directive @glServiceName(name: String) on FIELD_DEFINITION
directive @glSkipOnServer(mapTo: String, batch: Boolean) on FIELD_DEFINITION|OBJECT
directive @glSkipOnClient on FIELD_DEFINITION|OBJECT

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
    getCarsByUserId(userId: String!): [Car!]! @glServiceName(name: "CarService")
    getUser: User! @glServiceName(name: "CarService")
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
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
