import 'dart:io';

import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("tojson_method_call_test", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    const path = "test/queries_mutations/tojson_method_call_test";

    final text =
        File("$path/tojson_method_call_test.graphql").readAsStringSync();
    g.parse(text);

    Directory("$path/gen").createSync();
    final dsc = DartClientSerializer(g, DartSerializer(g));
    var client = dsc.generateClient("package");
    expect(client, contains("'input': input?.toJson()"));
  });
}
