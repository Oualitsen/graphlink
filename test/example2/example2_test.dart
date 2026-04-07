import 'dart:io';

import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("example2 test", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    final schema = File("test/example2/schema.graphql").readAsStringSync();
    final queries = File("test/example2/queries.graphql").readAsStringSync();
    final mutations =
        File("test/example2/mutations.graphql").readAsStringSync();
    final fragments =
        File("test/example2/fragments.graphql").readAsStringSync();
    g.parse("""
        $schema
        $fragments
        $queries
       $mutations
""");
  });

  test("depedecy_cycle_detection_test_indirect_dependency2", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    final text = File(
            "test/fragment/depedecy_cycle_detection/depedecy_cycle_detection_test_indirect_dependency.graphql")
        .readAsStringSync();
    expect(() => g.parse(text), throwsA(isA<ParseException>()));
  });

  test("client should not contain Instance of", () {
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
    final text = File("test/example2/schema.graphql").readAsStringSync();
    g.parse(text);
    var serializer = DartSerializer(g);

    var clientGen = DartClientSerializer(g, serializer);
    var client = clientGen.generateClient("package").toFileContent();
    var types = g.types.values
        .map((t) => serializer.serializeTypeDefinition(t, ""))
        .join("\n");
    var inputs = g.inputs.values
        .map((t) => serializer.serializeInputDefinition(t, ""))
        .join("\n");
    var enums = g.enums.values
        .map((t) => serializer.serializeEnumDefinition(t, ""))
        .join("\n");

    expect(client, isNot(stringContainsInOrder(["Instance of"])));
    expect(types, isNot(stringContainsInOrder(["Instance of"])));
    expect(inputs, isNot(stringContainsInOrder(["Instance of"])));
    expect(enums, isNot(stringContainsInOrder(["Instance of"])));
  });
}
