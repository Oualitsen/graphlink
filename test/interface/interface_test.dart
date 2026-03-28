import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("Input transformation 2", () {
    final GLParser g = GLParser();

    final text =
        File("test/interface/interface_schema.graphql").readAsStringSync();

    g.parse(text);

    expect(g.interfaces.length, greaterThanOrEqualTo(1));
    final i = g.interfaces["UserInput1"]!;
    expect(i.fieldNames, containsAll(["firstName", "lastName", "middleName"]));

    final i2 = g.interfaces["AddressInput1"]!;
    expect(i2.fieldNames, containsAll(["street", "wilayaId", "city"]));
    expect(i2.fieldNames,
        isNot(containsAll(["firstName1", "lastName1", "middleName1"])));
    expect(i2.getInterfaceNames(), contains("UserInput1"));
  });
}
