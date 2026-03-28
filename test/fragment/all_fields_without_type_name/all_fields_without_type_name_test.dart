import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("all_fields_without_type_name 1", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    final text = File(
            "test/fragment/all_fields_without_type_name/all_fields_without_type_name_test.graphql")
        .readAsStringSync();
    g.parse(text);
    var vehicleFrag = g.getFragmentByName("_all_fields_Vehicle")!;
    var depencyFragNames = vehicleFrag.dependecies.map((e) => e.token).toList();

    expect(depencyFragNames, contains("_all_fields_Make"));
  });
}
