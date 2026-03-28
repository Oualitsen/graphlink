import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_fragment.dart';

final GLParser g = GLParser();

void main() async {
  group("bms grammar", () {
    test("bms geammar fragment dependecy", () {
      final text = File("test/schema.graphql").readAsStringSync();

      final GLParser g = GLParser();

      g.parse(text);

      var frag = g.fragments["userFrag"]!;
      expect(
          frag.dependecies.map((e) => (e as GLFragmentDefinition).fragmentName),
          contains("beFrag"));
    });
  });
  group("Fragment tests", () {
    test("Fragments test 1", () async {
      final text = File("test/fragment/fragments.graphql").readAsStringSync();
      final GLParser g = GLParser();

      g.parse(text);

      expect(g.fragments.length, greaterThanOrEqualTo(4));
    });

    test("Fragemnt Dependecies Test 1", () {
      final GLParser g = GLParser();

      g.parse(
          File("test/fragment/fragment_dependecy.graphql").readAsStringSync());

      final frag = g.fragments["AddressFragment"]!;
      expect(
          frag.dependecies.map((e) => (e as GLFragmentDefinition).fragmentName),
          containsAll(["StateFragment"]));
      expect(g.fragments.length, greaterThanOrEqualTo(2));
    });
  });
}
