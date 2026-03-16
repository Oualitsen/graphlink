import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("fail_on_absence_of_query_projection_over_type_test 2", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File("test/queries_mutations/query_element_alias_test.graphql").readAsStringSync();
    var r = parser.parse(text);
    expect(r is Success, true);
    expect(g.projectedTypes.keys, contains("DriverResponse"));
    var response = g.projectedTypes["DriverResponse"]!;

    expect(response.fields.where((field) => field.name.token == "driver"), isNotEmpty);
  });
}
