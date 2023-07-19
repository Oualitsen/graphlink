import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("tojson_method_call_test", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/queries_mutations/tojson_method_call_test/tojson_method_call_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);

    expect(parsed.isSuccess, true);

    File("test/queries_mutations/tojson_method_call_test/gen/client.gq.dart")
        .writeAsStringSync(g.generateClient());
    File("test/queries_mutations/tojson_method_call_test/gen/types.gq.dart")
        .writeAsStringSync(g.generateTypes());
    File("test/queries_mutations/tojson_method_call_test/gen/inputs.gq.dart")
        .writeAsStringSync(g.generateInputs());
  });
}
