import 'dart:io';

import 'package:retrofit_graphql/src/serializers/dart_client_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("tojson_method_call_test", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    const path = "test/queries_mutations/tojson_method_call_test";

    var parser = g.buildFrom(g.fullGrammar().end());

    final text =
        File("$path/tojson_method_call_test.graphql").readAsStringSync();
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    Directory("$path/gen").createSync();
    final dsc = DartClientSerializer(g);
    var client = dsc.generateClient();
    expect(client, contains("'input': input?.toJson()"));
  });
}
