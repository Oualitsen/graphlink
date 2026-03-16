import 'dart:io';

import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("tojson_method_call_test", () {
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
    const path = "test/queries_mutations/tojson_method_call_test";

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File("$path/tojson_method_call_test.graphql").readAsStringSync();
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    Directory("$path/gen").createSync();
    final dsc = DartClientSerializer(g, DartSerializer(g));
    var client = dsc.generateClient("package");
    expect(client, contains("'input': input?.toJson()"));
  });
}
