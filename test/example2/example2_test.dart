import 'dart:io';

import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("example2 test", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);

    var parser = g.buildFrom(g.fullGrammar().end());

    final schema = File("test/example2/schema.graphql").readAsStringSync();
    final queries = File("test/example2/queries.graphql").readAsStringSync();
    final mutations =
        File("test/example2/mutations.graphql").readAsStringSync();
    final fragments =
        File("test/example2/fragments.graphql").readAsStringSync();
    var parsed = parser.parse("""
        $schema
        $fragments
        $queries
       $mutations
""");
    expect(parsed is Success, true);
  });

  test("depedecy_cycle_detection_test_indirect_dependency", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/fragment/depedecy_cycle_detection/depedecy_cycle_detection_test_indirect_dependency.graphql")
        .readAsStringSync();
    expect(() => parser.parse(text), throwsA(isA<ParseException>()));
  });
}
