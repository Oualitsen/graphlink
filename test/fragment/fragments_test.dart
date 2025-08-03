import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_fragment.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() async {
  group("bms grammar", () {
    test("bms geammar fragment dependecy", () {
      final text = File("test/schema.graphql").readAsStringSync();

      final GQGrammar g = GQGrammar();
      var parser = g.buildFrom(g.fullGrammar().end());
      var parsed = parser.parse(text);

      expect(parsed is Success, true);
      var frag = g.fragments["userFrag"]!;
      expect(
          frag.dependecies.map((e) => (e as GQFragmentDefinition).fragmentName),
          contains("beFrag"));
    });
  });
  group("Fragment tests", () {
    test("Fragments test 1", () async {
      final text = File("test/fragment/fragments.graphql").readAsStringSync();
      final GQGrammar g = GQGrammar();
      var parser = g.buildFrom(g.fullGrammar().end());

      var parsed = parser.parse(text);

      expect(parsed is Success, true);
      expect(g.fragments.length, greaterThanOrEqualTo(4));
    });

    test("Fragemnt Dependecies Test 1", () {
      final GQGrammar g = GQGrammar();
      var parser = g.buildFrom(g.fullGrammar().end());

      var parsed = parser.parse(
          File("test/fragment/fragment_dependecy.graphql").readAsStringSync());
      expect(parsed is Success, true);

      final frag = g.fragments["AddressFragment"]!;
      expect(
          frag.dependecies.map((e) => (e as GQFragmentDefinition).fragmentName),
          containsAll(["StateFragment"]));
      expect(g.fragments.length, greaterThanOrEqualTo(2));
    });
  });
}
