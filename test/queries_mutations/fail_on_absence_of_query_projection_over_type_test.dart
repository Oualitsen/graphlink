import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("fail_on_absence_of_query_projection_over_type_test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/queries_mutations/fail_on_absence_of_query_projection_over_type_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);
    expect(parsed.isSuccess, true);
    print(g.queries["Product"]?.fragments(g).map((e) => e.token));
  });
}
