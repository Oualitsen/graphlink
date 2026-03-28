import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/main.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const outputDir =
    "../gql-test-projects/gqlJavaClient/src/main/java/org/gqlclient/generated";

getConfig(GLParser g) {
  return GeneratorConfig(
      schemaPaths: [],
      mode: g.mode.name,
      identityFields: [],
      typeMappings: g.typeMap,
      outputDir: outputDir,
      clientConfig: ClientConfig(
          java: JavaClientConfig(
              packageName: "org.gqlclient.generated",
              generateAllFieldsFragments: g.generateAllFieldsFragments,
              nullableFieldsRequired: false,
              autoGenerateQueries: g.autoGenerateQueries,
              operationNameAsParameter: false)));
}

void main() async {
  test("generate java client", () async {
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse('''
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

    await generateJavaClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'org.gqlclient.generated');
  });

  test("GraphLinkJsonEncoder serialization", () {
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse('''
  ${javaJsonEncoderDecorder}
''');

    var serializer = JavaSerializer(g);

    var serial = serializer.serializeTypeDefinition(
        g.interfaces['GraphLinkJsonEncoder']!, 'com.myorg');
    expect(
        serial.split("\n").map((e) => e.trim()).where((e) => e.isNotEmpty),
        containsAllInOrder([
          '@FunctionalInterface',
          'public interface GraphLinkJsonEncoder {',
          'String encode(Object json);',
          '}',
        ]));
  });

  test("GraphLinkJsonDecoder serialization", () {
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse('''
  ${javaJsonEncoderDecorder}
''');

    var serializer = JavaSerializer(g);

    var serial = serializer.serializeTypeDefinition(
        g.interfaces['GraphLinkJsonDecoder']!, 'com.myorg');
    expect(
        serial.split("\n").map((e) => e.trim()).where((e) => e.isNotEmpty),
        containsAllInOrder([
          'import java.util.Map;',
          '@FunctionalInterface',
          'public interface GraphLinkJsonDecoder {',
          'Map<String, Object> decode(String json);',
          '}',
        ]));
  });

  test("GraphLinkClientAdapter serialization async", () {
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse('''
  ${javaClientAdapterNoParamSync}
''');

    var serializer = JavaSerializer(g);

    var serial = serializer.serializeTypeDefinition(
        g.interfaces['GraphLinkClientAdapter']!, 'com.myorg');
    expect(
        serial.split("\n").map((e) => e.trim()).where((e) => e.isNotEmpty),
        containsAllInOrder([
          '@FunctionalInterface',
          'public interface GraphLinkClientAdapter {',
          'String execute(String payload);',
          '}',
        ]));
  });
}
