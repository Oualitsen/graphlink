import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  group("projected types test", () {
    const folderPath = "test/fragment/fragment_projections_tests";

    test("Simple projection", () {
      final GLParser g = GLParser();

      final text = File("$folderPath/simple_projection_schema.graphql")
          .readAsStringSync();

      g.parse(text);

      var type = g.typedFragments["PersonFragment"];
      var fieldNames =
          type!.fragment.block.projections.values.map((e) => e.token);
      expect(fieldNames, containsAll(["firstName", "lastName", "middleName"]));
      expect(fieldNames, isNot(containsAll(["age"])));
    });

    test("Block test", () {
      final text = File("$folderPath/block_schema.graphql").readAsStringSync();

      final GLParser g = GLParser();

      g.parse(text);
    });

    test("Fragment reference", () {
      final text = File("$folderPath/fragment_reference_schema.graphql")
          .readAsStringSync();

      final GLParser g = GLParser();

      g.parse(text);
    });
  });
  group("Fragment tests", () {
    test("Fragments test 2", () async {
      final text = File("test/fragment/fragments.graphql").readAsStringSync();
      final GLParser g = GLParser();

      g.parse(text);

      expect(g.fragments.length, greaterThanOrEqualTo(4));
    });

    test("Fragemnt Dependecies Test 2", () {
      final GLParser g = GLParser();

      g.parse(
          File("test/fragment/fragment_dependecy.graphql").readAsStringSync());

      final frag = g.fragments["AddressFragment"]!;
      expect(
          frag.dependecies.map((e) => e.token), containsAll(["StateFragment"]));
      expect(g.fragments.length, greaterThanOrEqualTo(2));
    });
  });
}
