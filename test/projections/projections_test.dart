import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("projections_test", () {
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);

    final text =
        File("test/projections/projections_test.graphql").readAsStringSync();
    g.parse(text);

    var user = g.projectedTypes["User"];
    var address = g.projectedTypes["Address"];
    var state = g.projectedTypes["State"];

    //should generate User and Address instead of User_*_* and Address_all_types_fragmentAddress
    expect(user != null, true);
    expect(address != null, true);
    expect(state != null, true);
  });

  test("projections_test2 on glSkipOnClient", () {
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);

    final text =
        File("test/projections/projections2_test.graphql").readAsStringSync();
    g.parse(text);

    var projectedTypes = g.projectedTypes;
    expect(projectedTypes.keys, contains("Notif"));
  });
}
