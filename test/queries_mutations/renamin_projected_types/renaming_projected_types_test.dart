import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("renaming projected types test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/queries_mutations/renamin_projected_types/renaming_projected_types_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    //renamed product input
    expect(g.inputs.keys, contains("MyProductInput"));
    //renamed responses
    expect(g.queries["getAllProducts"]!.getGeneratedTypeDefinition().token,
        equals("MyProductResp"));
  });
}
