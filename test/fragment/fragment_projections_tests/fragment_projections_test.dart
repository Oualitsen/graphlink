import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  group("projected types test", () {
    const folderPath = "test/fragment/fragment_projections_tests";

    test("Simple projection", () {
      final GQGrammar g = GQGrammar();

      final text = File("$folderPath/simple_projection_schema.graphql")
          .readAsStringSync();

      final parser = g.buildFrom(g.fullGrammar().end());
      final parsed = parser.parse(text);

      expect(parsed is Success, true);
      var type = g.typedFragments["PersonFragment"];
      var fieldNames =
          type!.fragment.block.projections.values.map((e) => e.token);
      expect(fieldNames, containsAll(["firstName", "lastName", "middleName"]));
      expect(fieldNames, isNot(containsAll(["age"])));
    });

    test("Block test", () {
      final text = File("$folderPath/block_schema.graphql").readAsStringSync();

      final GQGrammar g = GQGrammar();
      final parser = g.buildFrom(g.fullGrammar().end());
      final parsed = parser.parse(text);
      expect(parsed is Success, true);
    });

    test("Fragment reference", () {
      final text = File("$folderPath/fragment_reference_schema.graphql")
          .readAsStringSync();

      final GQGrammar g = GQGrammar();
      final parser = g.buildFrom(g.fullGrammar().end());
      final parsed = parser.parse(text);
      expect(parsed is Success, true);
    });
  });
  group("Fragment tests", () {
    test("Fragments test", () async {
      final text = File("test/fragment/fragments.graphql").readAsStringSync();
      final GQGrammar g = GQGrammar();
      var parser = g.buildFrom(g.fullGrammar().end());

      var parsed = parser.parse(text);

      expect(parsed is Success, true);
      expect(g.fragments.length, greaterThanOrEqualTo(4));
    });

    test("Fragemnt Dependecies Test", () {
      final GQGrammar g = GQGrammar();
      var parser = g.buildFrom(g.fullGrammar().end());

      var parsed = parser.parse(
          File("test/fragment/fragment_dependecy.graphql").readAsStringSync());
      expect(parsed is Success, true);

      final frag = g.fragments["AddressFragment"]!;
      expect(
          frag.dependecies.map((e) => e.token), containsAll(["StateFragment"]));
      expect(g.fragments.length, greaterThanOrEqualTo(2));
    });
  });
}
