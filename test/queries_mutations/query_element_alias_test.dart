import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("fail_on_absence_of_query_projection_over_type_test 2", () {
    final GLParser g = GLParser();

    final text = File("test/queries_mutations/query_element_alias_test.graphql")
        .readAsStringSync();
    g.parse(text);

    expect(g.projectedTypes.keys, contains("DriverResponse"));
    var response = g.projectedTypes["DriverResponse"]!;

    expect(response.fields.where((field) => field.name.token == "driver"),
        isNotEmpty);
  });
}
