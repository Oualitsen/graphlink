import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("tojson_method_call_test", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    const path = "test/queries_mutations/tojson_method_call_test";

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File("$path/tojson_method_call_test.graphql").readAsStringSync();
    var parsed = parser.parse(text);

    expect(parsed.isSuccess, true);
    Directory("$path/gen").createSync();
    File("$path/gen/client.gq.dart").writeAsStringSync(g.generateClient());
    File("$path/gen/types.gq.dart").writeAsStringSync(g.generateTypes());
    File("$path/gen/inputs.gq.dart").writeAsStringSync(g.generateInputs());
    File("$path/gen/enums.gq.dart").writeAsStringSync(g.generateEnums());
  });
}
