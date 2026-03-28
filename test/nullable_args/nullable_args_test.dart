import 'dart:io';

import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:logger/logger.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("Nullable Arguments", () {
    var logger = Logger();
    final GLParser g = GLParser(nullableFieldsRequired: false);
    logger.i(
        "________________________________________init______________________");

    logger.i("reading file");

    final text = File("test/nullable_args/nullable_args_test.graphql")
        .readAsStringSync();
    logger.i("file read $test");

    g.parse(text);

    var serializer = DartSerializer(g);
    var types = g.types.values
        .map((t) => serializer.serializeTypeDefinition(t, ""))
        .join("\n");
    var inputs = g.inputs.values
        .map((t) => serializer.serializeInputDefinition(t, ""))
        .join("\n");

    expect(inputs, contains("this.middleName"));
    expect(inputs, isNot(contains("required this.middleName")));

    expect(types, contains("this.middleName"));
    expect(types, isNot(contains("required this.middleName")));
  });
  test("toContructoDeclaration test ", () {
    final GLParser g1 = GLParser(nullableFieldsRequired: false);
    final nullableString = GLType("String".toToken(), true);
    final nonNullableString = GLType("String".toToken(), false);
    final nullableField = GLField(
        name: "name".toToken(),
        type: nullableString,
        arguments: [],
        directives: []);
    final nonNullableField = GLField(
        name: "name".toToken(),
        type: nonNullableString,
        arguments: [],
        directives: []);
    var serializer1 = DartSerializer(g1);

    var dartContructorTypeNullable =
        serializer1.toConstructorDeclaration(nullableField);
    var dartContructorTypeNonNullable =
        serializer1.toConstructorDeclaration(nonNullableField);

    expect(dartContructorTypeNullable, "this.name");
    expect(dartContructorTypeNonNullable, "required this.name");

    final GLParser g2 = GLParser(nullableFieldsRequired: true);
    var serializer2 = DartSerializer(g2);

    var dartContructorTypeNullable2 =
        serializer2.toConstructorDeclaration(nullableField);
    var dartContructorTypeNonNullable2 =
        serializer2.toConstructorDeclaration(nonNullableField);

    expect(dartContructorTypeNullable2, "required this.name");
    expect(dartContructorTypeNonNullable2, "required this.name");
  });
}
