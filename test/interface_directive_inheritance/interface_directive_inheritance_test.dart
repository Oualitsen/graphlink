import 'dart:io';

import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  final typeMapping = {
    "ID": "String",
    "String": "String",
    "Float": "Double",
    "Int": "Integer",
    "Boolean": "Boolean",
    "Null": "null",
    "Long": "Long"
  };

  test("interface directive inheritance", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/interface_directive_inheritance/interface_directive_inheritance.graphql")
        .readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var interface = g.interfaces["Entity"]!;
    var idField = interface.getFieldByName("id")!;

    expect(idField.getDirectiveByName("@gqId"), isNotNull);

    var type = g.getType("User");
    var typeIdField = type.getFieldByName("id")!;
    expect(typeIdField.getDirectiveByName("@gqId"), isNotNull);
    var iCreationDate =
        interface.getFieldByName("creationDate")!.getDirectiveByName("@gqCreationDate")!.getArgValue("value");
    expect(iCreationDate, 1);

    var tCreationDate =
        type.getFieldByName("creationDate")!.getDirectiveByName("@gqCreationDate")!.getArgValue("value");
    expect(tCreationDate, 2);
  });
}
