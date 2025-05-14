import 'dart:io';

import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:test/test.dart';
import 'package:logger/logger.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("Nullable Arguments", () {
    var logger = Logger();
    final GQGrammar g = GQGrammar(nullableFieldsRequired: false);
    logger.i("________________________________________init______________________");

    var parser = g.buildFrom(g.fullGrammar().end());
    logger.i("reading file");

    final text = File("test/nullable_args/nullable_args_test.graphql").readAsStringSync();
    logger.i("file read $test");

    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var inputs = g.generateInputs();

    var types = g.generateTypes();
    expect(inputs, contains("this.middleName"));
    expect(inputs, isNot(contains("required this.middleName")));

    expect(types, contains("this.middleName"));
    expect(types, isNot(contains("required this.middleName")));
  });
  test("toContructoDeclaration test ", () {
    final GQGrammar g1 = GQGrammar(nullableFieldsRequired: false);
    final nullableString = GQType("String", true);
    final nonNullableString = GQType("String", false);
    final nullableField = GQField(name: "name", type: nullableString, arguments: [], directives: []);
    final nonNullableField = GQField(name: "name", type: nonNullableString, arguments: [], directives: []);

    var dartContructorTypeNullable = g1.toContructoDeclaration(nullableField);
    var dartContructorTypeNonNullable = g1.toContructoDeclaration(nonNullableField);

    expect(dartContructorTypeNullable, "this.name");
    expect(dartContructorTypeNonNullable, "required this.name");

    final GQGrammar g2 = GQGrammar(nullableFieldsRequired: true);
    var dartContructorTypeNullable2 = g2.toContructoDeclaration(nullableField);
    var dartContructorTypeNonNullable2 = g2.toContructoDeclaration(nonNullableField);

    expect(dartContructorTypeNullable2, "required this.name");
    expect(dartContructorTypeNonNullable2, "required this.name");
  });
}
