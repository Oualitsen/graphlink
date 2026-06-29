import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A subscription (resolver) may be named after a target-language keyword
/// (`return`). The generated client *method* must be sanitized (`return_`),
/// while the GraphQL *operation/wire name* stays the original `return` so the
/// request still matches the schema field on the server.
void main() {
  const schema = '''
    type Person { id: ID! name: String! }
    type Subscription { return(id: ID!): Person }
  ''';

  test("Dart: subscription method sanitized, wire operation name preserved", () {
    final g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: dartReservedWords,
    )..parse(schema);

    final out = DartClientSerializer(g, DartSerializer(g, importPrefix: ""))
        .generateClient()
        .toFileContent();

    // method name uses the safe identifier.
    expect(out, contains("return_("));
    // wire operation name stays the original `return`.
    expect(out, contains("subscription return"));
    expect(out, contains("operationName: 'return'"));
  });

  test("Java: subscription method sanitized, wire operation name preserved", () {
    const preamble = '''
$javaJsonEncoderDecorder
$javaClientAdapterNoParamSync
$javaGraphLinkWebSocketAdapter
''';
    final g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: javaReservedWords,
    )..parse(preamble + schema);

    final out = JavaClientSerializer(g, JavaSerializer(g, importPrefix: ""))
            .getSubscriptionsClass()
            ?.toFileContent() ??
        '';

    expect(out, contains("return_("));
    expect(out, contains('"return"'));
  });

  test("Kotlin: subscription method sanitized, wire operation name preserved",
      () {
    const preamble = '''
$kotlinJsonEncoderDecoder
$kotlinClientAdapterGql
''';
    final g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: kotlinReservedWords,
    )..parse(preamble + schema);

    final out = KotlinClientSerializer(g,
            KotlinSerializer(g,
                importPrefix: 'com.example', generateJsonMethods: true))
            .getSubscriptionsClass()
            ?.toFileContent() ??
        '';

    expect(out, contains("fun return_("));
    expect(out, contains('"return"'));
  });
}
